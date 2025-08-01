#!/bin/bash

#=================================================
# 验证系统模块
#=================================================
# 功能: 环境变量验证、系统资源检查、网络连通性测试、配置文件验证
#=================================================

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
    
    log_success "所有必需命令验证通过"
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
        
    log_success "系统环境验证通过"
    return 0
}

# 验证系统资源
validate_system_resources() {
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
    
    log_success "系统资源验证通过"
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
    
    log_success "网络连通性验证通过"
    return 0
}

# 验证配置参数
validate_config() {
    log_info "验证配置参数..."
    local validation_passed=true
    
    # 检查必需的配置项
    local required_configs=(
        "DATAKIT_VERSION"
        "S3_BUCKET"
        "S3_ACCESS_KEY"
        "S3_SECRET_KEY"
    )
    
    for config_key in "${required_configs[@]}"; do
        if [ -z "${CONFIG[$config_key]}" ]; then
            log_error "缺少必需的配置项: $config_key"
            validation_passed=false
        fi
    done
    
    # 检查S3配置完整性
    if [ -z "${CONFIG[S3_ACCESS_KEY]}" ] || [ -z "${CONFIG[S3_SECRET_KEY]}" ]; then
        log_warning "S3访问密钥未配置，可能影响文件下载"
        validation_passed=false
    fi
    
    # 检查路径配置
    if [ ! -d "$(dirname "${CONFIG[LOG_FILE]}")" ]; then
        log_warning "日志文件目录不存在: $(dirname "${CONFIG[LOG_FILE]}")"
    fi
    
    if [ ! -d "$(dirname "${CONFIG[DATAKIT_INSTALL_DIR]}")" ]; then
        log_warning "安装目录父目录不存在: $(dirname "${CONFIG[DATAKIT_INSTALL_DIR]}")"
    fi
    
    if [ "$validation_passed" = true ]; then
        log_success "配置验证通过"
        return 0
    else
        log_error "配置验证失败"
        return 1
    fi
}

# 验证环境完整性
validate_environment() {
    log_info "验证环境完整性..."
    
    # 验证系统环境
    if ! validate_system_environment; then
        return 1
    fi
    
    # 验证系统资源
    if ! validate_system_resources; then
        return 1
    fi
    
    # 验证网络连通性
    if ! validate_network_connectivity; then
        return 1
    fi
    
    # 验证必需命令
    if ! validate_required_commands; then
        return 1
    fi
    
    # 验证配置
    if ! validate_config; then
        return 1
    fi
    
    log_success "环境完整性验证通过"
    return 0
} 