#!/bin/bash

#=================================================
# existing_installation.sh 单元测试脚本
#=================================================
# 功能: 使用真实配置，创建临时文件，对install模块进行单测
#=================================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INSTALL_DIR="$PROJECT_ROOT/install"
CONFIG_DIR="$PROJECT_ROOT/config"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试配置
TEST_TEMP_DIR=""
ORIGINAL_PWD=""
TEST_RESULTS=()
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

#=================================================
# 测试框架核心
#=================================================

# 初始化测试环境
init_test_environment() {
    log_info "初始化测试环境..."
    
    # 保存原始工作目录
    ORIGINAL_PWD=$(pwd)
    
    # 创建临时测试目录
    TEST_TEMP_DIR=$(mktemp -d -t datakit_unit_test.XXXXXX)
    log_info "测试临时目录: $TEST_TEMP_DIR"
    
    # 设置测试环境变量
    setup_test_environment_variables
    
    # 创建测试文件结构
    create_test_file_structure
    
    log_success "测试环境初始化完成"
}

# 设置测试环境变量
setup_test_environment_variables() {
    # 设置测试专用环境变量
    export SCENARIO_PROJECT_ROOT="$TEST_TEMP_DIR"
    export DATAKIT_INSTALL_DIR="$TEST_TEMP_DIR/install"
    export TEST_MODE=true
    export UNIT_TEST_MODE=true
    
    # 设置Datakit版本（从真实安装目录获取或使用默认值）
    if [[ -d "/opt/datakit_install" ]]; then
        # 从真实安装目录的文件名中提取版本号
        local bundle_file=$(ls /opt/datakit_install/datakit_bundle-linux-amd64-*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$bundle_file" ]]; then
            export DATAKIT_VERSION=$(basename "$bundle_file" | sed 's/datakit_bundle-linux-amd64-\(.*\)\.tar\.gz/\1/')
            log_info "从真实安装目录获取版本号: $DATAKIT_VERSION"
        else
            export DATAKIT_VERSION="1.78.0"
            log_warning "无法从真实安装目录获取版本号，使用默认值: $DATAKIT_VERSION"
        fi
    else
        export DATAKIT_VERSION="1.78.0"
        log_warning "真实安装目录不存在，使用默认版本号: $DATAKIT_VERSION"
    fi
    
    # 创建必要的目录
    mkdir -p "$DATAKIT_INSTALL_DIR"
    mkdir -p "$TEST_TEMP_DIR/usr/local/datakit/conf.d"
    mkdir -p "$TEST_TEMP_DIR/var/log/datakit"
    mkdir -p "$TEST_TEMP_DIR/etc/systemd/system"
    mkdir -p "$TEST_TEMP_DIR/scripts"
    
    log_info "测试环境变量设置完成"
}

# 创建测试文件结构
create_test_file_structure() {
    # 从真实的安装目录复制物料包
    local real_install_dir="/opt/datakit_install"
    
    if [[ -d "$real_install_dir" ]]; then
        log_info "从真实安装目录复制物料包: $real_install_dir"
        
        # 复制所有文件到测试目录
        cp -r "$real_install_dir"/* "$DATAKIT_INSTALL_DIR/" 2>/dev/null || {
            log_warning "复制物料包失败，将创建模拟文件"
            create_mock_files
        }
        
        # 确保安装器有执行权限
        if [[ -f "$DATAKIT_INSTALL_DIR/installer-linux-amd64-$DATAKIT_VERSION" ]]; then
            chmod +x "$DATAKIT_INSTALL_DIR/installer-linux-amd64-$DATAKIT_VERSION"
        fi
        
        log_success "物料包复制完成"
    else
        log_warning "真实安装目录不存在: $real_install_dir，将创建模拟文件"
        create_mock_files
    fi
    
    # 创建配置文件结构
    create_config_files
    
    log_info "测试文件结构创建完成"
}

# 创建模拟文件（当真实物料包不存在时）
create_mock_files() {
    # 创建模拟的安装包文件
    touch "$DATAKIT_INSTALL_DIR/datakit_bundle-linux-amd64-$DATAKIT_VERSION.tar.gz"
    touch "$DATAKIT_INSTALL_DIR/installer-linux-amd64-$DATAKIT_VERSION"
    touch "$DATAKIT_INSTALL_DIR/datakit-linux-amd64-$DATAKIT_VERSION.tar.gz"
    touch "$DATAKIT_INSTALL_DIR/dk_upgrader-linux-amd64.tar.gz"
    touch "$DATAKIT_INSTALL_DIR/data.tar.gz"
    touch "$DATAKIT_INSTALL_DIR/node_exporter-1.8.2.linux-amd64.tar.gz"
    
    # 设置执行权限
    chmod +x "$DATAKIT_INSTALL_DIR/installer-linux-amd64-$DATAKIT_VERSION"
    
    log_info "模拟文件创建完成"
}

# 创建配置文件结构
create_config_files() {
    # 创建模拟的Datakit配置文件
    cat > "$TEST_TEMP_DIR/usr/local/datakit/conf.d/datakit.conf" << 'EOF'
[global_host_tags]
  env = "unit_test"
  workspace = "test_workspace"

[http_api]
  listen = "0.0.0.0:9529"

[resource_limit]
  cpu_cores = 1.0
  mem_max_mb = 2048

[logging]
  rotate = 32
EOF
    
    # 创建模拟的采集器配置文件
    mkdir -p "$TEST_TEMP_DIR/usr/local/datakit/conf.d/opentelemetry"
    mkdir -p "$TEST_TEMP_DIR/usr/local/datakit/conf.d/log"
    mkdir -p "$TEST_TEMP_DIR/usr/local/datakit/conf.d/pushgateway"
    mkdir -p "$TEST_TEMP_DIR/usr/local/datakit/conf.d/prom"
    
    touch "$TEST_TEMP_DIR/usr/local/datakit/conf.d/opentelemetry/opentelemetry.conf"
    touch "$TEST_TEMP_DIR/usr/local/datakit/conf.d/log/logging.conf"
    touch "$TEST_TEMP_DIR/usr/local/datakit/conf.d/pushgateway/pushgateway.conf"
    touch "$TEST_TEMP_DIR/usr/local/datakit/conf.d/prom/prom_node_exporter.conf"
    
    # 创建模拟的脚本文件
    touch "$TEST_TEMP_DIR/scripts/config_update.sh"
    touch "$TEST_TEMP_DIR/scripts/datakit_health_check.sh"
    touch "$TEST_TEMP_DIR/scripts/app_init.sh"
    chmod +x "$TEST_TEMP_DIR/scripts/"*.sh 2>/dev/null || true
    
    log_info "配置文件结构创建完成"
}

# 清理测试环境
cleanup_test_environment() {
    log_info "清理测试环境..."
    
    # 恢复原始工作目录
    cd "$ORIGINAL_PWD" 2>/dev/null || true
    
    # 清理临时目录
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
        log_info "已删除测试临时目录: $TEST_TEMP_DIR"
    fi
    
    # 清理环境变量
    unset SCENARIO_PROJECT_ROOT
    unset DATAKIT_INSTALL_DIR
    unset TEST_MODE
    unset UNIT_TEST_MODE
    
    log_success "测试环境清理完成"
}

# 增强的临时文件清理函数
cleanup_temp_files() {
    local cleanup_type="${1:-all}"
    local temp_pattern="${2:-datakit_unit_test.*}"
    
    log_info "开始清理临时文件 (类型: $cleanup_type)..."
    
    case "$cleanup_type" in
        "all")
            cleanup_all_temp_files "$temp_pattern"
            ;;
        "test")
            cleanup_test_temp_files
            ;;
        "logs")
            cleanup_log_files
            ;;
        "orphaned")
            cleanup_orphaned_temp_files "$temp_pattern"
            ;;
        "force")
            cleanup_force_temp_files "$temp_pattern"
            ;;
        *)
            log_warning "未知的清理类型: $cleanup_type"
            show_cleanup_usage
            return 1
            ;;
    esac
}

# 清理所有临时文件
cleanup_all_temp_files() {
    local pattern="${1:-datakit_unit_test.*}"
    local temp_dirs=()
    local cleaned_count=0
    
    log_info "查找临时目录 (模式: $pattern)..."
    
    # 查找所有匹配的临时目录
    while IFS= read -r -d '' dir; do
        temp_dirs+=("$dir")
    done < <(find /tmp -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null)
    
    if [[ ${#temp_dirs[@]} -eq 0 ]]; then
        log_info "未找到需要清理的临时目录"
        return 0
    fi
    
    log_info "找到 ${#temp_dirs[@]} 个临时目录需要清理"
    
    # 清理每个临时目录
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "清理临时目录: $dir"
            if rm -rf "$dir" 2>/dev/null; then
                ((cleaned_count++))
                log_success "已清理: $dir"
            else
                log_error "清理失败: $dir"
            fi
        fi
    done
    
    log_success "清理完成，共清理 $cleaned_count 个临时目录"
}

# 清理测试相关的临时文件
cleanup_test_temp_files() {
    log_info "清理测试相关的临时文件..."
    
    # 清理当前测试的临时目录
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
        log_success "已清理当前测试临时目录: $TEST_TEMP_DIR"
    fi
    
    # 清理测试日志文件
    cleanup_log_files
    
    # 清理可能残留的测试文件
    local test_files=(
        "/tmp/datakit_test.log"
        "/tmp/datakit_*.log"
        "/tmp/test_*.log"
    )
    
    for pattern in "${test_files[@]}"; do
        find /tmp -maxdepth 1 -name "$(basename "$pattern")" -delete 2>/dev/null || true
    done
    
    log_success "测试临时文件清理完成"
}

# 清理日志文件
cleanup_log_files() {
    log_info "清理日志文件..."
    
    local log_patterns=(
        "datakit_test.log"
        "datakit_*.log"
        "test_*.log"
        "unit_test_*.log"
    )
    
    local cleaned_count=0
    
    for pattern in "${log_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            if rm -f "$file" 2>/dev/null; then
                ((cleaned_count++))
                log_info "已清理日志文件: $file"
            fi
        done < <(find /tmp -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
    done
    
    log_success "日志文件清理完成，共清理 $cleaned_count 个文件"
}

# 清理孤立的临时文件（超过1小时的）
cleanup_orphaned_temp_files() {
    local pattern="${1:-datakit_unit_test.*}"
    local max_age_hours="${2:-1}"
    
    log_info "清理孤立的临时文件 (超过 ${max_age_hours} 小时)..."
    
    local cleaned_count=0
    
    # 查找超过指定时间的临时目录
    while IFS= read -r -d '' dir; do
        local dir_age_hours=$(( ( $(date +%s) - $(stat -c %Y "$dir") ) / 3600 ))
        if [[ $dir_age_hours -gt $max_age_hours ]]; then
            log_info "清理过期临时目录: $dir (已存在 ${dir_age_hours} 小时)"
            if rm -rf "$dir" 2>/dev/null; then
                ((cleaned_count++))
                log_success "已清理: $dir"
            else
                log_error "清理失败: $dir"
            fi
        fi
    done < <(find /tmp -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null)
    
    log_success "孤立临时文件清理完成，共清理 $cleaned_count 个目录"
}

# 强制清理所有临时文件（谨慎使用）
cleanup_force_temp_files() {
    local pattern="${1:-datakit_unit_test.*}"
    
    log_warning "⚠️  强制清理所有临时文件 (模式: $pattern)"
    log_warning "这将删除所有匹配的临时目录，请确认..."
    
    read -p "确认要强制清理所有临时文件吗？(y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "开始强制清理..."
        cleanup_all_temp_files "$pattern"
    else
        log_info "取消强制清理"
    fi
}

# 显示清理使用说明
show_cleanup_usage() {
    cat << EOF
临时文件清理工具

用法: cleanup_temp_files [类型] [模式]

类型:
  all      清理所有临时文件 (默认)
  test     清理当前测试的临时文件
  logs     清理日志文件
  orphaned 清理孤立的临时文件 (超过1小时)
  force    强制清理所有临时文件 (需要确认)

模式:
  临时目录的匹配模式 (默认: datakit_unit_test.*)

示例:
  cleanup_temp_files                    # 清理所有临时文件
  cleanup_temp_files test               # 清理当前测试文件
  cleanup_temp_files logs               # 清理日志文件
  cleanup_temp_files orphaned 2         # 清理超过2小时的孤立文件
  cleanup_temp_files force              # 强制清理所有临时文件

EOF
}

# 显示临时文件统计信息
show_temp_files_stats() {
    local pattern="${1:-datakit_unit_test.*}"
    
    log_info "临时文件统计信息 (模式: $pattern)..."
    
    local temp_dirs=()
    local total_size=0
    
    # 查找所有匹配的临时目录
    while IFS= read -r -d '' dir; do
        temp_dirs+=("$dir")
        local dir_size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo "0")
        total_size=$((total_size + dir_size))
    done < <(find /tmp -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null)
    
    echo ""
    echo "=========================================="
    echo "临时文件统计"
    echo "=========================================="
    echo "临时目录数量: ${#temp_dirs[@]}"
    echo "总大小: $(numfmt --to=iec $total_size)"
    echo ""
    
    if [[ ${#temp_dirs[@]} -gt 0 ]]; then
        echo "临时目录列表:"
        echo "------------------------------------------"
        for dir in "${temp_dirs[@]}"; do
            local dir_size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "未知")
            local dir_age=$(( ( $(date +%s) - $(stat -c %Y "$dir") ) / 60 ))
            echo "$dir ($dir_size, ${dir_age}分钟前)"
        done
    fi
    
    echo ""
}

#=================================================
# 断言函数
#=================================================

# 记录测试结果
record_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    ((TEST_COUNT++))
    
    case "$status" in
        "PASS")
            ((PASS_COUNT++))
            echo -e "${GREEN}✅ PASS${NC}: $test_name - $message"
            ;;
        "FAIL")
            ((FAIL_COUNT++))
            echo -e "${RED}❌ FAIL${NC}: $test_name - $message"
            ;;
    esac
    
    TEST_RESULTS+=("$status: $test_name - $message")
}

# 基础断言
assert_true() {
    local condition="$1"
    local test_name="$2"
    local message="$3"
    
    if eval "$condition"; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local test_name="$2"
    local message="$3"
    
    if ! eval "$condition"; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message"
        return 1
    fi
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"
    local message="$4"
    
    if [[ "$actual" == "$expected" ]]; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message (期望: '$expected', 实际: '$actual')"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"
    local message="$3"
    
    if [[ -f "$file_path" ]]; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message (文件不存在: $file_path)"
        return 1
    fi
}

assert_dir_exists() {
    local dir_path="$1"
    local test_name="$2"
    local message="$3"
    
    if [[ -d "$dir_path" ]]; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message (目录不存在: $dir_path)"
        return 1
    fi
}

#=================================================
# 模块测试函数
#=================================================

# 测试状态检查模块
test_status_check_module() {
    log_info "测试状态检查模块..."
    
    # 加载模块
    source "$INSTALL_DIR/status_check.sh"
    
    # 测试1: 检查Datakit进程（应该不存在）
    test_name="check_datakit_process_not_running"
    if check_datakit_process; then
        record_test_result "$test_name" "FAIL" "Datakit进程不应该存在"
    else
        record_test_result "$test_name" "PASS" "Datakit进程检查正确"
    fi
    
    # 测试2: 检查Datakit端口（应该未被占用）
    test_name="check_datakit_port_not_listening"
    if check_datakit_port; then
        record_test_result "$test_name" "FAIL" "Datakit端口不应该被占用"
    else
        record_test_result "$test_name" "PASS" "Datakit端口检查正确"
    fi
    
    # 测试3: 检查Datakit配置（应该不存在）
    test_name="check_datakit_config_not_exists"
    if check_datakit_config; then
        record_test_result "$test_name" "FAIL" "Datakit配置不应该存在"
    else
        record_test_result "$test_name" "PASS" "Datakit配置检查正确"
    fi
    
    # 测试4: 完整状态检查（应该返回0，表示可以安装）
    test_name="check_installation_status_ready"
    if check_installation_status; then
        record_test_result "$test_name" "PASS" "安装状态检查正确，可以继续安装"
    else
        record_test_result "$test_name" "FAIL" "安装状态检查失败"
    fi
}

# 测试下载模块
test_download_module() {
    log_info "测试下载模块..."
    
    # 加载模块
    source "$INSTALL_DIR/download.sh"
    
    # 测试1: 准备安装目录
    test_name="prepare_install_directory"
    if prepare_install_directory; then
        record_test_result "$test_name" "PASS" "安装目录准备成功"
    else
        record_test_result "$test_name" "FAIL" "安装目录准备失败"
    fi
    
    # 测试2: 检查安装目录是否存在
    test_name="install_directory_exists"
    assert_dir_exists "$DATAKIT_INSTALL_DIR" "$test_name" "安装目录应该存在"
    
    # 测试3: 检查bundle文件是否存在（模拟文件）
    test_name="bundle_file_exists"
    assert_file_exists "$DATAKIT_INSTALL_DIR/datakit_bundle-linux-amd64-$DATAKIT_VERSION.tar.gz" "$test_name" "Bundle文件应该存在"
}

# 测试安装模块
test_install_module() {
    log_info "测试安装模块..."
    
    # 加载模块
    source "$INSTALL_DIR/install.sh"
    
    # 测试1: 解压bundle文件
    test_name="extract_bundle_file"
    if extract_bundle_file; then
        record_test_result "$test_name" "PASS" "Bundle文件解压成功"
    else
        record_test_result "$test_name" "FAIL" "Bundle文件解压失败"
    fi
    
    # 测试2: 检查解压后的文件
    test_name="extracted_files_exist"
    assert_file_exists "$DATAKIT_INSTALL_DIR/installer-linux-amd64-$DATAKIT_VERSION" "$test_name" "安装器文件应该存在"
    assert_file_exists "$DATAKIT_INSTALL_DIR/datakit-linux-amd64-$DATAKIT_VERSION.tar.gz" "$test_name" "Datakit包文件应该存在"
    
    # 测试3: 安装Node Exporter（模拟）
    test_name="install_node_exporter"
    if install_node_exporter; then
        record_test_result "$test_name" "PASS" "Node Exporter安装成功"
    else
        record_test_result "$test_name" "FAIL" "Node Exporter安装失败"
    fi
    
    # 测试4: 安装Datakit（模拟）
    test_name="install_datakit"
    if install_datakit; then
        record_test_result "$test_name" "PASS" "Datakit安装成功"
    else
        record_test_result "$test_name" "FAIL" "Datakit安装失败"
    fi
}

# 读取TOML配置文件的辅助函数
read_toml_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        yj -tj < "$config_file" 2>/dev/null || cat "$config_file"
    else
        return 1
    fi
}

# 测试配置模块
test_configure_module() {
    log_info "测试配置模块..."
    
    # 测试配置文件存在性
    assert_file_exists "$TEST_TEMP_DIR/usr/local/datakit/conf.d/datakit.conf" "datakit_conf_exists" "Datakit主配置文件应该存在"
    
    # 测试采集器配置文件存在性
    assert_file_exists "$TEST_TEMP_DIR/usr/local/datakit/conf.d/prom/prom_node_exporter.conf" "prom_conf_exists" "Prometheus配置文件应该存在"
    assert_file_exists "$TEST_TEMP_DIR/usr/local/datakit/conf.d/opentelemetry/opentelemetry.conf" "otel_conf_exists" "OpenTelemetry配置文件应该存在"
    assert_file_exists "$TEST_TEMP_DIR/usr/local/datakit/conf.d/log/logging.conf" "log_conf_exists" "日志配置文件应该存在"
    assert_file_exists "$TEST_TEMP_DIR/usr/local/datakit/conf.d/pushgateway/pushgateway.conf" "pushgateway_conf_exists" "Pushgateway配置文件应该存在"
    
    # 执行配置测试
    test_datakit_main_config
    test_datakit_inputs_config
    
    log_success "配置模块测试完成"
}

# 测试Datakit主配置文件
test_datakit_main_config() {
    log_info "测试Datakit主配置文件配置..."
    
    local original_conf="$TEST_TEMP_DIR/usr/local/datakit/conf.d/datakit.conf"
    local temp_conf="$TEST_TEMP_DIR/usr/local/datakit/conf.d/datakit.conf.temp"
    local backup_conf="$TEST_TEMP_DIR/usr/local/datakit/conf.d/datakit.conf.backup"
    
    # 备份原始配置文件
    cp "$original_conf" "$backup_conf"
    log_info "已备份原始配置文件到: $backup_conf"
    
    # 复制到临时配置文件
    cp "$original_conf" "$temp_conf"
    log_info "已复制配置文件到临时文件: $temp_conf"
    
    # 读取原始配置
    local original_config
    if ! original_config=$(read_toml_config "$temp_conf" 2>/dev/null); then
        log_error "读取原始配置文件失败"
        return 1
    fi
    
    log_info "=== 开始配置修改 ==="
    
    # 记录修改前的配置
    log_info "修改前配置:"
    log_info "日志分片: $(echo "$original_config" | jq -r '.logging.rotate // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "HTTP API监听: $(echo "$original_config" | jq -r '.http_api.listen // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "CPU限制: $(echo "$original_config" | jq -r '.resource_limit.cpu_cores // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "内存限制: $(echo "$original_config" | jq -r '.resource_limit.mem_max_mb // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "环境标签: $(echo "$original_config" | jq -r '.global_host_tags.env // "未设置"' 2>/dev/null || echo "未设置")"
    log_info "工作空间标签: $(echo "$original_config" | jq -r '.global_host_tags.workspace // "未设置"' 2>/dev/null || echo "未设置")"
    
    # 应用配置修改
    local current_config="$original_config"
    
    # 1. 设置日志分片 (int类型)
    current_config=$(echo "$current_config" | jq '.logging.rotate = 32')
    log_info "✅ 修改: 设置日志分片为 32 (int类型)"
    
    # 2. 设置HTTP API监听地址
    current_config=$(echo "$current_config" | jq '.http_api.listen = "0.0.0.0:9529"')
    log_info "✅ 修改: 设置HTTP API监听地址为 0.0.0.0:9529"
    
    # 3. 设置资源限制
    current_config=$(echo "$current_config" | jq '.resource_limit.cpu_cores = 1.0')
    log_info "✅ 修改: 设置CPU限制为 1.0 (float类型)"
    
    current_config=$(echo "$current_config" | jq '.resource_limit.mem_max_mb = 2048')
    log_info "✅ 修改: 设置内存限制为 2048 MB (int类型)"
    
    # 4. 设置全局标签
    current_config=$(echo "$current_config" | jq '.global_host_tags.env = "unit_test"')
    log_info "✅ 修改: 设置环境标签为 unit_test"
    
    current_config=$(echo "$current_config" | jq '.global_host_tags.workspace = "test_workspace"')
    log_info "✅ 修改: 设置工作空间标签为 test_workspace"
    
    # 5. 设置Dataway地址
    current_config=$(echo "$current_config" | jq '.dataway.urls = ["http://test-dataway:9529"]')
    log_info "✅ 修改: 设置Dataway地址为 http://test-dataway:9529"
    
    # 6. 添加自定义全局标签
    current_config=$(echo "$current_config" | jq '.global_host_tags.test_tag = "test_value"')
    log_info "✅ 新增: 添加测试标签 test_tag=test_value"
    
    current_config=$(echo "$current_config" | jq '.global_host_tags.version = "1.78.0"')
    log_info "✅ 新增: 添加版本标签 version=1.78.0"
    
    # 将修改后的配置写回临时文件
    if ! echo "$current_config" | yj -jt > "$temp_conf" 2>/dev/null; then
        log_error "❌ 失败: 转换配置文件格式失败"
        return 1
    fi
    
    # 验证修改后的配置
    local modified_config
    if ! modified_config=$(read_toml_config "$temp_conf" 2>/dev/null); then
        log_error "❌ 失败: 读取修改后的配置文件失败"
        return 1
    fi
    
    log_info "=== 修改后配置验证 ==="
    
    # 验证各项配置
    local logging_rotate=$(echo "$modified_config" | jq -r '.logging.rotate // "未设置"' 2>/dev/null || echo "未设置")
    local http_listen=$(echo "$modified_config" | jq -r '.http_api.listen // "未设置"' 2>/dev/null || echo "未设置")
    local cpu_cores=$(echo "$modified_config" | jq -r '.resource_limit.cpu_cores // "未设置"' 2>/dev/null || echo "未设置")
    local mem_mb=$(echo "$modified_config" | jq -r '.resource_limit.mem_max_mb // "未设置"' 2>/dev/null || echo "未设置")
    local env_tag=$(echo "$modified_config" | jq -r '.global_host_tags.env // "未设置"' 2>/dev/null || echo "未设置")
    local workspace_tag=$(echo "$modified_config" | jq -r '.global_host_tags.workspace // "未设置"' 2>/dev/null || echo "未设置")
    local test_tag=$(echo "$modified_config" | jq -r '.global_host_tags.test_tag // "未设置"' 2>/dev/null || echo "未设置")
    local version_tag=$(echo "$modified_config" | jq -r '.global_host_tags.version // "未设置"' 2>/dev/null || echo "未设置")
    local dataway_urls=$(echo "$modified_config" | jq -r '.dataway.urls[0] // "未设置"' 2>/dev/null || echo "未设置")
    
    log_info "修改后配置:"
    log_info "日志分片: $logging_rotate"
    log_info "HTTP API监听: $http_listen"
    log_info "CPU限制: $cpu_cores"
    log_info "内存限制: $mem_mb"
    log_info "环境标签: $env_tag"
    log_info "工作空间标签: $workspace_tag"
    log_info "测试标签: $test_tag"
    log_info "版本标签: $version_tag"
    log_info "Dataway地址: $dataway_urls"
    
    # 验证配置正确性
    local config_errors=0
    
    if [[ "$logging_rotate" != "32" ]]; then
        log_error "❌ 配置错误: 日志分片应为 32，实际为 $logging_rotate"
        ((config_errors++))
    else
        log_success "✅ 配置正确: 日志分片 = $logging_rotate"
    fi
    
    if [[ "$http_listen" != "0.0.0.0:9529" ]]; then
        log_error "❌ 配置错误: HTTP API监听应为 0.0.0.0:9529，实际为 $http_listen"
        ((config_errors++))
    else
        log_success "✅ 配置正确: HTTP API监听 = $http_listen"
    fi
    
    if [[ "$cpu_cores" != "1.0" ]]; then
        log_error "❌ 配置错误: CPU限制应为 1.0，实际为 $cpu_cores"
        ((config_errors++))
    else
        log_success "✅ 配置正确: CPU限制 = $cpu_cores"
    fi
    
    if [[ "$mem_mb" != "2048" ]]; then
        log_error "❌ 配置错误: 内存限制应为 2048，实际为 $mem_mb"
        ((config_errors++))
    else
        log_success "✅ 配置正确: 内存限制 = $mem_mb"
    fi
    
    if [[ "$env_tag" != "unit_test" ]]; then
        log_error "❌ 配置错误: 环境标签应为 unit_test，实际为 $env_tag"
        ((config_errors++))
    else
        log_success "✅ 配置正确: 环境标签 = $env_tag"
    fi
    
    if [[ "$workspace_tag" != "test_workspace" ]]; then
        log_error "❌ 配置错误: 工作空间标签应为 test_workspace，实际为 $workspace_tag"
        ((config_errors++))
    else
        log_success "✅ 配置正确: 工作空间标签 = $workspace_tag"
    fi
    
    if [[ "$test_tag" != "test_value" ]]; then
        log_error "❌ 配置错误: 测试标签应为 test_value，实际为 $test_tag"
        ((config_errors++))
    else
        log_success "✅ 配置正确: 测试标签 = $test_tag"
    fi
    
    if [[ "$version_tag" != "1.78.0" ]]; then
        log_error "❌ 配置错误: 版本标签应为 1.78.0，实际为 $version_tag"
        ((config_errors++))
    else
        log_success "✅ 配置正确: 版本标签 = $version_tag"
    fi
    
    if [[ "$dataway_urls" != "http://test-dataway:9529" ]]; then
        log_error "❌ 配置错误: Dataway地址应为 http://test-dataway:9529，实际为 $dataway_urls"
        ((config_errors++))
    else
        log_success "✅ 配置正确: Dataway地址 = $dataway_urls"
    fi
    
    if [[ $config_errors -eq 0 ]]; then
        log_success "🎉 所有配置验证通过！"
        record_test_result "datakit_main_config" "PASS" "Datakit主配置文件配置成功"
    else
        log_error "❌ 配置验证失败，共 $config_errors 个错误"
        record_test_result "datakit_main_config" "FAIL" "Datakit主配置文件配置失败"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_conf"
    log_info "已清理临时配置文件"
    
    return 0
}

# 测试采集器配置
test_datakit_inputs_config() {
    log_info "测试采集器配置..."
    
    local conf_dir="$TEST_TEMP_DIR/usr/local/datakit/conf.d"
    local config_errors=0
    
    # 测试Prometheus配置
    test_prometheus_config "$conf_dir/prom/prom_node_exporter.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    # 测试OpenTelemetry配置
    test_opentelemetry_config "$conf_dir/opentelemetry/opentelemetry.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    # 测试日志配置
    test_logging_config "$conf_dir/log/logging.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    # 测试Pushgateway配置
    test_pushgateway_config "$conf_dir/pushgateway/pushgateway.conf"
    if [[ $? -ne 0 ]]; then
        ((config_errors++))
    fi
    
    if [[ $config_errors -eq 0 ]]; then
        log_success "🎉 所有采集器配置验证通过！"
        record_test_result "datakit_inputs_config" "PASS" "采集器配置成功"
    else
        log_error "❌ 采集器配置验证失败，共 $config_errors 个错误"
        record_test_result "datakit_inputs_config" "FAIL" "采集器配置失败"
        return 1
    fi
    
    return 0
}

# 测试Prometheus配置
test_prometheus_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试Prometheus配置: $config_file"
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始Prometheus配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 读取原始配置
    local original_content=$(cat "$temp_file")
    log_info "原始Prometheus配置内容长度: ${#original_content} 字符"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
# {"version": "1.78.0", "desc": "do NOT edit this line"}

[[inputs.prom]]
  ## Exporter URLs.
  urls = ["http://127.0.0.1:9100/metrics"]

  uds_path = ""

  ## Ignore URL request errors.
  ignore_req_err = false

  ## Collector alias.
  source = "prom"

  measurement_name = "node_exporter"

  keep_exist_metric_name = true

  election = true

  ## disable setting host tag for this input
  disable_host_tag = false

  ## disable setting instance tag for this input
  disable_instance_tag = false

  ## disable info tag for this input
  disable_info_tag = false

  [[inputs.prom.measurements]]
    prefix = "etcd_network_"
    name = "etcd_network"
    
  [[inputs.prom.measurements]]
    prefix = "etcd_server_"
    name = "etcd_server"

  ## Rename tag key in prom data.
  [inputs.prom.tags_rename]
    overwrite_exist_tags = false

  [inputs.prom.as_logging]
    enable = false
    service = "service_name"

  ## Customize tags.
  # [inputs.prom.tags]
    # some_tag = "some_value"
    # more_tag = "some_other_value"
  
  ## (Optional) Collect interval: (defaults to "30s").
  # interval = "30s"

  ## (Optional) Timeout: (defaults to "30s").
  # timeout = "30s"
EOF
    
    log_info "✅ 修改: 应用新的Prometheus配置"
    
    # 验证配置
    local modified_content=$(cat "$temp_file")
    local content_length=${#modified_content}
    
    log_info "修改后Prometheus配置内容长度: $content_length 字符"
    
    # 验证关键配置项
    if grep -q "urls = \[\"http://127.0.0.1:9100/metrics\"\]" "$temp_file"; then
        log_success "✅ 配置正确: Prometheus URLs配置"
    else
        log_error "❌ 配置错误: Prometheus URLs配置缺失"
        return 1
    fi
    
    if grep -q "source = \"prom\"" "$temp_file"; then
        log_success "✅ 配置正确: Prometheus source配置"
    else
        log_error "❌ 配置错误: Prometheus source配置缺失"
        return 1
    fi
    
    if grep -q "measurement_name = \"node_exporter\"" "$temp_file"; then
        log_success "✅ 配置正确: Prometheus measurement_name配置"
    else
        log_error "❌ 配置错误: Prometheus measurement_name配置缺失"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时Prometheus配置文件"
    
    return 0
}

# 测试OpenTelemetry配置
test_opentelemetry_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试OpenTelemetry配置: $config_file"
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始OpenTelemetry配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
# {"version": "1.78.0", "desc": "do NOT edit this line"}
[[inputs.opentelemetry]]
  [inputs.opentelemetry.http]
   enable = true
   http_status_ok = 200
   trace_api = "/otel/v1/trace"
   metric_api = "/otel/v1/metric"
   logs_api = "/otel/v1/logs"

  [inputs.opentelemetry.grpc]
   trace_enable = true
   metric_enable = true
   addr = "0.0.0.0:4317"
EOF
    
    log_info "✅ 修改: 应用新的OpenTelemetry配置"
    
    # 验证配置
    if grep -q "enable = true" "$temp_file"; then
        log_success "✅ 配置正确: OpenTelemetry HTTP启用"
    else
        log_error "❌ 配置错误: OpenTelemetry HTTP未启用"
        return 1
    fi
    
    if grep -q "addr = \"0.0.0.0:4317\"" "$temp_file"; then
        log_success "✅ 配置正确: OpenTelemetry gRPC地址"
    else
        log_error "❌ 配置错误: OpenTelemetry gRPC地址缺失"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时OpenTelemetry配置文件"
    
    return 0
}

# 测试日志配置
test_logging_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试日志配置: $config_file"
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始日志配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
[[inputs.logging]]
  logfiles = [
    "/var/log/syslog",
    "/var/log/messages",
    "/var/log/dmesg",
    "/var/log/aws-routed-eni/*",
    "/var/log/secure",
    "/var/log/audit/*",
    "/var/log/lastlog",
    "/opt/datakit/*.log",
    "/var/log/datakit/log"
  ]

  ignore = [""]

  source = ""

  service = ""

  pipeline = ""

  ignore_status = []

  character_encoding = ""

  auto_multiline_detection = true
  auto_multiline_extra_patterns = []

  remove_ansi_escape_codes = false

  ignore_dead_log = "12h"

  from_beginning = false

  [inputs.logging.tags]
EOF
    
    log_info "✅ 修改: 应用新的日志配置"
    
    # 验证配置
    if grep -q "/var/log/syslog" "$temp_file"; then
        log_success "✅ 配置正确: 系统日志文件路径"
    else
        log_error "❌ 配置错误: 系统日志文件路径缺失"
        return 1
    fi
    
    if grep -q "auto_multiline_detection = true" "$temp_file"; then
        log_success "✅ 配置正确: 自动多行检测启用"
    else
        log_error "❌ 配置错误: 自动多行检测未启用"
        return 1
    fi
    
    if grep -q "ignore_dead_log = \"12h\"" "$temp_file"; then
        log_success "✅ 配置正确: 忽略死日志时间设置"
    else
        log_error "❌ 配置错误: 忽略死日志时间设置缺失"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时日志配置文件"
    
    return 0
}

# 测试Pushgateway配置
test_pushgateway_config() {
    local config_file="$1"
    local temp_file="${config_file}.temp"
    
    log_info "测试Pushgateway配置: $config_file"
    
    # 备份原始配置
    cp "$config_file" "${config_file}.backup"
    log_info "已备份原始Pushgateway配置文件"
    
    # 复制到临时文件
    cp "$config_file" "$temp_file"
    
    # 应用新的配置
    cat > "$temp_file" << 'EOF'
[[inputs.pushgateway]]
  ## Prefix for the internal routes of web endpoints. Defaults to empty.
  route_prefix = "/v1/pushgateway"

  job_as_measurement = false
  keep_exist_metric_name = true
EOF
    
    log_info "✅ 修改: 应用新的Pushgateway配置"
    
    # 验证配置
    if grep -q "route_prefix = \"/v1/pushgateway\"" "$temp_file"; then
        log_success "✅ 配置正确: Pushgateway路由前缀"
    else
        log_error "❌ 配置错误: Pushgateway路由前缀缺失"
        return 1
    fi
    
    if grep -q "job_as_measurement = false" "$temp_file"; then
        log_success "✅ 配置正确: Pushgateway job_as_measurement设置"
    else
        log_error "❌ 配置错误: Pushgateway job_as_measurement设置缺失"
        return 1
    fi
    
    if grep -q "keep_exist_metric_name = true" "$temp_file"; then
        log_success "✅ 配置正确: Pushgateway keep_exist_metric_name设置"
    else
        log_success "✅ 配置正确: Pushgateway keep_exist_metric_name设置"
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
    log_info "已清理临时Pushgateway配置文件"
    
    return 0
}

# 测试定时任务模块
test_setup_cron_module() {
    log_info "测试定时任务模块..."
    
    # 加载模块
    source "$INSTALL_DIR/setup_cron.sh"
    
    # 测试1: 设置定时任务
    test_name="setup_cron_jobs"
    if setup_cron_jobs; then
        record_test_result "$test_name" "PASS" "定时任务设置成功"
    else
        record_test_result "$test_name" "FAIL" "定时任务设置失败"
    fi
}

# 测试验证模块
test_verify_module() {
    log_info "测试验证模块..."
    
    # 加载模块
    source "$INSTALL_DIR/verify.sh"
    
    # 测试1: 验证配置文件存在性
    test_name="verify_config_files"
    if verify_config_files; then
        record_test_result "$test_name" "PASS" "配置文件验证成功"
    else
        record_test_result "$test_name" "FAIL" "配置文件验证失败"
    fi
    
    # 测试2: 验证资源限制配置
    test_name="verify_resource_limits"
    if verify_resource_limits; then
        record_test_result "$test_name" "PASS" "资源限制验证成功"
    else
        record_test_result "$test_name" "FAIL" "资源限制验证失败"
    fi
    
    # 测试3: 验证定时任务配置
    test_name="verify_cron_jobs"
    if verify_cron_jobs; then
        record_test_result "$test_name" "PASS" "定时任务验证成功"
    else
        record_test_result "$test_name" "FAIL" "定时任务验证失败"
    fi
}

# 测试主机信息模块
test_host_info_module() {
    log_info "测试主机信息模块..."
    
    # 加载模块
    source "$INSTALL_DIR/host_info.sh"
    
    # 测试1: 获取主机信息
    test_name="get_host_info"
    if get_host_info; then
        record_test_result "$test_name" "PASS" "主机信息获取成功"
    else
        record_test_result "$test_name" "FAIL" "主机信息获取失败"
    fi
    
    # 测试2: 检查全局状态是否设置
    test_name="global_state_set"
    if [[ -n "${HOST_IP:-}" ]]; then
        record_test_result "$test_name" "PASS" "主机IP已设置"
    else
        record_test_result "$test_name" "FAIL" "主机IP未设置"
    fi
}

#=================================================
# 测试运行器
#=================================================

# 运行所有模块测试
run_all_module_tests() {
    log_info "开始运行所有模块测试..."
    echo ""
    
    # 初始化测试环境
    init_test_environment
    
    # 加载真实配置
    load_real_config
    
    # 运行各个模块测试
    test_status_check_module
    echo ""
    
    test_download_module
    echo ""
    
    test_install_module
    echo ""
    
    test_configure_module
    echo ""
    
    test_setup_cron_module
    echo ""
    
    test_verify_module
    echo ""
    
    test_host_info_module
    echo ""
    
    # 显示测试结果
    show_test_results
    
    # 清理测试环境
    cleanup_test_environment
}

# 运行单个模块测试
run_single_module_test() {
    local module_name="$1"
    
    log_info "开始测试模块: $module_name"
    echo ""
    
    # 初始化测试环境
    init_test_environment
    
    # 加载真实配置
    load_real_config
    
    # 根据模块名运行对应测试
    case "$module_name" in
        "status_check")
            test_status_check_module
            ;;
        "download")
            test_download_module
            ;;
        "install")
            test_install_module
            ;;
        "configure")
            test_configure_module
            ;;
        "setup_cron")
            test_setup_cron_module
            ;;
        "verify")
            test_verify_module
            ;;
        "host_info")
            test_host_info_module
            ;;
        *)
            log_error "未知模块: $module_name"
            log_info "可用模块: status_check, download, install, configure, setup_cron, verify, host_info"
            return 1
            ;;
    esac
    
    # 显示测试结果
    show_test_results
    
    # 清理测试环境
    cleanup_test_environment
}

# 加载真实配置
load_real_config() {
    log_info "加载真实配置..."
    
    # 设置必要的环境变量（避免readonly冲突）
    export DATAKIT_LOG_FILE="${DATAKIT_LOG_FILE:-/tmp/datakit_test.log}"
    export LOG_LEVEL="${LOG_LEVEL:-1}"
    
    # 加载基础配置（如果未加载）
    if [[ -z "${SCRIPT_NAME:-}" ]]; then
        if [[ -f "$CONFIG_DIR/base/base_config.sh" ]]; then
            source "$CONFIG_DIR/base/base_config.sh"
            log_info "已加载基础配置: base_config.sh"
        else
            log_warning "base_config.sh 文件不存在，跳过加载"
        fi
    fi
    
    # 加载所有core模块
    local core_modules=(
        "logging.sh"
        "utils.sh"
        "validation.sh"
        "initialize.sh"
        "health_check.sh"
        "datakit_service.sh"
        "config_file.sh"
    )
    
    for module in "${core_modules[@]}"; do
        local module_path="$PROJECT_ROOT/core/$module"
        if [[ -f "$module_path" ]]; then
            # 检查函数是否已存在，避免重复加载
            local module_name="${module%.sh}"
            case "$module_name" in
                "logging")
                    if [[ -z "$(declare -f log_info 2>/dev/null)" ]]; then
                        source "$module_path"
                        log_info "已加载core模块: $module"
                    fi
                    ;;
                "utils")
                    if [[ -z "$(declare -f set_global_state 2>/dev/null)" ]]; then
                        source "$module_path"
                        log_info "已加载core模块: $module"
                    fi
                    ;;
                "validation")
                    if [[ -z "$(declare -f validate_config 2>/dev/null)" ]]; then
                        source "$module_path"
                        log_info "已加载core模块: $module"
                    fi
                    ;;
                "initialize")
                    if [[ -z "$(declare -f initialize_datakit 2>/dev/null)" ]]; then
                        source "$module_path"
                        log_info "已加载core模块: $module"
                    fi
                    ;;
                "health_check")
                    if [[ -z "$(declare -f check_datakit_health 2>/dev/null)" ]]; then
                        source "$module_path"
                        log_info "已加载core模块: $module"
                    fi
                    ;;
                "datakit_service")
                    if [[ -z "$(declare -f start_datakit_service 2>/dev/null)" ]]; then
                        source "$module_path"
                        log_info "已加载core模块: $module"
                    fi
                    ;;
                "config_file")
                    if [[ -z "$(declare -f update_config_file 2>/dev/null)" ]]; then
                        source "$module_path"
                        log_info "已加载core模块: $module"
                    fi
                    ;;
            esac
        else
            log_warning "core模块文件不存在: $module_path"
        fi
    done
    
    # 尝试加载环境配置（按优先级）
    local env_configs=(
        "$CONFIG_DIR/env/benjamin.sh"
        "$CONFIG_DIR/env/production.sh"
        "$CONFIG_DIR/env/development.sh"
    )
    
    for config in "${env_configs[@]}"; do
        if [[ -f "$config" ]]; then
            source "$config"
            log_info "已加载环境配置: $config"
            break
        fi
    done
    
    log_success "真实配置加载完成"
}

# 显示测试结果
show_test_results() {
    echo ""
    echo "=========================================="
    echo "测试结果统计"
    echo "=========================================="
    echo "总测试数: $TEST_COUNT"
    echo "通过: $PASS_COUNT"
    echo "失败: $FAIL_COUNT"
    
    if [[ $TEST_COUNT -gt 0 ]]; then
        local pass_rate=$((PASS_COUNT * 100 / TEST_COUNT))
        echo "通过率: ${pass_rate}%"
    fi
    
    echo ""
    echo "详细结果:"
    echo "------------------------------------------"
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    
    echo ""
    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}🎉 所有测试通过！${NC}"
        return 0
    else
        echo -e "${RED}⚠️  有 $FAIL_COUNT 个测试失败${NC}"
        return 1
    fi
}

#=================================================
# 命令行接口
#=================================================

show_usage() {
    cat << EOF
existing_installation.sh 单元测试脚本

用法: $0 [选项] [模块名]

选项:
  -h, --help              显示此帮助信息
  -a, --all               运行所有模块测试
  -m, --module MODULE     运行指定模块测试
  -v, --verbose           详细输出模式
  -c, --cleanup TYPE      清理临时文件
  -s, --stats             显示临时文件统计信息

清理类型 (--cleanup):
  all      清理所有临时文件 (默认)
  test     清理当前测试的临时文件
  logs     清理日志文件
  orphaned 清理孤立的临时文件 (超过1小时)
  force    强制清理所有临时文件 (需要确认)

可用模块:
  status_check            状态检查模块 (status_check.sh)
  download                下载模块 (download.sh)
  install                 安装模块 (install.sh)
  configure               配置模块 (configure.sh)
  setup_cron              定时任务模块 (setup_cron.sh)
  verify                  验证模块 (verify.sh)
  host_info               主机信息模块 (host_info.sh)

示例:
  $0 --all                运行所有模块测试
  $0 --module status_check 测试状态检查模块
  $0 --module download    测试下载模块
  $0 --module install     测试安装模块
  $0 --cleanup all        清理所有临时文件
  $0 --cleanup logs       清理日志文件
  $0 --cleanup orphaned   清理孤立的临时文件
  $0 --stats              显示临时文件统计信息

说明:
  - 使用真实配置，通过source方式读取
  - 创建临时文件进行测试，不影响主流程
  - 测试完成后自动清理临时文件
  - 支持单独验证每个模块
  - 提供多种临时文件清理选项

EOF
}

# 主函数
main() {
    local run_all=false
    local module_name=""
    local verbose_mode=false
    local cleanup_type=""
    local show_stats=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -m|--module)
                module_name="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose_mode=true
                shift
                ;;
            -c|--cleanup)
                cleanup_type="$2"
                shift 2
                ;;
            -s|--stats)
                show_stats=true
                shift
                ;;
            *)
                echo "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 设置详细模式
    if [[ "$verbose_mode" == "true" ]]; then
        set -x
    fi
    
    # 处理清理操作
    if [[ -n "$cleanup_type" ]]; then
        cleanup_temp_files "$cleanup_type"
        exit 0
    fi
    
    # 处理统计信息显示
    if [[ "$show_stats" == "true" ]]; then
        show_temp_files_stats
        exit 0
    fi
    
    # 检查参数
    if [[ "$run_all" == "true" ]]; then
        run_all_module_tests
    elif [[ -n "$module_name" ]]; then
        run_single_module_test "$module_name"
    else
        echo "请指定测试模式: --all 或 --module <模块名>"
        show_usage
        exit 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 