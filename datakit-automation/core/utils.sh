#!/bin/bash

#=================================================
# 工具函数模块
#=================================================
# 功能: 通用工具函数、文件操作、网络操作、系统操作
#=================================================

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查文件是否存在
file_exists() {
    [ -f "$1" ]
}

# 检查目录是否存在
dir_exists() {
    [ -d "$1" ]
}

# 检查进程是否运行
process_running() {
    pgrep -x "$1" >/dev/null 2>&1
}

# 检查端口是否被监听
port_listening() {
    local port="$1"
    netstat -tlnp 2>/dev/null | grep -q ":$port " || \
    ss -tlnp 2>/dev/null | grep -q ":$port "
}

# 安全执行命令并记录日志
safe_execute() {
    local cmd="$1"
    local description="${2:-执行命令}"
    
    log_info "$description: $cmd"
    if eval "$cmd"; then
        log_success "$description 成功"
        return 0
    else
        log_error "$description 失败"
        return 1
    fi
}

# 重试执行函数
retry_execute() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    local description="${4:-执行命令}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "$description (尝试 $attempt/$max_attempts)"
        if eval "$cmd"; then
            log_success "$description 成功"
            return 0
        else
            log_warning "$description 失败 (尝试 $attempt/$max_attempts)"
            if [ $attempt -lt $max_attempts ]; then
                log_info "等待 ${delay} 秒后重试..."
                sleep "$delay"
            fi
        fi
        attempt=$((attempt + 1))
    done
    
    log_error "$description 失败，已重试 $max_attempts 次"
    return 1
}

# 超时执行命令
timeout_execute() {
    local timeout="$1"
    local cmd="$2"
    local description="${3:-执行命令}"
    
    log_info "$description (超时: ${timeout}秒)"
    
    if timeout "$timeout" bash -c "$cmd"; then
        log_success "$description 成功"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "$description 超时 (${timeout}秒)"
        else
            log_error "$description 失败 (退出码: $exit_code)"
        fi
        return $exit_code
    fi
}

# 带重试的安全执行
retry_safe_execute() {
    local cmd="$1"
    local description="${2:-执行命令}"
    local max_attempts="${3:-$MAX_RETRY_ATTEMPTS}"
    local timeout="${4:-$COMMAND_TIMEOUT}"
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "$description (尝试 $attempt/$max_attempts)"
        
        if timeout_execute "$timeout" "$cmd" "$description"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            local delay=$((attempt * 5))  # 递增延迟
            log_warning "$description 失败，${delay}秒后重试..."
            sleep "$delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "$description 失败，已重试 $max_attempts 次"
    return 1
}

# 创建备份
create_backup() {
    local source_path="$1"
    local backup_name="$2"
    
    if [[ ! -e "$source_path" ]]; then
        log_warning "备份源不存在: $source_path"
        return 0
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/${backup_name}_${timestamp}"
    
    log_info "创建备份: $source_path -> $backup_path"
    
    if cp -r "$source_path" "$backup_path"; then
        SCRIPT_STATE["BACKUP_CREATED"]="true"
        log_success "备份创建成功: $backup_path"
        
        # 清理旧备份
        cleanup_old_backups "$backup_name"
        return 0
    else
        log_error "备份创建失败: $source_path"
        return 1
    fi
}

# 清理旧备份
cleanup_old_backups() {
    local backup_name="$1"
    
    # 按修改时间排序，保留最新的MAX_BACKUP_COUNT个
    local old_backups=$(find "$BACKUP_DIR" -name "${backup_name}_*" -type d -printf '%T@ %p\n' | sort -n | head -n -$MAX_BACKUP_COUNT | awk '{print $2}')
    
    if [[ -n "$old_backups" ]]; then
        log_info "清理旧备份..."
        echo "$old_backups" | xargs rm -rf
        log_success "旧备份清理完成"
    fi
}

# 清理临时文件
cleanup_temp_files() {
    local temp_dir="${CONFIG[DATAKIT_INSTALL_DIR]}"
    if [ -n "$temp_dir" ] && dir_exists "$temp_dir"; then
        log_info "清理临时文件: $temp_dir"
        rm -rf "$temp_dir"
    fi
}

# 清理AWS凭证
cleanup_aws_credentials() {
    if dir_exists ~/.aws; then
        log_info "清理AWS凭证"
        rm -rf ~/.aws
    fi
}

# 完整清理函数
full_cleanup() {
    cleanup_temp_files
    cleanup_aws_credentials
    log_info "清理完成"
}

# 设置当前步骤
set_current_step() {
    local step="$1"
    SCRIPT_STATE["CURRENT_STEP"]="$step"
    log_info "当前步骤: $step"
}

# 记录错误
record_error() {
    local error_message="$1"
    SCRIPT_STATE["ERROR_MESSAGE"]="$error_message"
    log_error "$error_message"
}


# 获取本机IP地址
get_host_ip() {
    log_info "获取本机IP地址..."
    
    # 使用 `ip` 命令获取主网卡的 IP 地址，排除回环地址
    local host_ip=$(ip -4 addr show | grep -v '127.0.0.1' | awk '/inet/ {print $2}' | cut -d'/' -f1 | head -n 1)
    
    # 如果没有找到 IP 地址，尝试使用 `ifconfig` 命令
    if [ -z "$host_ip" ]; then
        host_ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
    fi
    
    if [ -z "$host_ip" ]; then
        log_error "无法获取本机IP地址"
        return 1
    fi
    
    # 设置全局状态
    set_global_state "HOST_IP" "$host_ip"
    log_success "获取到本机IP地址: $host_ip"
    return 0
}

# 获取运维平台配置
get_ops_config() {
    log_info "获取运维平台配置..."
    
    # 确保已获取主机IP
    if [ -z "$(get_global_state 'HOST_IP')" ]; then
        if ! get_host_ip; then
            log_error "获取本机IP地址失败"
            return 1
        fi
    fi
    
    local host_ip=$(get_global_state 'HOST_IP')
    local ops_addr="${CONFIG[OPS_ADDR]}"
    local ops_token="${CONFIG[OPS_TOKEN]}"
    
    # 调用运维平台接口获取配置信息
    local response
    if response=$(curl -s -X POST "$ops_addr/api/v2/cmdb/observation-agent" \
        -H "Content-Type: application/json" \
        -d "{\"server_ip\": \"$host_ip\"}" 2>/dev/null); then
        
        # 输出response并jq解析
        echo "$response" | jq . 2>/dev/null || log_warning "无法解析JSON响应"
        
        if [ -n "$response" ]; then
            # 解析返回数据
            local env=$(echo "$response" | jq -r '.env // empty' 2>/dev/null)
            local workspace=$(echo "$response" | jq -r '.workspace // empty' 2>/dev/null)
            local global_tags=$(echo "$response" | jq -r '.global_tags.global_source // empty' 2>/dev/null)
            local dataway_url=$(echo "$response" | jq -r '.dataway_url // empty' 2>/dev/null)
            local workspace_token=$(echo "$response" | jq -r '.workspace_token // empty' 2>/dev/null)
            
            if [ -n "$env" ] && [ -n "$workspace" ] && [ -n "$workspace_token" ]; then
                # 构建完整的Dataway URL
                local dataway_full_url="$dataway_url?token=$workspace_token"
                
                # 设置全局状态
                set_global_state "ENV" "$env"
                set_global_state "WORKSPACE" "$workspace"
                set_global_state "GLOBAL_TAGS" "$global_tags"
                set_global_state "WORKSPACE_TOKEN" "$workspace_token"
                set_global_state "DATAWAY_FULL_URL" "$dataway_full_url"
                
                log_success "获取运维平台配置成功"
                log_info "环境: $env"
                log_info "工作空间: $workspace"
                log_info "全局标签: $global_tags"
                log_info "Dataway地址: $dataway_full_url"
                
                # 上报成功日志
                dataway_log "info" "成功获取运维平台配置: env=$env, workspace=$workspace"
                return 0
            else
                log_error "从运维平台接口获取的配置信息不完整"
                log_error "ENV: $env"
                log_error "WORKSPACE: $workspace"
                log_error "WORKSPACE_TOKEN: $workspace_token"
                return 1
            fi
        else
            log_error "运维平台接口返回空响应"
            return 1
        fi
    else
        log_error "调用运维平台接口失败"
        return 1
    fi
}

# 获取主机信息
get_host_info() {
    log_info "获取主机信息..."
    
    # 检查全局状态是否完整
    if check_global_state; then
        log_success "主机信息验证成功"
        log_info "环境: $(get_global_state 'ENV')"
        log_info "工作空间: $(get_global_state 'WORKSPACE')"
        log_info "全局标签: $(get_global_state 'GLOBAL_TAGS')"
        log_info "Dataway地址: $(get_global_state 'DATAWAY_FULL_URL')"
        
        # 上报成功日志
        dataway_log "info" "主机信息验证成功: env=$(get_global_state 'ENV'), workspace=$(get_global_state 'WORKSPACE')"
        return 0
    else
        # 执行get_ops_config函数
        if get_ops_config; then
            log_success "主机信息验证成功"
            return 0
        else
            log_error "主机信息不完整，请检查get_ops_config函数"
            dataway_log "error" "主机信息不完整"
            return 1
        fi
    fi
}

# 设置全局状态
set_global_state() {
    local key="$1"
    local value="$2"
    GLOBAL_STATE["$key"]="$value"
}

# 获取全局状态
get_global_state() {
    local key="$1"
    echo "${GLOBAL_STATE[$key]}"
}

# 检查全局状态是否完整
check_global_state() {
    local required_keys=("HOST_IP" "ENV" "WORKSPACE" "WORKSPACE_TOKEN")
    local missing_keys=()
    
    for key in "${required_keys[@]}"; do
        if [ -z "${GLOBAL_STATE[$key]}" ]; then
            missing_keys+=("$key")
        fi
    done
    
    if [ ${#missing_keys[@]} -gt 0 ]; then
        log_error "缺少必需的全局状态: ${missing_keys[*]}"
        return 1
    fi
    
    log_success "全局状态验证通过"
    return 0
} 

