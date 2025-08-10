#!/bin/bash

# Cgroup支持检查脚本
# 检查系统是否符合Cgroup资源限制的要求

set -e

# 配置变量
CLEANUP_AFTER_TEST=${CLEANUP_AFTER_TEST:-true}
TEST_CGROUP_NAME="datakit_test_$$"
TEST_CPU_LIMIT="200000"  # 200% CPU (2 cores at 100%)
TEST_MEMORY_LIMIT="512"  # 512MB
TEST_DURATION=10         # 测试持续时间(秒)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 清理函数
cleanup() {
    if [ "$CLEANUP_AFTER_TEST" = "true" ]; then
        log_info "清理测试资源..."
        
        # 停止测试进程
        if [ -n "$TEST_PID" ]; then
            kill -TERM "$TEST_PID" 2>/dev/null || true
            wait "$TEST_PID" 2>/dev/null || true
        fi
        
        # 删除cgroup目录
        if [ -d "/sys/fs/cgroup/cpu/$TEST_CGROUP_NAME" ]; then
            rmdir "/sys/fs/cgroup/cpu/$TEST_CGROUP_NAME" 2>/dev/null || true
        fi
        
        if [ -d "/sys/fs/cgroup/memory/$TEST_CGROUP_NAME" ]; then
            rmdir "/sys/fs/cgroup/memory/$TEST_CGROUP_NAME" 2>/dev/null || true
        fi
        
        if [ -d "/sys/fs/cgroup/cpu,cpuacct/$TEST_CGROUP_NAME" ]; then
            rmdir "/sys/fs/cgroup/cpu,cpuacct/$TEST_CGROUP_NAME" 2>/dev/null || true
        fi
        
        if [ -d "/sys/fs/cgroup/unified/$TEST_CGROUP_NAME" ]; then
            rmdir "/sys/fs/cgroup/unified/$TEST_CGROUP_NAME" 2>/dev/null || true
        fi
    fi
}

# 设置退出时清理
trap cleanup EXIT

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检测cgroup版本
detect_cgroup_version() {
    log_info "检测cgroup版本和配置..."
    
    # 检查cgroup挂载点
    local cgroup_mounts=$(mount | grep -E "cgroup|cgroup2" | awk '{print $3}' | sort -u)
    log_info "检测到的cgroup挂载点: $cgroup_mounts"
    
    # 检查cgroup文件系统类型
    local cgroup_fs=$(mount | grep -E "cgroup|cgroup2" | awk '{print $5}' | sort -u)
    log_info "cgroup文件系统类型: $cgroup_fs"
    
    # 检查cgroup v2支持
    if [ -d "/sys/fs/cgroup/unified" ] || [ -d "/sys/fs/cgroup" ] && [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        CGROUP_VERSION="v2"
        CGROUP_ROOT="/sys/fs/cgroup"
        
        # 检查v2控制器
        if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
            local controllers=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null | tr '\n' ' ')
            log_success "检测到cgroup v2，可用控制器: $controllers"
        else
            log_success "检测到cgroup v2"
        fi
        
        # 检查具体控制器支持
        if [ -f "/sys/fs/cgroup/cpu.max" ]; then
            log_info "CPU控制器: 支持"
        else
            log_warning "CPU控制器: 不支持"
        fi
        
        if [ -f "/sys/fs/cgroup/memory.max" ]; then
            log_info "内存控制器: 支持"
        else
            log_warning "内存控制器: 不支持"
        fi
        
    # 检查cgroup v1支持
    elif [ -d "/sys/fs/cgroup/cpu" ] || [ -d "/sys/fs/cgroup/memory" ] || [ -d "/sys/fs/cgroup/cpu,cpuacct" ]; then
        CGROUP_VERSION="v1"
        CGROUP_ROOT="/sys/fs/cgroup"
        
        log_success "检测到cgroup v1"
        
        # 检查v1控制器
        local cpu_controller=""
        local memory_controller=""
        
        if [ -d "/sys/fs/cgroup/cpu" ]; then
            cpu_controller="/sys/fs/cgroup/cpu"
            log_info "CPU控制器: /sys/fs/cgroup/cpu"
        elif [ -d "/sys/fs/cgroup/cpu,cpuacct" ]; then
            cpu_controller="/sys/fs/cgroup/cpu,cpuacct"
            log_info "CPU控制器: /sys/fs/cgroup/cpu,cpuacct"
        else
            log_warning "CPU控制器: 未找到"
        fi
        
        if [ -d "/sys/fs/cgroup/memory" ]; then
            memory_controller="/sys/fs/cgroup/memory"
            log_info "内存控制器: /sys/fs/cgroup/memory"
        else
            log_warning "内存控制器: 未找到"
        fi
        
        # 检查控制器功能
        if [ -n "$cpu_controller" ]; then
            if [ -f "$cpu_controller/cpu.cfs_quota_us" ] && [ -f "$cpu_controller/cpu.cfs_period_us" ]; then
                log_info "CPU限制功能: 支持"
            else
                log_warning "CPU限制功能: 不支持"
            fi
        fi
        
        if [ -n "$memory_controller" ]; then
            if [ -f "$memory_controller/memory.limit_in_bytes" ]; then
                log_info "内存限制功能: 支持"
            else
                log_warning "内存限制功能: 不支持"
            fi
        fi
        
    # 检查混合模式（v1和v2共存）
    elif [ -d "/sys/fs/cgroup/unified" ] && ([ -d "/sys/fs/cgroup/cpu" ] || [ -d "/sys/fs/cgroup/memory" ]); then
        CGROUP_VERSION="hybrid"
        CGROUP_ROOT="/sys/fs/cgroup"
        log_success "检测到cgroup混合模式（v1和v2共存）"
        
        # 检查v2控制器
        if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
            local controllers=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null | tr '\n' ' ')
            log_info "v2可用控制器: $controllers"
        fi
        
        # 检查v1控制器
        if [ -d "/sys/fs/cgroup/cpu" ] || [ -d "/sys/fs/cgroup/cpu,cpuacct" ]; then
            log_info "v1 CPU控制器: 可用"
        fi
        
        if [ -d "/sys/fs/cgroup/memory" ]; then
            log_info "v1 内存控制器: 可用"
        fi
        
    # 检查systemd cgroup
    elif [ -d "/sys/fs/cgroup/systemd" ]; then
        CGROUP_VERSION="systemd"
        CGROUP_ROOT="/sys/fs/cgroup"
        log_success "检测到systemd cgroup"
        
        # 检查systemd cgroup配置
        if systemctl --version >/dev/null 2>&1; then
            local systemd_cgroup=$(systemctl show --property=ControlGroup | cut -d'=' -f2)
            log_info "systemd cgroup路径: $systemd_cgroup"
        fi
        
    # 检查其他可能的cgroup路径
    elif [ -d "/cgroup" ]; then
        CGROUP_VERSION="legacy"
        CGROUP_ROOT="/cgroup"
        log_success "检测到legacy cgroup路径: /cgroup"
        
        # 检查legacy控制器
        if [ -d "/cgroup/cpu" ]; then
            log_info "Legacy CPU控制器: 可用"
        fi
        
        if [ -d "/cgroup/memory" ]; then
            log_info "Legacy 内存控制器: 可用"
        fi
        
    else
        log_error "未检测到cgroup支持"
        log_info "请检查以下项目："
        log_info "1. 内核是否支持cgroup"
        log_info "2. cgroup是否已挂载"
        log_info "3. 是否有足够的权限访问cgroup文件系统"
        
        # 尝试诊断问题
        log_info "=== 诊断信息 ==="
        log_info "内核版本: $(uname -r)"
        log_info "cgroup相关内核模块:"
        lsmod | grep -i cgroup || log_info "  无相关模块"
        log_info "挂载点信息:"
        mount | grep -E "cgroup|cgroup2" || log_info "  无cgroup挂载"
        log_info "cgroup文件系统:"
        ls -la /sys/fs/cgroup/ 2>/dev/null || log_info "  /sys/fs/cgroup/ 不存在"
        
        exit 1
    fi
    
    # 检查cgroup权限
    if [ ! -w "$CGROUP_ROOT" ]; then
        log_error "没有cgroup目录的写权限: $CGROUP_ROOT"
        exit 1
    fi
    
    # 检查cgroup功能
    log_info "=== cgroup功能检查 ==="
    log_info "版本: $CGROUP_VERSION"
    log_info "根目录: $CGROUP_ROOT"
    log_info "当前进程cgroup: $(cat /proc/self/cgroup 2>/dev/null || echo '无法获取')"
    
    # 检查是否支持嵌套cgroup
    if [ "$CGROUP_VERSION" = "v2" ]; then
        if [ -w "$CGROUP_ROOT" ]; then
            log_info "嵌套cgroup支持: 是"
        else
            log_warning "嵌套cgroup支持: 否"
        fi
    fi
}

# 检查必要工具
check_tools() {
    log_info "检查必要工具..."
    
    local tools=("bc" "awk" "grep" "cat" "echo")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必要工具: ${missing_tools[*]}"
        exit 1
    fi
    
    log_success "所有必要工具已安装"
}

# 创建测试cgroup
create_test_cgroup() {
    log_info "创建测试cgroup: $TEST_CGROUP_NAME"
    
    case "$CGROUP_VERSION" in
        "v2")
            # cgroup v2
            mkdir -p "$CGROUP_ROOT/$TEST_CGROUP_NAME"
            
            # 设置CPU限制
            if [ -f "$CGROUP_ROOT/cpu.max" ]; then
                echo "$TEST_CPU_LIMIT" > "$CGROUP_ROOT/$TEST_CGROUP_NAME/cpu.max"
                log_info "设置CPU限制: $TEST_CPU_LIMIT"
            else
                log_warning "CPU控制器不可用，跳过CPU限制设置"
            fi
            
            # 设置内存限制
            if [ -f "$CGROUP_ROOT/memory.max" ]; then
                echo "${TEST_MEMORY_LIMIT}M" > "$CGROUP_ROOT/$TEST_CGROUP_NAME/memory.max"
                log_info "设置内存限制: ${TEST_MEMORY_LIMIT}MB"
            else
                log_warning "内存控制器不可用，跳过内存限制设置"
            fi
            ;;
            
        "v1")
            # cgroup v1
            # CPU限制
            if [ -d "$CGROUP_ROOT/cpu" ]; then
                mkdir -p "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME"
                echo "$TEST_CPU_LIMIT" > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/cpu.cfs_quota_us"
                echo "100000" > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/cpu.cfs_period_us"
                log_info "设置CPU限制: $TEST_CPU_LIMIT/100000"
            elif [ -d "$CGROUP_ROOT/cpu,cpuacct" ]; then
                mkdir -p "$CGROUP_ROOT/cpu,cpuacct/$TEST_CGROUP_NAME"
                echo "$TEST_CPU_LIMIT" > "$CGROUP_ROOT/cpu,cpuacct/$TEST_CGROUP_NAME/cpu.cfs_quota_us"
                echo "100000" > "$CGROUP_ROOT/cpu,cpuacct/$TEST_CGROUP_NAME/cpu.cfs_period_us"
                log_info "设置CPU限制: $TEST_CPU_LIMIT/100000"
            else
                log_warning "CPU控制器不可用，跳过CPU限制设置"
            fi
            
            # 内存限制
            if [ -d "$CGROUP_ROOT/memory" ]; then
                mkdir -p "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME"
                echo "$((TEST_MEMORY_LIMIT * 1024 * 1024))" > "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME/memory.limit_in_bytes"
                log_info "设置内存限制: $((TEST_MEMORY_LIMIT * 1024 * 1024)) bytes"
            else
                log_warning "内存控制器不可用，跳过内存限制设置"
            fi
            ;;
            
        "hybrid")
            # 混合模式 - 优先使用v2
            if [ -f "$CGROUP_ROOT/cpu.max" ]; then
                mkdir -p "$CGROUP_ROOT/$TEST_CGROUP_NAME"
                echo "$TEST_CPU_LIMIT" > "$CGROUP_ROOT/$TEST_CGROUP_NAME/cpu.max"
                echo "${TEST_MEMORY_LIMIT}M" > "$CGROUP_ROOT/$TEST_CGROUP_NAME/memory.max"
                log_info "使用v2控制器设置限制"
            else
                # 回退到v1
                if [ -d "$CGROUP_ROOT/cpu" ]; then
                    mkdir -p "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME"
                    echo "$TEST_CPU_LIMIT" > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/cpu.cfs_quota_us"
                    echo "100000" > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/cpu.cfs_period_us"
                fi
                if [ -d "$CGROUP_ROOT/memory" ]; then
                    mkdir -p "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME"
                    echo "$((TEST_MEMORY_LIMIT * 1024 * 1024))" > "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME/memory.limit_in_bytes"
                fi
                log_info "使用v1控制器设置限制"
            fi
            ;;
            
        "systemd")
            # systemd cgroup
            log_warning "systemd cgroup模式，使用systemd命令创建cgroup"
            if systemctl --version >/dev/null 2>&1; then
                # 尝试使用systemd创建cgroup
                systemctl set-property user.slice CPUQuota="$TEST_CPU_LIMIT%" 2>/dev/null || true
                systemctl set-property user.slice MemoryLimit="${TEST_MEMORY_LIMIT}M" 2>/dev/null || true
                log_info "通过systemd设置资源限制"
            else
                log_error "systemctl命令不可用"
                exit 1
            fi
            ;;
            
        "legacy")
            # legacy cgroup
            if [ -d "$CGROUP_ROOT/cpu" ]; then
                mkdir -p "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME"
                echo "$TEST_CPU_LIMIT" > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/cpu.cfs_quota_us"
                echo "100000" > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/cpu.cfs_period_us"
            fi
            if [ -d "$CGROUP_ROOT/memory" ]; then
                mkdir -p "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME"
                echo "$((TEST_MEMORY_LIMIT * 1024 * 1024))" > "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME/memory.limit_in_bytes"
            fi
            log_info "使用legacy cgroup设置限制"
            ;;
            
        *)
            log_error "不支持的cgroup版本: $CGROUP_VERSION"
            exit 1
            ;;
    esac
    
    log_success "测试cgroup创建成功"
}

# 启动CPU密集型测试进程
start_cpu_test() {
    log_info "启动CPU密集型测试进程..."
    
    # 创建测试脚本
    cat > /tmp/cpu_test_$$.sh << 'EOF'
#!/bin/bash
while true; do
    # 执行CPU密集型计算
    echo "scale=1000; 4*a(1)" | bc -l >/dev/null 2>&1
done
EOF
    
    chmod +x /tmp/cpu_test_$$.sh
    
    # 在cgroup中启动进程
    if [ "$CGROUP_VERSION" = "v2" ]; then
        echo $$ > "$CGROUP_ROOT/$TEST_CGROUP_NAME/cgroup.procs"
        /tmp/cpu_test_$$.sh &
    else
        if [ -d "$CGROUP_ROOT/cpu" ]; then
            echo $$ > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/tasks"
        elif [ -d "$CGROUP_ROOT/cpu,cpuacct" ]; then
            echo $$ > "$CGROUP_ROOT/cpu,cpuacct/$TEST_CGROUP_NAME/tasks"
        fi
        
        if [ -d "$CGROUP_ROOT/memory" ]; then
            echo $$ > "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME/tasks"
        fi
        
        /tmp/cpu_test_$$.sh &
    fi
    
    TEST_PID=$!
    log_success "测试进程已启动 (PID: $TEST_PID)"
}

# 启动内存密集型测试进程
start_memory_test() {
    log_info "启动内存密集型测试进程..."
    
    # 创建测试脚本
    cat > /tmp/memory_test_$$.sh << 'EOF'
#!/bin/bash
# 尝试分配超过限制的内存
declare -a arrays
i=0
while true; do
    # 每次分配10MB
    arrays[$i]=$(head -c 10M /dev/zero)
    i=$((i + 1))
    sleep 1
done
EOF
    
    chmod +x /tmp/memory_test_$$.sh
    
    # 在cgroup中启动进程
    if [ "$CGROUP_VERSION" = "v2" ]; then
        echo $$ > "$CGROUP_ROOT/$TEST_CGROUP_NAME/cgroup.procs"
        /tmp/memory_test_$$.sh &
    else
        if [ -d "$CGROUP_ROOT/cpu" ]; then
            echo $$ > "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/tasks"
        elif [ -d "$CGROUP_ROOT/cpu,cpuacct" ]; then
            echo $$ > "$CGROUP_ROOT/cpu,cpuacct/$TEST_CGROUP_NAME/tasks"
        fi
        
        if [ -d "$CGROUP_ROOT/memory" ]; then
            echo $$ > "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME/tasks"
        fi
        
        /tmp/memory_test_$$.sh &
    fi
    
    MEMORY_TEST_PID=$!
    log_success "内存测试进程已启动 (PID: $MEMORY_TEST_PID)"
}

# 监控CPU使用率
monitor_cpu_usage() {
    log_info "监控CPU使用率 (${TEST_DURATION}秒)..."
    
    local max_cpu=0
    local start_time=$(date +%s)
    
    while [ $(($(date +%s) - start_time)) -lt $TEST_DURATION ]; do
        if [ "$CGROUP_VERSION" = "v2" ]; then
            local cpu_usage=$(cat "$CGROUP_ROOT/$TEST_CGROUP_NAME/cpu.stat" | grep "usage_usec" | awk '{print $2}')
            local cpu_percent=$(echo "scale=2; $cpu_usage / 10000" | bc)
        else
            local cpu_usage=0
            if [ -d "$CGROUP_ROOT/cpu" ]; then
                cpu_usage=$(cat "$CGROUP_ROOT/cpu/$TEST_CGROUP_NAME/cpuacct.usage" 2>/dev/null || echo "0")
            elif [ -d "$CGROUP_ROOT/cpu,cpuacct" ]; then
                cpu_usage=$(cat "$CGROUP_ROOT/cpu,cpuacct/$TEST_CGROUP_NAME/cpuacct.usage" 2>/dev/null || echo "0")
            fi
            local cpu_percent=$(echo "scale=2; $cpu_usage / 10000000" | bc)
        fi
        
        if (( $(echo "$cpu_percent > $max_cpu" | bc -l) )); then
            max_cpu=$cpu_percent
        fi
        
        sleep 1
    done
    
    echo "$max_cpu"
}

# 监控内存使用率
monitor_memory_usage() {
    log_info "监控内存使用率..."
    
    if [ "$CGROUP_VERSION" = "v2" ]; then
        local memory_usage=$(cat "$CGROUP_ROOT/$TEST_CGROUP_NAME/memory.current" 2>/dev/null || echo "0")
        local memory_mb=$(echo "scale=2; $memory_usage / 1024 / 1024" | bc)
    else
        local memory_usage=0
        if [ -d "$CGROUP_ROOT/memory" ]; then
            memory_usage=$(cat "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME/memory.usage_in_bytes" 2>/dev/null || echo "0")
        fi
        local memory_mb=$(echo "scale=2; $memory_usage / 1024 / 1024" | bc)
    fi
    
    echo "$memory_mb"
}

# 检查OOM事件
check_oom_events() {
    log_info "检查OOM事件..."
    
    if [ "$CGROUP_VERSION" = "v2" ]; then
        local oom_count=$(cat "$CGROUP_ROOT/$TEST_CGROUP_NAME/memory.events" | grep "oom_kill" | awk '{print $2}' 2>/dev/null || echo "0")
    else
        local oom_count=0
        if [ -d "$CGROUP_ROOT/memory" ]; then
            oom_count=$(cat "$CGROUP_ROOT/memory/$TEST_CGROUP_NAME/memory.oom_control" | grep "oom_kill_disable" | awk '{print $2}' 2>/dev/null || echo "0")
        fi
    fi
    
    echo "$oom_count"
}

# 验证测试结果
verify_results() {
    log_info "验证测试结果..."
    
    local cpu_usage=$1
    local memory_usage=$2
    local oom_count=$3
    
    local cpu_test_passed=false
    local memory_test_passed=false
    
    # 验证CPU限制
    if (( $(echo "$cpu_usage <= 200" | bc -l) )); then
        log_success "CPU限制测试通过: ${cpu_usage}% <= 200%"
        cpu_test_passed=true
    else
        log_error "CPU限制测试失败: ${cpu_usage}% > 200%"
    fi
    
    # 验证内存限制
    if (( $(echo "$memory_usage <= 512" | bc -l) )) || [ "$oom_count" -gt 0 ]; then
        if [ "$oom_count" -gt 0 ]; then
            log_success "内存限制测试通过: 触发OOM事件 ($oom_count 次)"
        else
            log_success "内存限制测试通过: ${memory_usage}MB <= 512MB"
        fi
        memory_test_passed=true
    else
        log_error "内存限制测试失败: ${memory_usage}MB > 512MB 且无OOM事件"
    fi
    
    # 输出最终结果
    echo
    log_info "=== 测试结果汇总 ==="
    echo "Cgroup版本: $CGROUP_VERSION"
    echo "CPU使用率: ${cpu_usage}%"
    echo "内存使用率: ${memory_usage}MB"
    echo "OOM事件数: $oom_count"
    echo
    
    if [ "$cpu_test_passed" = "true" ] && [ "$memory_test_passed" = "true" ]; then
        log_success "所有测试通过！系统支持cgroup资源限制"
        exit 0
    else
        log_error "部分测试失败！系统可能不完全支持cgroup资源限制"
        exit 1
    fi
}

# 主函数
main() {
    log_info "开始cgroup支持检查..."
    
    # 检查root权限
    check_root
    
    # 检查必要工具
    check_tools
    
    # 检测cgroup版本
    detect_cgroup_version
    
    # 创建测试cgroup
    create_test_cgroup
    
    # 启动CPU测试
    start_cpu_test
    
    # 监控CPU使用率
    local max_cpu=$(monitor_cpu_usage)
    
    # 停止CPU测试进程
    kill -TERM "$TEST_PID" 2>/dev/null || true
    wait "$TEST_PID" 2>/dev/null || true
    
    # 启动内存测试
    start_memory_test
    
    # 等待一段时间让内存测试运行
    sleep 5
    
    # 监控内存使用率
    local memory_usage=$(monitor_memory_usage)
    
    # 检查OOM事件
    local oom_count=$(check_oom_events)
    
    # 停止内存测试进程
    kill -TERM "$MEMORY_TEST_PID" 2>/dev/null || true
    wait "$MEMORY_TEST_PID" 2>/dev/null || true
    
    # 清理临时文件
    rm -f /tmp/cpu_test_$$.sh /tmp/memory_test_$$.sh
    
    # 验证结果
    verify_results "$max_cpu" "$memory_usage" "$oom_count"
}

# 运行主函数
main "$@" 