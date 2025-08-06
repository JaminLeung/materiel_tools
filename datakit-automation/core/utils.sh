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
    
    log_info "log_data: $log_data"

    if [ -n "$dataway_host" ]; then


        log_info "执行命令：curl -s -X POST $dataway_host/v1/write/logging?token=$dataway_token&precision=ns -H 'Content-Type: application/json' -d '$log_data'"

        
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
        log_warning "配置文件不存在: $config_py_file"
    fi
    
    # 如果从配置文件获取失败，尝试使用环境变量
    if [ -z "$ops_token" ]; then
        ops_token="${OPS_TOKEN:-}"
        log_info "使用环境变量OPS_TOKEN: ${ops_token:0:10}..."
    fi
    
    # 支持多种API地址配置
    local ops_addr="${CONFIG_UPDATE_OPS_API_URL:-${OPS_ADDR:-}}"
    
    if [ -z "$ops_addr" ]; then
        log_error "未配置运维平台API地址"
        log_error "CONFIG_UPDATE_OPS_API_URL: ${CONFIG_UPDATE_OPS_API_URL:-未设置}"
        log_error "OPS_ADDR: ${OPS_ADDR:-未设置}"
        return 1
    fi
    
    if [ -z "$ops_token" ]; then
        log_error "未配置OPS_TOKEN"
        log_error "请检查配置文件: $config_py_file 或环境变量OPS_TOKEN"
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
    if response=$(curl -s -w "%{http_code}" -X POST "$api_path" \
        -H "Authorization: Token $ops_token" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -d "{\"server_ip\": \"$host_ip\"}" \
        --connect-timeout 10 \
        --max-time 30 2>/dev/null); then
        
        # 检查HTTP状态码
        local http_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | head -n -1)
        
        if [ "$http_code" -eq 28 ]; then
            log_error "请求超时，当前连接超时设置为10s，最大请求时间为30s"
            return 1
        elif [ "$http_code" -ne 200 ]; then
            case "$http_code" in
                400) log_error "错误请求，可能是请求参数有误" ;;
                401) log_error "未授权，检查Token是否有效" ;;
                403) log_error "禁止访问，您没有权限访问该资源" ;;
                404) log_error "未找到，检查URL是否正确" ;;
                500) log_error "服务器内部错误，请稍后重试" ;;
                502) log_error "错误网关，可能是上游服务器问题" ;;
                503) log_error "服务不可用，服务器当前无法处理请求" ;;
                504) log_error "网关超时，服务器未能及时响应" ;;
                *) log_error "其他错误，HTTP状态码: $http_code" ;;
            esac
            return 1
        fi
        
        if [ -n "$response_body" ]; then
            # 输出响应内容用于调试
            echo "$response_body" | jq . 2>/dev/null || log_warning "无法解析JSON响应"
            
            # 验证JSON格式
            if ! echo "$response_body" | jq empty 2>/dev/null; then
                log_error "响应结果不是有效的JSON格式"
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
                    log_success "获取Datakit配置成功"
                else
                    log_warning "响应中未包含Datakit配置，使用默认配置"
                    # 设置默认Datakit配置
                    local default_datakit_config='{"enable": true, "global_config": [], "input_config": []}'
                    set_global_state "DATAKIT_CONFIG" "$default_datakit_config"
                fi
                
                log_success "获取运维平台配置成功"
                log_info "环境: $env"
                log_info "工作空间: $workspace"
                log_info "全局标签: $global_tags"
                log_info "Dataway地址: $dataway_full_url"
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
    echo "${GLOBAL_STATE[$key]:-}"
}

# 检查全局状态是否完整
check_global_state() {
    local required_keys=("HOST_IP" "ENV" "WORKSPACE" "WORKSPACE_TOKEN")
    local missing_keys=()
    
    for key in "${required_keys[@]}"; do
        if [ -z "${GLOBAL_STATE[$key]:-}" ]; then
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
    
    log_success "旧备份目录清理完成"
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
        log_error "缺少AWS凭证，无法访问私有S3 bucket"
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
        log_error "无法创建临时目录"
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
            log_success "文件下载成功: $local_path (${file_size} bytes)"
            return 0
        else
            log_error "下载的文件为空: $key"
            return 1
        fi
    else
        log_error "下载失败: $key"
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
            log_success "下载成功: $key"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "下载失败，${delay}秒后重试..."
            sleep "$delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "下载失败，已尝试 $max_attempts 次: $key"
    return 1
}

# 验证文件MD5
verify_file_md5() {
    local file_path="$1"
    local expected_md5="$2"
    
    if [ ! -f "$file_path" ]; then
        log_error "文件不存在: $file_path"
        return 1
    fi
    
    local actual_md5=$(md5sum "$file_path" | awk '{print $1}')
    
    if [ "$expected_md5" = "$actual_md5" ]; then
        log_success "MD5验证成功: $file_path"
        return 0
    else
        log_error "MD5验证失败: $file_path"
        log_error "期望: $expected_md5"
        log_error "实际: $actual_md5"
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
        log_error "文件不存在: $package_path"
        return 1
    fi
    
    # 创建解压目录
    mkdir -p "$extract_dir"
    cd "$extract_dir"
    
    # 根据文件类型解压
    case "$package_path" in
        *.tar.gz|*.tgz)
            if tar -xzf "$package_path"; then
                log_success "解压成功: $package_path"
                return 0
            else
                log_error "解压失败: $package_path"
                return 1
            fi
            ;;
        *.tar)
            if tar -xf "$package_path"; then
                log_success "解压成功: $package_path"
                return 0
            else
                log_error "解压失败: $package_path"
                return 1
            fi
            ;;
        *.zip)
            if unzip -q "$package_path"; then
                log_success "解压成功: $package_path"
                return 0
            else
                log_error "解压失败: $package_path"
                return 1
            fi
            ;;
        *)
            log_error "不支持的文件格式: $package_path"
            return 1
            ;;
    esac
}

# 安装工具到系统目录
install_tools() {
    local tools_dir="$1"
    
    log_info "安装工具到系统目录..."
    
    if [ ! -d "$tools_dir" ]; then
        log_error "工具目录不存在: $tools_dir"
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
    
    log_success "工具安装完成"
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
        log_error "缺少必需的工具: ${missing_tools[*]}"
        return 1
    fi
    
    log_success "所有必需工具检查通过"
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
        log_success "备份创建成功: $backup_path"
        return 0
    else
        log_error "备份创建失败: $source_path"
        return 1
    fi
}

# 清理临时文件（重命名避免冲突）
cleanup_package_temp_files() {
    local temp_dir="$1"
    
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        log_info "清理临时文件: $temp_dir"
        rm -rf "$temp_dir"
        log_success "临时文件清理完成"
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
    
    dataway_log "info" "设置资源限制: $(get_global_state 'CGROUP_CPU_LIMIT')C$(get_global_state 'CGROUP_MEMORY_LIMIT')MB"
}

# 验证系统资源（重命名避免冲突）
validate_system_resources_specs() {
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
 
 