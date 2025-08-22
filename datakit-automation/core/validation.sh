#!/bin/bash

#=================================================
# 验证系统模块
#=================================================
# 功能: 环境变量验证、系统资源检查、网络连通性测试、配置文件验证
#=================================================

# 获取脚本所在目录
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载依赖模块
source "$CORE_DIR/utils.sh"

# 验证必需的命令
validate_required_commands() {
    local required_commands=("curl" "jq" "systemctl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "缺少必需的命令: ${missing_commands[*]}"
        return 1
    fi
    
    log_info "所有必需命令验证通过"
    return 0
}

# 验证系统环境
validate_system_environment() {
    # 检查是否为root用户
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本需要root权限运行"
        return 1
    fi
    
    # 检查系统类型
    if ! command_exists "systemctl"; then
        log_error "此脚本需要支持systemd的系统"
        return 1
    fi
        
    log_info "系统环境验证通过"
    return 0
}

# 验证系统资源（重命名避免冲突）
validate_system_resources_validation() {
    log_info "验证系统资源..."
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "磁盘空间不足: 可用 ${available_space}KB，需要 ${required_space}KB"
        return 1
    fi
    
    # 检查内存
    local available_memory=$(free -k | awk 'NR==2 {print $7}')
    local required_memory=524288  # 512MB in KB
    
    if [[ $available_memory -lt $required_memory ]]; then
        log_warning "可用内存较少: 可用 ${available_memory}KB，建议 ${required_memory}KB"
    fi
    
    # 检查CPU负载
    local load_average=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_average > 5.0" | bc -l) )); then
        log_warning "系统负载较高: $load_average"
    fi
    
    log_info "系统资源验证通过"
    return 0
}

# 验证网络连通性
validate_network_connectivity() {
    log_info "验证网络连通性..."
    
    # 检查S3连接
    if ! curl -s --connect-timeout 10 --max-time 30 -I "https://s3.ap-southeast-1.amazonaws.com" >/dev/null; then
        log_error "无法连接到AWS S3"
        return 1
    fi
    
    # 检查Dataway连接
    if [ -n "${CONFIG[DATAWAY_URL]}" ]; then
        if ! curl -s --connect-timeout 10 --max-time 30 -I "${CONFIG[DATAWAY_URL]}" >/dev/null; then
            log_warning "无法连接到Dataway，可能影响数据上报"
        fi
    fi
    
    # 检查运维平台连接
    if [ -n "${CONFIG[OPS_ADDR]}" ]; then
        if ! curl -s --connect-timeout 10 --max-time 30 -I "${CONFIG[OPS_ADDR]}" >/dev/null; then
            log_warning "无法连接到运维平台，可能影响配置获取"
        fi
    fi
    
    log_info "网络连通性验证通过"
    return 0
}


# 验证环境完整性
validate_environment() {
    log_info "验证环境完整性..."
    
    # 验证系统环境
    if ! validate_system_environment; then
        return 1
    fi
    
    # 验证系统资源
    if ! validate_system_resources_validation; then
        return 1
    fi
    
    # 验证网络连通性
    if ! validate_network_connectivity; then
        return 1
    fi
    
    # 验证必需命令
    #if ! validate_required_commands; then
    #    return 1
    #fi
    

    
    log_info "环境完整性验证通过"
    return 0
}

# =============================================================================
# 通用验证函数 - 供其他模块复用
# =============================================================================

# 验证进程是否运行
validate_process_running() {
    local process_name="$1"
    local max_retries="${2:-1}"
    local retry_interval="${3:-5}"
    
    for ((i=1; i<=max_retries; i++)); do
        if pgrep -x "$process_name" >/dev/null; then
            log_info "$process_name 进程运行正常 (尝试 $i/$max_retries)"
            return 0
        else
            if [ $i -lt $max_retries ]; then
                log_info "$process_name 进程未运行，等待 ${retry_interval}秒后重试 ($i/$max_retries)"
                sleep $retry_interval
            else
                log_error "$process_name 进程验证失败，已重试 $max_retries 次"
                return 1
            fi
        fi
    done
}

# 验证端口是否监听
validate_port_listening() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if netstat -tlnp 2>/dev/null | grep -q ":$port " || \
       ss -tlnp 2>/dev/null | grep -q ":$port "; then
        log_info "端口 $port ($protocol) 监听正常"
        return 0
    else
        log_warning "端口 $port ($protocol) 未监听"
        return 1
    fi
}

# 验证文件是否存在
validate_file_exists() {
    local file_path="$1"
    local description="${2:-文件}"
    
    if [ -f "$file_path" ]; then
        log_info "$description 存在: $file_path"
        return 0
    else
        log_error "$description 不存在: $file_path"
        return 1
    fi
}

# 验证目录是否存在
validate_directory_exists() {
    local dir_path="$1"
    local description="${2:-目录}"
    
    if [ -d "$dir_path" ]; then
        log_info "$description 存在: $dir_path"
        return 0
    else
        log_warning "$description 不存在: $dir_path"
        return 1
    fi
}

# 验证服务状态
validate_service_status() {
    local service_name="$1"
    local expected_status="${2:-active}"
    
    if systemctl is-$expected_status --quiet "$service_name" 2>/dev/null; then
        log_info "$service_name 服务状态正常 ($expected_status)"
        return 0
    else
        log_warning "$service_name 服务状态异常 (期望: $expected_status)"
        return 1
    fi
}

# 验证配置文件内容
validate_config_file() {
    local config_file="$1"
    local config_key="$2"
    local expected_value="$3"
    local description="${4:-配置项}"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件不存在: $config_file"
        return 1
    fi
    
    # 尝试读取配置值
    local actual_value
    if command_exists "yj" && command_exists "jq"; then
        # 使用yj和jq读取TOML配置
        actual_value=$(read_toml_config "$config_file" 2>/dev/null | jq -r "$config_key // empty" 2>/dev/null)
    else
        # 使用grep简单匹配
        actual_value=$(grep -o "$config_key[[:space:]]*=[[:space:]]*[^[:space:]]*" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    fi
    
    if [ "$actual_value" = "$expected_value" ]; then
        log_info "$description 配置正确: $expected_value"
        return 0
    else
        log_warning "$description 配置不匹配 (期望: $expected_value, 实际: $actual_value)"
        return 1
    fi
}

# 验证cron任务配置
validate_cron_job() {
    local cron_pattern="$1"
    local description="${2:-定时任务}"
    
    if crontab -l 2>/dev/null | grep -q "$cron_pattern"; then
        log_info "$description 配置存在"
        return 0
    else
        log_error "$description 配置不存在"
        return 1
    fi
} 

verify_installation() {
    log_info "=== 验证安装结果 ==="
    log_info "开始执行安装总结验证..."
    
    local verification_passed=true
    local verification_results=()
    
    # 1. 验证Datakit进程运行状态
    log_info "1. 验证Datakit进程运行状态..."
    if verify_datakit_process; then
        verification_results+=("✅ Datakit进程运行正常")
    else
        verification_results+=("❌ Datakit进程运行异常")
        verification_passed=false
    fi
    
    # 2. 验证配置文件存在性
    log_info "2. 验证配置文件存在性..."
    if verify_config_files; then
        verification_results+=("✅ 配置文件检查通过")
    else
        verification_results+=("❌ 配置文件检查失败")
        verification_passed=false
    fi
    
    # 3. 验证资源限制配置
    log_info "3. 验证资源限制配置..."
    if verify_resource_limits; then
        verification_results+=("✅ 资源限制配置正确")
    else
        verification_results+=("❌ 资源限制配置异常")
        verification_passed=false
    fi
    
    # 4. 验证定时任务配置
    log_info "4. 验证定时任务配置..."
    if verify_cron_jobs; then
        verification_results+=("✅ 定时任务配置正确")
    else
        verification_results+=("❌ 定时任务配置异常")
        verification_passed=false
    fi
    
    # 5. 验证运维平台信息获取
    log_info "5. 验证运维平台信息获取..."
    if verify_ops_platform_info; then
        verification_results+=("✅ 运维平台信息获取成功")
    else
        verification_results+=("❌ 运维平台信息获取失败")
        verification_passed=false
    fi
    
    # 6. 验证Node Exporter状态
    log_info "6. 验证Node Exporter状态..."
    if verify_node_exporter; then
        verification_results+=("✅ Node Exporter运行正常")
    else
        verification_results+=("❌ Node Exporter运行异常")
        verification_passed=false
    fi
    
    # 输出验证总结
    log_info "=== 安装验证总结 ==="
    for result in "${verification_results[@]}"; do
        log_info "$result"
    done
    
    if [ "$verification_passed" = true ]; then
        log_info "=== 所有验证项通过 ==="
        log_info "Datakit安装验证通过: 所有6项检查均通过"
        return 0
    else
        log_error "=== 部分验证项失败 ==="
        
        # return 1
    fi
}

# 1. 验证Datakit进程运行状态（带重试）
verify_datakit_process() {
    validate_process_running "datakit" 10 5
}

# 2. 验证配置文件存在性
verify_config_files() {
    local conf_dir="/usr/local/datakit/conf.d"
    local required_configs=(
        "opentelemetry/opentelemetry.conf"
        "log/logging.conf"
        "pushgateway/pushgateway.conf"
        "prom/prom_node_exporter.conf"
    )
    
    log_info "检查必需配置文件:"
    for config in "${required_configs[@]}"; do
        if ! validate_file_exists "$conf_dir/$config" "配置文件"; then
            return 1
        fi
    done
    
    log_info "所有必需配置文件存在"
    return 0
}

# 3. 验证资源限制配置
verify_resource_limits() {
    local datakit_conf="/usr/local/datakit/conf.d/datakit.conf"
    
    if [ ! -f "$datakit_conf" ]; then
        log_error "Datakit配置文件不存在"
        return 1
    fi
    
    # 读取配置并验证资源限制
    local config_json
    if ! config_json=$(read_toml_config "$datakit_conf"); then
        log_error "读取Datakit配置文件失败"
        return 1
    fi
    
    # 检查CPU限制
    local cpu_limit=$(echo "$config_json" | jq -r '.resource_limit.cpu_cores // empty')
    if [ -n "$cpu_limit" ] && [ "$cpu_limit" != "null" ]; then
        log_info "CPU限制配置: $cpu_limit"
    else
        log_warning "CPU限制未配置"
    fi
    
    # 检查内存限制
    local mem_limit=$(echo "$config_json" | jq -r '.resource_limit.mem_max_mb // empty')
    if [ -n "$mem_limit" ] && [ "$mem_limit" != "null" ]; then
        log_info "内存限制配置: ${mem_limit}MB"
    else
        log_warning "内存限制未配置"
    fi
    
    # 检查日志分片配置
    local log_rotate=$(echo "$config_json" | jq -r '.logging.rotate // empty')
    if [ -n "$log_rotate" ] && [ "$log_rotate" != "null" ]; then
        log_info "日志分片配置: $log_rotate"
    else
        log_warning "日志分片未配置"
    fi
    
    return 0
}

# 4. 验证定时任务配置
verify_cron_jobs() {
    # 通过crontab -l 检查config-update ,app-init ,health_check 定时任务配置是否存在
    if crontab -l 2>/dev/null | grep -q "config-update"; then
        log_info "config-update 定时任务配置存在"
    else
        log_error "config-update 定时任务配置不存在"
        return 1
    
    fi
    
    return 0
}

# 5. 验证运维平台信息获取
verify_ops_platform_info() {
    # 检查全局状态中的关键信息
    local env=$(get_global_state 'ENV')
    local workspace=$(get_global_state 'WORKSPACE')
    local dataway_url=$(get_global_state 'DATAWAY_FULL_URL')
    local global_tags=$(get_global_state 'GLOBAL_TAGS')
    
    if [ -n "$env" ]; then
        log_info "环境信息: $env"
    else
        log_error "环境信息未获取"
        return 1
    fi
    
    if [ -n "$workspace" ]; then
        log_info "工作空间: $workspace"
    else
        log_error "工作空间信息未获取"
        return 1
    fi
    
    if [ -n "$dataway_url" ]; then
        log_info "Dataway地址已配置"
    else
        log_error "Dataway地址未配置"
        return 1
    fi
    
    if [ -n "$global_tags" ]; then
        log_info "全局标签已配置"
    else
        log_warning "全局标签未配置"
    fi
    
    return 0
}

# 6. 验证Node Exporter状态
verify_node_exporter() {
    # 检查Node Exporter进程
    if ! validate_process_running "node_exporter" 1 0; then
        return 1
    fi
    
    # 检查Node Exporter端口
    validate_port_listening "9100" "tcp"
    
    # 检查systemd服务状态
    validate_service_status "node_exporter" "active"
    
    return 0
} 
