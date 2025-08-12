#!/bin/bash

#=================================================
# 工具函数模块
#=================================================
# 功能: 通用工具函数、文件操作、网络操作、系统操作
#=================================================

# 获取脚本所在目录
CORE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source外部脚本
source "$CORE_SCRIPT_DIR/logging.sh" 2>/dev/null || echo "警告: 无法加载logging.sh" >&2
source "$CORE_SCRIPT_DIR/error_handler.sh" 2>/dev/null || echo "警告: 无法加载error_handler.sh" >&2
source "$CORE_SCRIPT_DIR/initialize.sh" 2>/dev/null || echo "警告: 无法加载initialize.sh" >&2

# 声明全局状态变量
declare -A GLOBAL_STATE

# Dataway日志上报函数
dataway_log() {
    local level="$1"
    local message="$2"
    
    # 构建上报数据结构
    local log_data=$(cat <<EOF
[{
    "measurement": "datakit_host",
    "tags": {
        "level": "$level",
        "host_ip": "$(get_global_state 'HOST_IP')",
        "env": "$(get_global_state 'ENV')",
        "workspace": "$(get_global_state 'WORKSPACE')"
    },
    "time": $(date +%s%N),
    "fields": {
        "message": "$message"
    }
}]
EOF
)

    # 上报到Dataway

    # dataway_host 是从 DATAWAY_URL 中提取的
    local dataway_host=$(echo $DATAWAY_URL | awk -F'?' '{print $1}')
    local dataway_token=$(echo $DATAWAY_URL | awk -F'token=' '{print $2}')
    
    # log_info "log_data: $log_data"

    if [ -n "$dataway_host" ]; then
        # log_info "执行命令：curl -s -X POST $dataway_host/v1/write/logging?token=$dataway_token&precision=ns -H 'Content-Type: application/json' -d '$log_data'"

        
        curl -s -X POST "$dataway_host/v1/write/logging?token=$dataway_token" \
            -H "Content-Type: application/json" \
            -d "$log_data" >/dev/null 2>&1 || true
    fi
    
    # 同时记录到本地日志
    case "$level" in
        "info")
            log_info "$message"
            ;;
        "error")
            log_error "$message"
            ;;
        *)
            log_info "$message"
            ;;
    esac
}

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

# 错误上下文管理函数
set_error_context() {
    local context="$1"
    # 设置错误上下文（如果需要的话）
    # 这里可以添加错误上下文的设置逻辑
    return 0
}

clear_error_context() {
    # 清除错误上下文（如果需要的话）
    # 这里可以添加错误上下文的清除逻辑
    return 0
}

# 安全执行命令并记录日志
safe_execute() {
    local cmd="$1"
    local description="${2:-执行命令}"
    
    set_error_context "执行命令: $description"
    
    log_info "$description: $cmd"
    if eval "$cmd"; then
        log_info "$description 成功"
        clear_error_context
        return 0
    else
        local exit_code=$?
        handle_error "COMMAND_ERROR" "$description 失败" "ERROR" "false"
        clear_error_context
        return $exit_code
    fi
}

# 重试执行函数
retry_execute() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    local description="${4:-执行命令}"
    
    set_error_context "重试执行: $description"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "$description (尝试 $attempt/$max_attempts)"
        if eval "$cmd"; then
            log_info "$description 成功"
            clear_error_context
            return 0
        else
            record_error "COMMAND_ERROR" "$description 失败 (尝试 $attempt/$max_attempts)" "WARNING"
            if [ $attempt -lt $max_attempts ]; then
                log_info "等待 ${delay} 秒后重试..."
                sleep "$delay"
            fi
        fi
        attempt=$((attempt + 1))
    done
    
    handle_error "COMMAND_ERROR" "$description 失败，已重试 $max_attempts 次" "ERROR" "false"
    clear_error_context
    return 1
}

# 超时执行命令
timeout_execute() {
    local timeout="$1"
    local cmd="$2"
    local description="${3:-执行命令}"
    
    set_error_context "超时执行: $description"
    
    log_info "$description (超时: ${timeout}秒)"
    
    if timeout "$timeout" bash -c "$cmd"; then
        log_info "$description 成功"
        clear_error_context
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            handle_error "TIMEOUT_ERROR" "$description 超时 (${timeout}秒)" "ERROR" "false"
        else
            handle_error "COMMAND_ERROR" "$description 失败 (退出码: $exit_code)" "ERROR" "false"
        fi
        clear_error_context
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
    
    handle_error "COMMAND_ERROR" "$description 失败，已重试 $max_attempts 次" "ERROR" "false"
    return 1
}

# 创建备份
create_backup() {
    local source_path="$1"
    local backup_name="$2"
    
    if [[ ! -e "$source_path" ]]; then
        record_error "FILE_ERROR" "备份源不存在: $source_path" "WARNING"
        return 0
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/${backup_name}_${timestamp}"
    
    log_info "创建备份: $source_path -> $backup_path"
    
    if cp -r "$source_path" "$backup_path"; then
        SCRIPT_STATE["BACKUP_CREATED"]="true"
        log_info "备份创建成功: $backup_path"
        
        # 清理旧备份
        cleanup_old_backups "$backup_name"
        return 0
    else
        handle_error "BACKUP_ERROR" "备份创建失败: $source_path" "ERROR" "false"
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
        log_info "旧备份清理完成"
    fi
}

# 清理临时文件
cleanup_temp_files() {
    # 确保CONFIG数组已初始化
    if [ -z "${CONFIG+x}" ]; then
        declare -A CONFIG
    fi
    local temp_dir="${CONFIG[DATAKIT_INSTALL_DIR]:-/opt/datakit_install/tmp}"
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

# # 记录错误
# record_error() {
#     local error_message="$1"
#     SCRIPT_STATE["ERROR_MESSAGE"]="$error_message"
#     log_error "$error_message"
# }


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
        handle_error "NETWORK_ERROR" "无法获取本机IP地址" "ERROR" "false"
        return 1
    fi
    
    # 设置全局状态
    set_global_state "HOST_IP" "$host_ip"
    log_info "获取到本机IP地址: $host_ip"
    return 0
}

# 获取运维平台配置
get_ops_config() {
    log_info "获取运维平台配置"
    
    # 获取主机IP
    local host_ip=$(get_global_state 'HOST_IP')
    if [ -z "$host_ip" ]; then
        if ! get_host_ip; then
            return 1
        fi
        host_ip=$(get_global_state 'HOST_IP')
    fi
    
    # 从配置文件获取OPS_TOKEN
    local ops_token=""
    local config_py_file="${CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}"
    
    if [ -f "$config_py_file" ]; then
        ops_token=$(grep -v '^\s*#' "$config_py_file" | grep -oP "ops_token = '\K[^']+" 2>/dev/null || echo "")
        log_info "从配置文件获取OPS_TOKEN: ${ops_token:0:10}..."
    else
        record_error "FILE_ERROR" "配置文件不存在: $config_py_file" "WARNING"
    fi
    
    # 如果从配置文件获取失败，尝试使用环境变量
    if [ -z "$ops_token" ]; then
        ops_token="${OPS_TOKEN:-}"
        log_info "使用环境变量OPS_TOKEN: ${ops_token:0:10}..."
    fi
    
    # 支持多种API地址配置
    local ops_addr="${CONFIG_UPDATE_OPS_API_URL:-${OPS_ADDR:-}}"
    
    if [ -z "$ops_addr" ]; then
        handle_error "CONFIG_ERROR" "未配置运维平台API地址" "ERROR" "false"
        return 1
    fi
    
    if [ -z "$ops_token" ]; then
        handle_error "CONFIG_ERROR" "未配置OPS_TOKEN" "ERROR" "false"
        return 1
    fi
    
    log_info "使用API地址: $ops_addr"
    log_info "使用OPS_TOKEN: ${ops_token:0:10}..."
    
    # 构建API路径
    local api_path=""
    if [[ "$ops_addr" == *"/api/v2/cmdb/observation-agent" ]]; then
        api_path="$ops_addr"
    else
        api_path="$ops_addr/api/v2/cmdb/observation-agent"
    fi
    
    log_info "最终API路径: $api_path"
    
    # 随机休眠避免并发请求
    local random_number=$((RANDOM % 60 + 1))
    log_info "随机休眠 $random_number 秒"
    sleep $random_number

    # 调用运维平台API
    log_info "调用API: $api_path"
    log_info "请求数据: {\"server_ip\": \"$host_ip\"}"
    
    local response
    if response=$(curl -s -w "\n%{http_code}" -X POST "$api_path" \
        -H "Authorization: Token $ops_token" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -d "{\"server_ip\": \"$host_ip\"}" \
        --connect-timeout 10 \
        --max-time 30 2>/dev/null); then
        
        # 检查HTTP状态码
        local http_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | head -n -1)
        
        if [ "$http_code" -eq 28 ]; then
            handle_error "TIMEOUT_ERROR" "请求超时，当前连接超时设置为10s，最大请求时间为30s" "ERROR" "false"
            return 1
        elif [ "$http_code" -ne 200 ]; then
            case "$http_code" in
                400) handle_error "API_ERROR" "错误请求，可能是请求参数有误" "ERROR" "false" ;;
                401) handle_error "API_ERROR" "未授权，检查Token是否有效" "ERROR" "false" ;;
                403) handle_error "API_ERROR" "禁止访问，您没有权限访问该资源" "ERROR" "false" ;;
                404) handle_error "API_ERROR" "未找到，检查URL是否正确" "ERROR" "false" ;;
                500) handle_error "API_ERROR" "服务器内部错误，请稍后重试" "ERROR" "false" ;;
                502) handle_error "API_ERROR" "错误网关，可能是上游服务器问题" "ERROR" "false" ;;
                503) handle_error "API_ERROR" "服务不可用，服务器当前无法处理请求" "ERROR" "false" ;;
                504) handle_error "API_ERROR" "网关超时，服务器未能及时响应" "ERROR" "false" ;;
                *) handle_error "API_ERROR" "其他错误，HTTP状态码: $http_code" "ERROR" "false" ;;
            esac
            return 1
        fi
        
        if [ -n "$response_body" ]; then
            # 输出响应内容用于调试
            echo "$response_body" | jq . 2>/dev/null || record_error "API_ERROR" "无法解析JSON响应" "WARNING"
            
            # 验证JSON格式
            if ! echo "$response_body" | jq empty 2>/dev/null; then
                handle_error "API_ERROR" "响应结果不是有效的JSON格式" "ERROR" "false"
                return 1
            fi
            
            # 适配mock服务器的返回格式
            # 检查是否有data包装层
            local response_data="$response_body"
            if echo "$response_body" | jq -e '.data' >/dev/null 2>&1; then
                response_data=$(echo "$response_body" | jq -r '.data' 2>/dev/null)
            fi
            
            # 解析基础配置信息
            local env=$(echo "$response_data" | jq -r '.env // empty' 2>/dev/null)
            local workspace=$(echo "$response_data" | jq -r '.workspace // empty' 2>/dev/null)
            local global_tags=$(echo "$response_data" | jq -r '.global_tags.global_source // empty' 2>/dev/null)
            local dataway_url=$(echo "$response_data" | jq -r '.dataway_url // empty' 2>/dev/null)
            local workspace_token=$(echo "$response_data" | jq -r '.workspace_token // empty' 2>/dev/null)
            
            # 验证必需字段
            if [ -n "$env" ] && [ -n "$workspace" ] && [ -n "$workspace_token" ]; then
                # 设置基础配置到全局状态
                local dataway_full_url="$dataway_url?token=$workspace_token"
                set_global_state "ENV" "$env"
                set_global_state "WORKSPACE" "$workspace"
                set_global_state "GLOBAL_TAGS" "$global_tags"
                set_global_state "WORKSPACE_TOKEN" "$workspace_token"
                set_global_state "DATAWAY_FULL_URL" "$dataway_full_url"
                
                # 解析Datakit配置
                local datakit_config=$(echo "$response_data" | jq '.datakit_config // empty' 2>/dev/null)
                if [ -n "$datakit_config" ] && [ "$datakit_config" != "null" ]; then
                    # 设置Datakit配置到全局状态
                    set_global_state "DATAKIT_CONFIG" "$datakit_config"
                    log_info "获取Datakit配置成功"
                else
                    record_error "CONFIG_ERROR" "响应中未包含Datakit配置，使用默认配置" "WARNING"
                    # 设置默认Datakit配置
                    local default_datakit_config='{"enable": true, "global_config": [], "input_config": []}'
                    set_global_state "DATAKIT_CONFIG" "$default_datakit_config"
                fi
                
                log_info "获取运维平台配置成功"
                log_info "环境: $env"
                log_info "工作空间: $workspace"
                log_info "全局标签: $global_tags"
                log_info "Dataway地址: $dataway_full_url"
                return 0
            else
                handle_error "API_ERROR" "从运维平台接口获取的配置信息不完整" "ERROR" "false"
                return 1
            fi
        else
            handle_error "API_ERROR" "运维平台接口返回空响应" "ERROR" "false"
            return 1
        fi
    else
        handle_error "API_ERROR" "调用运维平台接口失败" "ERROR" "false"
        return 1
    fi
}

# 获取主机信息
get_host_info() {
    log_info "获取主机信息..."
    # 执行get_ops_config函数
    if get_ops_config; then
        log_info "主机信息验证成功"
        return 0
    else
        record_error "API_ERROR" "获取运维平台配置失败，使用默认配置" "WARNING"
        log_warning "获取运维平台配置失败，使用默认配置"
        
        # 使用缺省配置逻辑
        local dataway_url="${DATAWAY_LOG_URL:-${DATAWAY_URL:-${CONFIG_UPDATE_DATAWAY_URL:-}}}"
        local env="${ENV:-test}"
        local workspace="${WORKSPACE:-default}"


        if [ -n "$dataway_url" ]; then
            set_global_state "DATAWAY_FULL_URL" "$dataway_url"
            log_info "使用默认配置:"
            log_info "  - 环境: $env"
            log_info "  - 工作空间: $workspace"
            log_info "  - Dataway地址: $dataway_url"
        else
            handle_error "CONFIG_ERROR" "所有Dataway URL都未设置" "ERROR" "false"
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
    echo "${GLOBAL_STATE[$key]:-}"
}

# # 检查全局状态是否完整
# check_global_state() {
#     local required_keys=("HOST_IP" "ENV" "WORKSPACE" "WORKSPACE_TOKEN")
#     local missing_keys=()
    
#     for key in "${required_keys[@]}"; do
#         if [ -z "${GLOBAL_STATE[$key]:-}" ]; then
#             missing_keys+=("$key")
#         fi
#     done
    
#     if [ ${#missing_keys[@]} -gt 0 ]; then
#         log_error "缺少必需的全局状态: ${missing_keys[*]}"
#         return 1
#     fi
    
#     log_info "全局状态验证通过"
#     return 0
# } 

# =============================================================================
# 清理旧备份目录
# =============================================================================
cleanup_old_backup_dirs() {
    local backup_base_dir="$1"
    local keep_days="${2:-7}"
    
    log_info "清理旧备份目录"
    
    local current_date=$(date +%Y%m%d)
    
    if [ -d "$backup_base_dir" ]; then
        find "$backup_base_dir" -maxdepth 1 -type d -name "20*" | while read -r dir; do
            local dir_date=$(basename "$dir")
            
            # 检查目录日期是否超过保留天数
            if [ "$dir_date" != "$current_date" ]; then
                local days_diff=0
                if command_exists dateutils.ddiff; then
                    days_diff=$(dateutils.ddiff "$dir_date" "$current_date" 2>/dev/null || echo "999")
                else
                    # 简单的日期比较（假设日期格式为YYYYMMDD）
                    local dir_year=${dir_date:0:4}
                    local dir_month=${dir_date:4:2}
                    local dir_day=${dir_date:6:2}
                    local current_year=${current_date:0:4}
                    local current_month=${current_date:4:2}
                    local current_day=${current_date:6:2}
                    
                    # 简单的天数计算（近似值）
                    days_diff=$(( (current_year - dir_year) * 365 + (current_month - dir_month) * 30 + (current_day - dir_day) ))
                fi
                
                if [ "$days_diff" -gt "$keep_days" ]; then
                    log_info "删除旧备份目录: $dir_date (已保留 $days_diff 天)"
                    rm -rf "$dir"
                fi
            fi
        done
    fi
    
    log_info "旧备份目录清理完成"
}

# =============================================================================
# S3下载工具函数（从install_utils整合）
# =============================================================================

# 使用curl下载私有S3文件（AWS签名v4）
download_from_s3_with_curl() {
    local bucket="$1"
    local key="$2"
    local local_path="$3"
    
    log_info "使用curl从私有S3下载: $key"
    
    # 检查AWS凭证
    if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
        handle_error "CONFIG_ERROR" "缺少AWS凭证，无法访问私有S3 bucket" "ERROR" "false"
        return 1
    fi
    
    # 设置变量
    local http_method="GET"
    local canonical_uri="/$key"
    local canonical_querystring=""
    local timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    local date_stamp=$(date -u +%Y%m%d)
    local region="${S3_REGION:-ap-southeast-1}"
    local service="s3"
    local host="$bucket.s3.$region.amazonaws.com"
    
    # 生成负载哈希（GET请求为空）
    local payload_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    
    # 构建Canonical Headers - 确保格式完全正确
    local canonical_headers="host:$host"$'\n'"x-amz-content-sha256:$payload_hash"$'\n'"x-amz-date:$timestamp"$'\n'
    local signed_headers="host;x-amz-content-sha256;x-amz-date"
    
    # 构建Canonical Request - 使用精确的换行符
    local canonical_request="$http_method"$'\n'"$canonical_uri"$'\n'"$canonical_querystring"$'\n'"$canonical_headers"$'\n'"$signed_headers"$'\n'"$payload_hash"
    
    # 计算Canonical Request哈希
    local canonical_request_hash=$(printf "%s" "$canonical_request" | sha256sum | awk '{print $1}')
    
    # 构建String to Sign
    local credential_scope="$date_stamp/$region/$service/aws4_request"
    local string_to_sign="AWS4-HMAC-SHA256"$'\n'"$timestamp"$'\n'"$credential_scope"$'\n'"$canonical_request_hash"
    
    # 生成签名密钥 - 使用简单方法避免null byte问题
    local kSecret="AWS4$S3_SECRET_KEY"
    local temp_dir=$(mktemp -d)
    # 注意：trap 在函数内部可能导致过早清理，改为手动清理
    # 确保临时目录存在
    if [ ! -d "$temp_dir" ]; then
        handle_error "FILE_ERROR" "无法创建临时目录" "ERROR" "false"
        return 1
    fi
    
    # 调试信息
    log_info "临时目录: $temp_dir"
    log_info "kSecret: ${kSecret:0:20}..."
    log_info "S3_SECRET_KEY: ${S3_SECRET_KEY:0:10}..."
    log_info "S3_ACCESS_KEY: ${S3_ACCESS_KEY:0:10}..."
    
    # kDate
    local kDate=$(echo -n "$date_stamp" | openssl dgst -sha256 -hmac "$kSecret" -binary)
    
    # kRegion
    local kRegion=$(echo -n "$region" | openssl dgst -sha256 -hmac "$kDate" -binary)
    
    # kService
    local kService=$(echo -n "$service" | openssl dgst -sha256 -hmac "$kRegion" -binary)
    
    # kSigning
    local kSigning=$(echo -n "aws4_request" | openssl dgst -sha256 -hmac "$kService" -binary)
    
    # 生成签名
    echo -n "$string_to_sign" > "$temp_dir/string_input"
    local signature=$(openssl dgst -sha256 -hmac "$kSigning" "$temp_dir/string_input" | awk '{print $2}')
    
    # 生成授权头
    local authorization_header="AWS4-HMAC-SHA256 Credential=$S3_ACCESS_KEY/$credential_scope,SignedHeaders=$signed_headers,Signature=$signature"
    
    # 构建完整URL
    local s3_url="https://$host$canonical_uri"
    
    # 使用curl下载
    log_info "开始下载文件..."
    if curl -L -o "$local_path" "$s3_url" \
        -H "Authorization: $authorization_header" \
        -H "x-amz-content-sha256: $payload_hash" \
        -H "x-amz-date: $timestamp" \
        --connect-timeout 30 --max-time "${DOWNLOAD_TIMEOUT:-300}"; then
        
        # 检查文件大小，确保下载成功
        local file_size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path" 2>/dev/null)
        if [ "$file_size" -gt 0 ]; then
            log_info "文件下载成功: $local_path (${file_size} bytes)"
            return 0
        else
            handle_error "NETWORK_ERROR" "下载的文件为空: $key" "ERROR" "false"
            return 1
        fi
    else
        handle_error "NETWORK_ERROR" "下载失败: $key" "ERROR" "false"
        # 清理临时目录
        rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir" 2>/dev/null || true
}

# 带重试的S3下载
download_from_s3_with_retry() {
    local bucket="$1"
    local key="$2"
    local local_path="$3"
    local max_attempts="${4:-${MAX_RETRY_ATTEMPTS:-3}}"
    local delay="${5:-${RETRY_DELAY:-5}}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "下载尝试 $attempt/$max_attempts: $key"
        
        if download_from_s3_with_curl "$bucket" "$key" "$local_path"; then
            log_info "下载成功: $key"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            record_error "NETWORK_ERROR" "下载失败，${delay}秒后重试..." "WARNING"
            sleep "$delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    handle_error "NETWORK_ERROR" "下载失败，已尝试 $max_attempts 次: $key" "ERROR" "false"
    return 1
}

# 验证文件MD5
verify_file_md5() {
    local file_path="$1"
    local expected_md5="$2"
    
    if [ ! -f "$file_path" ]; then
        handle_error "FILE_ERROR" "文件不存在: $file_path" "ERROR" "false"
        return 1
    fi
    
    local actual_md5=$(md5sum "$file_path" | awk '{print $1}')
    
    if [ "$expected_md5" = "$actual_md5" ]; then
        log_info "MD5验证成功: $file_path"
        return 0
    else
        handle_error "VALIDATION_ERROR" "MD5验证失败: $file_path" "ERROR" "false"
        return 1
    fi
}

# =============================================================================
# 包安装工具函数（从install_utils整合）
# =============================================================================

# 解压文件
extract_package() {
    local package_path="$1"
    local extract_dir="$2"
    
    log_info "解压文件: $package_path"
    
    if [ ! -f "$package_path" ]; then
        handle_error "FILE_ERROR" "文件不存在: $package_path" "ERROR" "false"
        return 1
    fi
    
    # 创建解压目录
    mkdir -p "$extract_dir"
    cd "$extract_dir"
    
    # 根据文件类型解压
    case "$package_path" in
        *.tar.gz|*.tgz)
            if tar -xzf "$package_path"; then
                log_info "解压成功: $package_path"
                return 0
            else
                handle_error "FILE_ERROR" "解压失败: $package_path" "ERROR" "false"
                return 1
            fi
            ;;
        *.tar)
            if tar -xf "$package_path"; then
                log_info "解压成功: $package_path"
                return 0
            else
                handle_error "FILE_ERROR" "解压失败: $package_path" "ERROR" "false"
                return 1
            fi
            ;;
        *.zip)
            if unzip -q "$package_path"; then
                log_info "解压成功: $package_path"
                return 0
            else
                handle_error "FILE_ERROR" "解压失败: $package_path" "ERROR" "false"
                return 1
            fi
            ;;
        *)
            handle_error "FILE_ERROR" "不支持的文件格式: $package_path" "ERROR" "false"
            return 1
            ;;
    esac
}

# 安装工具到系统目录
install_tools() {
    local tools_dir="$1"
    
    log_info "安装工具到系统目录..."
    
    if [ ! -d "$tools_dir" ]; then
        handle_error "FILE_ERROR" "工具目录不存在: $tools_dir" "ERROR" "false"
        return 1
    fi
    
    cd "$tools_dir"
    
    # 安装jq
    if [ -f "./jq" ]; then
        cp ./jq /usr/local/bin/ && chmod +x /usr/local/bin/jq
        log_info "jq工具安装完成"
    fi
    
    # 安装yj
    if [ -f "./yj" ]; then
        cp ./yj /usr/local/bin/ && chmod +x /usr/local/bin/yj
        log_info "yj工具安装完成"
    fi
    
    log_info "工具安装完成"
}

# 检查必需的工具
check_required_tools() {
    local missing_tools=()
    
    # 检查必需的工具
    local required_tools=("curl" "jq" "systemctl" "tar")
    
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        handle_error "DEPENDENCY_ERROR" "缺少必需的工具: ${missing_tools[*]}" "ERROR" "false"
        return 1
    fi
    
    log_info "所有必需工具检查通过"
    return 0
}

# 创建备份（重命名避免冲突）
create_package_backup() {
    local source_path="$1"
    local backup_dir="$2"
    
    if [ ! -e "$source_path" ]; then
        log_info "源路径不存在，无需备份: $source_path"
        return 0
    fi
    
    # 创建备份目录
    mkdir -p "$backup_dir"
    
    # 生成备份文件名
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$source_path")
    local backup_path="$backup_dir/${basename}.backup.${timestamp}"
    
    # 执行备份
    if cp -r "$source_path" "$backup_path"; then
        log_info "备份创建成功: $backup_path"
        return 0
    else
        handle_error "BACKUP_ERROR" "备份创建失败: $source_path" "ERROR" "false"
        return 1
    fi
}

# 清理临时文件（重命名避免冲突）
cleanup_package_temp_files() {
    local temp_dir="$1"
    
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        log_info "清理临时文件: $temp_dir"
        rm -rf "$temp_dir"
        log_info "临时文件清理完成"
    fi
}

# =============================================================================
# 机器规格检测工具函数（从install_utils整合）
# =============================================================================

# 获取机器规格并设置资源限制
get_machine_specs() {
    log_info "获取机器规格并设置资源限制..."
    
    # 获取CPU规格
    local cpu_cores=$(lscpu | grep "CPU(s)" | cut -d ':' -f 2 | sed 's/^ //' | awk '{print $1}' | head -n 1)
    
    # 获取内存规格（GB）
    local memory_gb=$(free -g | grep "Mem" | awk '{print $2}')
    
    log_info "机器规格: ${cpu_cores}核 ${memory_gb}GB"
    
    # 根据规格设置资源限制
    if [ "$cpu_cores" -lt 4 ] || [ "$memory_gb" -lt 8 ]; then
        # 2C4G ~ 4C8G: 使用规格的12.5%，最低0.5C0.5G
        local cpu_limit_raw=$(echo "$cpu_cores * 0.125" | bc | sed 's/^\./0./' | sed 's/\.$//')
        local memory_limit_raw=$(echo "$memory_gb * 0.125 * 1024" | bc | sed 's/^\./0./' | sed 's/\.$//')
        
        # 确保最低限制：0.5C0.5G
        local cpu_limit
        if (( $(echo "$cpu_limit_raw < 0.5" | bc -l) )); then
            cpu_limit="0.5"
        else
            cpu_limit="$cpu_limit_raw"
        fi
        
        local memory_limit
        if (( $(echo "$memory_limit_raw < 0.5" | bc -l) )); then
            memory_limit="512"  # 0.5GB = 512MB
        else
            memory_limit=$(echo "$memory_limit_raw " | bc | sed 's/^\./0./' | sed 's/\.$//')    
        fi
        
        # 设置全局状态
        set_global_state "CGROUP_CPU_LIMIT" "$cpu_limit"
        set_global_state "CGROUP_MEMORY_LIMIT" "$memory_limit"
        


        log_info "2C4G~4C8G 规格资源限制计算:"
        log_info "CPU原始限制: ${cpu_limit_raw}C (规格的12.5%)"
        log_info "内存原始限制: ${memory_limit_raw}GB (规格的12.5%)"
        log_info "CPU最终限制: ${cpu_limit}C (应用最低限制0.5C)"
        log_info "内存最终限制: ${memory_limit}MB (应用最低限制0.5GB)"
        log_info "设置动态资源限制: ${cpu_limit}C${memory_limit}MB"
        
    else
        # ≥ 4C8G: 使用固定限制
        set_global_state "CGROUP_CPU_LIMIT" "1"
        set_global_state "CGROUP_MEMORY_LIMIT" "2048"
        log_info "≥4C8G规格，设置默认资源限制: 1C2G"
    fi
    
    log_info "设置资源限制: $(get_global_state 'CGROUP_CPU_LIMIT')C$(get_global_state 'CGROUP_MEMORY_LIMIT')MB"
    
    # 验证资源限制是否满足最低要求
    local cpu_limit=$(get_global_state 'CGROUP_CPU_LIMIT')
    local memory_limit=$(get_global_state 'CGROUP_MEMORY_LIMIT')
    
    # 使用 bc 进行浮点数比较
    if (( $(echo "$cpu_limit < 0.5" | bc -l) )) || (( $(echo "$memory_limit < 512" | bc -l) )); then
        handle_error "RESOURCE_ERROR" "资源限制不满足最低要求: CPU=${cpu_limit}C, 内存=${memory_limit}MB" "ERROR" "false"
        return 1
    fi
    
    log_info "资源限制验证通过: CPU=${cpu_limit}C, 内存=${memory_limit}MB"
    return 0
    
}

# =============================================================================
# 配置文件处理相关函数（从 config_file.sh 合并）
# =============================================================================

# 全局配置变量
declare -A CONFIG_VALUES

# 默认配置文件路径
DEFAULT_CONFIG_FILE=""

read_toml_config() {
    local toml_file="$1"
    [ -f "$toml_file" ] || handle_error "FILE_ERROR" "配置文件不存在: $toml_file" "ERROR" "false"
    command_exists yj || handle_error "DEPENDENCY_ERROR" "命令 'yj' 不存在" "ERROR" "false"
    yj -t < "$toml_file" 2>/dev/null || handle_error "FILE_ERROR" "TOML文件读取失败: $toml_file" "ERROR" "false"
}

update_toml_config() {
    local toml_file="$1"
    local json_data="$2"
    local current_config
    if [ -f "$toml_file" ]; then
        current_config=$(read_toml_config "$toml_file") || {
            handle_error "FILE_ERROR" "读取当前配置文件失败: $toml_file" "ERROR" "false"
            return 1
        }
    else
        log_info "配置文件不存在，将创建新文件: $toml_file"
        current_config="{}"
    fi
    if [ "$current_config" = "$json_data" ]; then
        log_info "配置相同，跳过更新: $toml_file"
        return 0
    fi
    # 使用CONFIG_UPDATE_BACKUP_DIR，如果未定义则使用默认值
    local backup_dir="${CONFIG_UPDATE_BACKUP_DIR:-/var/backups/datakit}"
    safe_execute "mkdir -p '$backup_dir'" "创建备份目录" || return 1
    local filename=$(basename "$toml_file")
    local backup_file="$backup_dir/${filename}.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -f "$toml_file" ]; then
        safe_execute "cp '$toml_file' '$backup_file'" "备份配置文件" || return 1
        log_info "备份文件: $backup_file"
    else
        log_info "原文件不存在，无需备份"
    fi
    safe_execute "echo '$json_data' | yj -jt > '$toml_file'" "更新配置文件" || return 1
    log_info "配置文件更新成功: $toml_file"
    log_info "备份文件: $backup_file"
    return 0
}

get_json_path_value() {
    local json_data="$1"
    local json_path="$2"
    local value
    value=$(echo "$json_data" | jq "$json_path" 2>/dev/null)
    local jq_ret=$?
    if [ $jq_ret -eq 0 ] && [ "$value" != "null" ]; then
        local first_char="${value:0:1}"
        if [ "$first_char" = "[" ] || [ "$first_char" = "{" ]; then
            echo "$value"
        else
            echo "$json_data" | jq -r "$json_path" 2>/dev/null
        fi
        return 0
    fi
    return 1
}

set_json_path_value() {
    local json_data="$1"
    local json_path="$2"
    local new_value="$3"
    local updated_json
    if [[ "$new_value" =~ ^\[.*\]$ ]]; then
        updated_json=$(echo "$json_data" | jq "$json_path = $new_value" 2>/dev/null)
    elif [[ "$new_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        updated_json=$(echo "$json_data" | jq "$json_path = $new_value" 2>/dev/null)
    elif [[ "$new_value" =~ ^(true|false)$ ]]; then
        updated_json=$(echo "$json_data" | jq "$json_path = $new_value" 2>/dev/null)
    else
        updated_json=$(echo "$json_data" | jq "$json_path = \"$new_value\"" 2>/dev/null)
    fi
    if [ $? -eq 0 ]; then
        echo "$updated_json"
        return 0
    fi
    return 1
}

# =============================================================================
# 配置管理函数
# =============================================================================

# 设置默认配置文件路径
set_default_config_file() {
    local config_file="$1"
    DEFAULT_CONFIG_FILE="$config_file"
}

# 加载配置文件
load_config_file() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    if [ -z "$config_file" ]; then
        handle_error "CONFIG_ERROR" "未指定配置文件路径" "ERROR" "false"
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        handle_error "CONFIG_ERROR" "配置文件不存在: $config_file" "ERROR" "false"
        return 1
    fi
    
    log_info "加载配置文件: $config_file"
    
    # 清空现有配置
    CONFIG_VALUES=()
    
    # 读取TOML配置文件并转换为JSON
    local json_config
    json_config=$(yj -t < "$config_file" 2>/dev/null) || {
        handle_error "CONFIG_ERROR" "配置文件格式错误: $config_file" "ERROR" "false"
        return 1
    }
    
    # 解析配置项并存储到关联数组中
    local sections
    sections=$(echo "$json_config" | jq -r 'keys[]' 2>/dev/null)
    
    for section in $sections; do
        local section_data
        section_data=$(echo "$json_config" | jq -r ".[\"$section\"]" 2>/dev/null)
        
        if [ "$section_data" != "null" ]; then
            local keys
            keys=$(echo "$section_data" | jq -r 'keys[]' 2>/dev/null)
            
            for key in $keys; do
                local value
                value=$(echo "$section_data" | jq -r ".[\"$key\"]" 2>/dev/null)
                CONFIG_VALUES["${section}_${key}"]="$value"
                log_debug "加载配置: ${section}_${key} = $value"
            done
        fi
    done
    
    log_info "配置文件加载完成: $config_file"
    return 0
}

# 获取配置值
get_config_value() {
    local key="$1"
    local default_value="${2:-}"
    
    if [ -z "$key" ]; then
        handle_error "CONFIG_ERROR" "配置键不能为空" "ERROR" "false"
        return 1
    fi
    
    local value="${CONFIG_VALUES[$key]:-}"
    
    if [ -z "$value" ]; then
        if [ -n "$default_value" ]; then
            log_debug "配置键 '$key' 未找到，使用默认值: $default_value"
            echo "$default_value"
            return 0
        else
            handle_error "CONFIG_ERROR" "配置键 '$key' 未找到且无默认值" "ERROR" "false"
            return 1
        fi
    fi
    
    echo "$value"
    return 0
}

# 设置配置值
set_config_value() {
    local key="$1"
    local value="$2"
    
    if [ -z "$key" ]; then
        handle_error "CONFIG_ERROR" "配置键不能为空" "ERROR" "false"
        return 1
    fi
    
    CONFIG_VALUES["$key"]="$value"
    log_debug "设置配置: $key = $value"
    return 0
}

# 检查配置键是否存在
has_config_key() {
    local key="$1"
    
    if [ -z "$key" ]; then
        return 1
    fi
    
    [ -n "${CONFIG_VALUES[$key]:-}" ]
}

# 列出所有配置键
list_config_keys() {
    local pattern="${1:-*}"
    
    for key in "${!CONFIG_VALUES[@]}"; do
        if [[ "$key" == $pattern ]]; then
            echo "$key"
        fi
    done
}

# 导出配置为环境变量
export_config_as_env() {
    local prefix="${1:-CONFIG_}"
    
    for key in "${!CONFIG_VALUES[@]}"; do
        local env_key="${prefix}${key^^}"
        export "$env_key"="${CONFIG_VALUES[$key]}"
        log_debug "导出环境变量: $env_key = ${CONFIG_VALUES[$key]}"
    done
    
    log_info "配置已导出为环境变量 (前缀: $prefix)"
}

# 验证必需配置项
validate_required_config() {
    local required_keys=("$@")
    local missing_keys=()
    
    for key in "${required_keys[@]}"; do
        if ! has_config_key "$key"; then
            missing_keys+=("$key")
        fi
    done
    
    if [ ${#missing_keys[@]} -gt 0 ]; then
        handle_error "CONFIG_ERROR" "缺少必需的配置项: ${missing_keys[*]}" "ERROR" "false"
        return 1
    fi
    
    log_info "所有必需配置项验证通过"
    return 0
}

# 生成配置模板
generate_config_template() {
    local output_file="$1"
    local template_content="$2"
    
    if [ -z "$output_file" ]; then
        handle_error "CONFIG_ERROR" "输出文件路径不能为空" "ERROR" "false"
        return 1
    fi
    
    if [ -z "$template_content" ]; then
        handle_error "CONFIG_ERROR" "模板内容不能为空" "ERROR" "false"
        return 1
    fi
    
    # 创建目录
    local dir=$(dirname "$output_file")
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            handle_error "FILE_ERROR" "创建目录失败: $dir" "ERROR" "false"
            return 1
        }
    fi
    
    # 写入模板文件
    echo "$template_content" > "$output_file" || {
        handle_error "FILE_ERROR" "写入模板文件失败: $output_file" "ERROR" "false"
        return 1
    }
    
    log_info "配置模板已生成: $output_file"
    return 0
} 

# =============================================================================
# 定时任务包装函数（从 cron_wrapper.sh 合并）
# =============================================================================

# 执行定时任务包装
# 参数: $1 - 任务类型 (config_update|health_check|app_init)
#       $2 - 脚本路径
execute_cron_wrapper() {
    local task_type="$1"
    local script_path="$2"
    
    # 验证参数
    if [ -z "$task_type" ]; then
        handle_error "CONFIG_ERROR" "缺少任务类型参数" "ERROR" "false"
        return 1
    fi
    
    if [ -z "$script_path" ]; then
        handle_error "CONFIG_ERROR" "缺少脚本路径参数" "ERROR" "false"
        return 1
    fi
    
    # 根据任务类型设置配置
    local lock_file=""
    local log_file=""
    local task_name=""
    
    case "$task_type" in
        "config_update")
            lock_file="${CONFIG_UPDATE_LOCK_FILE:-/var/run/config_update.lock}"
            log_file="${CONFIG_UPDATE_LOG_FILE:-/opt/datakit/config_update.log}"
            task_name="${CONFIG_UPDATE_TASK_NAME:-config_update.sh}"
            ;;
        "health_check")
            lock_file="${HEALTH_CHECK_LOCK_FILE:-/var/run/datakit_health_check.lock}"
            log_file="${HEALTH_CHECK_LOG_FILE:-/opt/datakit/health_check.log}"
            task_name="${HEALTH_CHECK_TASK_NAME:-datakit_health_check.sh}"
            ;;
        "app_init")
            lock_file="${APP_INIT_LOCK_FILE:-/var/run/app_init.lock}"
            log_file="${APP_INIT_LOG_FILE:-/opt/datakit/app_init.log}"
            task_name="${APP_INIT_TASK_NAME:-app_init.sh}"
            ;;
        *)
            handle_error "CONFIG_ERROR" "未知的任务类型: $task_type" "ERROR" "false"
            return 1
            ;;
    esac
    
    # 确保日志目录存在
    local log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir" 2>/dev/null || true
    
    # 清空日志文件，只保留最新内容
    > "$log_file" 2>/dev/null || true
    
    # 记录执行开始
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始执行$task_name" > "$log_file"
    
    # 检查锁文件
    if [ -f "$lock_file" ]; then
        # 读取锁文件中的PID
        local pid=$(cat "$lock_file" 2>/dev/null)
        
        # 检查进程是否还在运行
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 上一个$task_name任务(PID: $pid)还在运行，跳过本次执行" >> "$log_file"
            return 0
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 发现僵尸锁文件，清理并继续执行" >> "$log_file"
            rm -f "$lock_file"
        fi
    fi
    
    # 执行实际脚本（脚本内部会处理锁机制）
    if [ -f "$script_path" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 执行脚本: $script_path" >> "$log_file"
        if bash "$script_path" >> "$log_file" 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $task_name执行成功" >> "$log_file"
            return 0
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $task_name执行失败" >> "$log_file"
            return 1
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 脚本文件不存在: $script_path" >> "$log_file"
        return 1
    fi
}

# 获取任务配置信息
# 参数: $1 - 任务类型
# 返回: 锁文件路径、日志文件路径、任务名称
get_task_config() {
    local task_type="$1"
    
    case "$task_type" in
        "config_update")
            echo "${CONFIG_UPDATE_LOCK_FILE:-/var/run/config_update.lock}"
            echo "${CONFIG_UPDATE_LOG_FILE:-/opt/datakit/config_update.log}"
            echo "${CONFIG_UPDATE_TASK_NAME:-config_update.sh}"
            ;;
        "health_check")
            echo "${HEALTH_CHECK_LOCK_FILE:-/var/run/datakit_health_check.lock}"
            echo "${HEALTH_CHECK_LOG_FILE:-/opt/datakit/health_check.log}"
            echo "${HEALTH_CHECK_TASK_NAME:-datakit_health_check.sh}"
            ;;
        "app_init")
            echo "${APP_INIT_LOCK_FILE:-/var/run/app_init.lock}"
            echo "${APP_INIT_LOG_FILE:-/opt/datakit/app_init.log}"
            echo "${APP_INIT_TASK_NAME:-app_init.sh}"
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查任务是否正在运行
# 参数: $1 - 任务类型
# 返回: 0 - 正在运行, 1 - 未运行
is_task_running() {
    local task_type="$1"
    local lock_file=""
    
    case "$task_type" in
        "config_update")
            lock_file="${CONFIG_UPDATE_LOCK_FILE:-/var/run/config_update.lock}"
            ;;
        "health_check")
            lock_file="${HEALTH_CHECK_LOCK_FILE:-/var/run/datakit_health_check.lock}"
            ;;
        "app_init")
            lock_file="${APP_INIT_LOCK_FILE:-/var/run/app_init.lock}"
            ;;
        *)
            return 1
            ;;
    esac
    
    if [ -f "$lock_file" ]; then
        local pid=$(cat "$lock_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0  # 正在运行
        fi
    fi
    
    return 1  # 未运行
}

# 清理任务锁文件
# 参数: $1 - 任务类型
cleanup_task_lock() {
    local task_type="$1"
    local lock_file=""
    
    case "$task_type" in
        "config_update")
            lock_file="${CONFIG_UPDATE_LOCK_FILE:-/var/run/config_update.lock}"
            ;;
        "health_check")
            lock_file="${HEALTH_CHECK_LOCK_FILE:-/var/run/datakit_health_check.lock}"
            ;;
        "app_init")
            lock_file="${APP_INIT_LOCK_FILE:-/var/run/app_init.lock}"
            ;;
        *)
            return 1
            ;;
    esac
    
    if [ -f "$lock_file" ]; then
        rm -f "$lock_file"
        log_info "已清理任务锁文件: $lock_file"
        return 0
    fi
    
    return 1
} 

 