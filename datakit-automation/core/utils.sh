#!/bin/bash

#=================================================
# 工具函数模块
#=================================================
# 功能: 通用工具函数、文件操作、网络操作、系统操作
#=================================================

# 获取脚本所在目录
CORE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
load_module() {
    local module_name="$1"
    local module_file="$2"
    
    if [[ -f "$module_file" ]]; then
        source "$module_file"
        echo "INFO: 加载模块: $module_name"
    else
        echo "[ERROR] 模块文件不存在: $module_file" >&2
        exit 1
    fi
}
# Source外部脚本
load_module "logging" "$CORE_SCRIPT_DIR/logging.sh"
load_module "error_handler" "$CORE_SCRIPT_DIR/error_handler.sh"
load_module "initialize" "$CORE_SCRIPT_DIR/initialize.sh"



# 设置全局环境变量（仅OX版本）
set_global_env() {
    local code=${GLOBAL_CODE:-"ox"}
    local env=${GLOBAL_ENV:-"pre"}
    local ops_env=${GLOBAL_OPS_ENV:-"test"}
    local system=${GLOBAL_SYSTEM:-"system"}
    
    # 打印日志
    echo "========= 参数接收开始 ========="
    echo "Code: $code"
    echo "Environment: $env"
    echo "Ops Environment: $ops_env"
    echo "System: $system"
    echo "Deploy Version: $DEPLOY_VERSION"
    echo "========= 参数接收结束 ========="

    # 设置环境变量
    export GLOBAL_CODE="$code"
    export GLOBAL_ENV="$env"
    export GLOBAL_OPS_ENV="$ops_env"
    export GLOBAL_SYSTEM="$system"

    echo "已设置以下环境变量："
    echo "GLOBAL_CODE=$GLOBAL_CODE"
    echo "GLOBAL_ENV=$GLOBAL_ENV"
    echo "GLOBAL_OPS_ENV=$GLOBAL_OPS_ENV"
    echo "GLOBAL_SYSTEM=$GLOBAL_SYSTEM"
}


# 旧版本部署方式（仅OX）
deploy_legacy() {

    local install_script_url="https://static-api.pre-guance.houtai.io/guance/datakit/install.sh"
    echo "========= 开始旧版本部署 ========="
    
    # 初始化安装环境（停止进程、备份配置、清理定时任务）
    restore_installation_env "legacy"


    # 下载安装脚本
    echo "正在下载安装脚本：$INSTALL_SCRIPT_URL..."
    wget -q "$INSTALL_SCRIPT_URL" -O install.sh

    # 检查下载是否成功
    if [[ $? -ne 0 ]]; then
        echo "错误: 无法下载安装脚本，请检查网络连接或 URL 是否正确。"
        return 2
    fi

    echo "安装脚本下载完成。"

    # 修改脚本权限
    chmod +x install.sh

    # 执行安装脚本
    echo "正在执行安装脚本..."
    ./install.sh

    # 检查 install.sh 是否执行成功
    if [[ $? -eq 0 ]]; then
        echo "旧版本安装成功！"
        return 0
    else
        echo "旧版本安装失败，请检查日志了解详情。"
        return 3
    fi
}



# 还原安装环境函数
restore_installation_env() {
    local install_type="$1"
    
    # 设置默认安装类型
    if [[ -z "$install_type" ]]; then
        install_type="unknown"
    fi
    
    log_info "========= 开始还原安装环境 ========="
    
    # 检查datakit进程是否存在
    log_info "--- 停止datakit进程 ---"
    if pgrep -f "datakit" > /dev/null; then
        log_info "datakit进程已存在，进行停止datakit操作"

        # 停止datakit进程
        if systemctl stop datakit; then
            log_info "datakit进程已停止"
        else
            log_info "datakit进程停止失败，请手动停止"
        fi
    else
        log_info "datakit进程不存在，跳过停止操作"
    fi

    # 备份datakit配置文件
    log_info "备份datakit配置文件"
    if [ -d "/usr/local/datakit/conf.d" ]; then
        log_info "备份datakit配置文件"
        local backup_name="datakit_${install_type}_backup_$(date +%Y%m%d%H%M%S)"
        mv "/usr/local/datakit/conf.d" "/tmp/$backup_name"
        log_info "配置文件已备份到: /tmp/$backup_name"
    else
        log_info "datakit配置文件不存在，跳过备份"
    fi

    # 删除相关的定时任务
    log_info "--- 删除相关的定时任务 ---"
    local task_pattern=("app_init.sh" "app-init.sh" "datakit_auto_installer.sh")

    # 如果存在定时任务，则备份当前crontab
    if crontab -l 2>/dev/null; then
        local crontab_backup="/tmp/crontab_backup_$(date +%Y%m%d%H%M%S)"
        log_info "crontab_backup 路径: $crontab_backup"
        crontab -l > "$crontab_backup" 2>/dev/null
        log_info "crontab已备份到: $crontab_backup"
    else
        log_info "未发现相关定时任务，跳过备份"
    fi
    
    # 获取当前crontab内容
    local current_crontab=$(crontab -l 2>/dev/null)
    local has_deleted=false
    
    if [[ -n "$current_crontab" ]]; then
        # 构建过滤后的crontab内容
        local filtered_crontab=""
        
        while IFS= read -r line; do
            local should_keep=true
            
            # 跳过空行和注释行
            if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                if [[ -n "$filtered_crontab" ]]; then
                    filtered_crontab="$filtered_crontab"$'\n'"$line"
                else
                    filtered_crontab="$line"
                fi
                continue
            fi
            
            # 检查当前行是否匹配任何任务模式
            for task in "${task_pattern[@]}"; do
                if echo "$line" | grep -q "$task"; then
                    log_info "发现匹配的定时任务: $line"
                    should_keep=false
                    has_deleted=true
                    break
                fi
            done
            
            # 如果应该保留，添加到过滤后的内容
            if [[ "$should_keep" == "true" ]]; then
                if [[ -n "$filtered_crontab" ]]; then
                    filtered_crontab="$filtered_crontab"$'\n'"$line"
                else
                    filtered_crontab="$line"
                fi
            fi
        done <<< "$current_crontab"
        
        # 如果有删除操作，更新crontab
        if [[ "$has_deleted" == "true" ]]; then
            log_info "正在更新crontab..."
            if [[ -n "$filtered_crontab" ]]; then
                echo "$filtered_crontab" | crontab -
                log_info "定时任务删除完成，保留了 $(echo "$filtered_crontab" | grep -v '^[[:space:]]*#' | grep -v '^$' | wc -l) 个有效任务"
            else
                crontab -r 2>/dev/null
                log_info "定时任务删除完成，所有任务已清空"
            fi
        else
            log_info "未发现匹配的定时任务，无需删除"
        fi
    else
        log_info "当前没有定时任务，无需删除"
    fi
    
    log_info "========= 还原安装环境完成 ========="
}



# Dataway批量日志上报函数
dataway_log_batch() {
    local level="$1"
    local messages="$2"  # 多行消息，每行一条
    local release_id="${3:-}"
    
    # 检查是否有消息需要上报
    if [ -z "$messages" ]; then
        log_warning "没有消息需要上报到Dataway"
        return 0
    fi
    
    # 获取Dataway配置
    local dataway_host=$(echo $DATAWAY_URL | awk -F'?' '{print $1}')
    local dataway_token=$(echo $DATAWAY_URL | awk -F'token=' '{print $2}')
    
    if [ -z "$dataway_host" ] || [ -z "$dataway_token" ]; then
        log_warning "Dataway配置不完整，跳过批量上报"
        return 1
    fi
    
    # 获取批量大小配置
    local batch_size="${DATAWAY_LOG_BATCH_SIZE:-100}"
    local timeout="${DATAWAY_LOG_TIMEOUT:-30}"
    
    # 将消息按行分割并分批处理
    local message_array=()
    local line_count=0
    
    while IFS= read -r message; do
        if [ -n "$message" ]; then
            message_array+=("$message")
            line_count=$((line_count + 1))
        fi
    done <<< "$messages"
    
    if [ $line_count -eq 0 ]; then
        log_warning "没有有效消息需要上报"
        return 0
    fi
    
    log_info "开始分批上报 $line_count 条日志到Dataway (批次大小: $batch_size)"
    
    # 分批处理
    local batch_count=0
    local success_count=0
    local fail_count=0
    
    for ((i=0; i<line_count; i+=batch_size)); do
        batch_count=$((batch_count + 1))
        local end_index=$((i + batch_size - 1))
        if [ $end_index -ge $line_count ]; then
            end_index=$((line_count - 1))
        fi
        
        # 构建当前批次的数据
        local batch_data="["
        local first=true
        local current_batch_size=0
        
        for ((j=i; j<=end_index; j++)); do
            local message="${message_array[j]}"
            if [ -n "$message" ]; then
                # 转义JSON特殊字符
                local escaped_message=$(echo "$message" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
                
                if [ "$first" = true ]; then
                    first=false
                else
                    batch_data="$batch_data,"
                fi
                
                # 构建标签
                local tags="\"level\": \"$level\", \"host_ip\": \"$(get_global_state 'HOST_IP')\", \"env\": \"$(get_global_state 'ENV')\", \"workspace\": \"$(get_global_state 'WORKSPACE')\""
                if [ -n "$release_id" ]; then
                    tags="$tags, \"release_id\": \"$release_id\""
                fi
                
                batch_data="$batch_data"$(cat <<EOF
{
    "measurement": "datakit_host",
    "tags": {
        $tags
    },
    "time": $(date +%s%N),
    "fields": {
        "status": "$level",
        "message": "$escaped_message"
    }
}
EOF
)
                current_batch_size=$((current_batch_size + 1))
            fi
        done
        
        batch_data="$batch_data]"
        
        # 上报当前批次
        # log_info "上报批次 $batch_count: $current_batch_size 条消息"
        # # debug
        # echo "curl -s --max-time "$timeout" -X POST "$dataway_host/v1/write/logging?token=$dataway_token" \
        #     -H "Content-Type: application/json" \
        #     -d "$batch_data""


        if curl -s --max-time "$timeout" -X POST "$dataway_host/v1/write/logging?token=$dataway_token" \
            -H "Content-Type: application/json" \
            -d "$batch_data" >/dev/null 2>&1; then
            success_count=$((success_count + current_batch_size))
        else
            fail_count=$((fail_count + current_batch_size))
            log_warning "批次 $batch_count 上报失败: $current_batch_size 条消息"
        fi
        
        # 批次间短暂延迟，避免过于频繁的请求
        if [ $batch_count -lt $(((line_count + batch_size - 1) / batch_size)) ]; then
            sleep 0.1
        fi
    done
    
    # 输出上报结果统计
    if [ $fail_count -eq 0 ]; then
        log_info "批量日志上报完成: 成功 $success_count 条，失败 $fail_count 条"
        return 0
    else
        log_warning "批量日志上报部分失败: 成功 $success_count 条，失败 $fail_count 条"
        return 1
    fi
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

# 废弃：初始化运行时目录（已迁移到initialize.sh）
init_runtime_dirs() {
    log_warning "init_runtime_dirs 函数已废弃，请使用 initialize.sh 中的 init_runtime_environment"
    
    # 检查是否已加载initialize模块
    if command -v init_runtime_environment >/dev/null 2>&1; then
        local runtime_root="${1:-$RUNTIME_DIR}"
        local create_release="${2:-false}"
        init_runtime_environment "$create_release"
    else
        log_error "initialize模块未加载，无法使用新的runtime管理函数"
        return 1
    fi
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


# # 清理旧备份
# cleanup_old_backups() {
#     local backup_name="$1"
    
#     # 按修改时间排序，保留最新的MAX_BACKUP_COUNT个
#     local old_backups=$(find "$BACKUP_DIR" -name "${backup_name}_*" -type d -printf '%T@ %p\n' | sort -n | head -n -$MAX_BACKUP_COUNT | awk '{print $2}')
    
#     if [[ -n "$old_backups" ]]; then
#         log_info "清理旧备份..."
#         echo "$old_backups" | xargs rm -rf
#         log_info "旧备份清理完成"
#     fi
# }



# 清理AWS凭证
# cleanup_aws_credentials() {
#     if dir_exists ~/.aws; then
#         log_info "清理AWS凭证"
#         rm -rf ~/.aws
#     fi
# }


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
            if [ -n "$env" ]  && [ -n "$workspace_token" ]; then
                # 设置基础配置到全局状态
                local dataway_full_url="$dataway_url?token=$workspace_token"
                set_global_state "ENV" "$env"
                set_global_state "WORKSPACE" "$workspace"
                set_global_state "GLOBAL_TAGS" "$global_tags"
                set_global_state "WORKSPACE_TOKEN" "$workspace_token"
                set_global_state "DATAWAY_FULL_URL" "$dataway_full_url"
                set_global_state "RESPONSE_BODY" "$response_body"
                
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

# 卸载datakit
uninstall_datakit() {
    log_info "卸载Datakit"

    
    # 停止datakit服务
    systemctl stop datakit
    # 卸载datakit
    systemctl disable datakit
    # 删除datakit安装目录
}

# =============================================================================
# S3下载工具函数（从install_utils整合）
# =============================================================================

# # 使用curl下载私有S3文件（AWS签名v4）
# download_from_s3_with_curl() {
#     local bucket="$1"
#     local key="$2"
#     local local_path="$3"
    
#     log_info "使用curl从私有S3下载: $key"
    
#     # 检查AWS凭证
#     if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
#         handle_error "CONFIG_ERROR" "缺少AWS凭证，无法访问私有S3 bucket" "ERROR" "false"
#         return 1
#     fi
    
#     # 设置变量
#     local http_method="GET"
#     local canonical_uri="/$key"
#     local canonical_querystring=""
#     local timestamp=$(date -u +%Y%m%dT%H%M%SZ)
#     local date_stamp=$(date -u +%Y%m%d)
#     local region="${S3_REGION:-ap-southeast-1}"
#     local service="s3"
#     local host="$bucket.s3.$region.amazonaws.com"
    
#     # 生成负载哈希（GET请求为空）
#     local payload_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    
#     # 构建Canonical Headers - 确保格式完全正确
#     local canonical_headers="host:$host"$'\n'"x-amz-content-sha256:$payload_hash"$'\n'"x-amz-date:$timestamp"$'\n'
#     local signed_headers="host;x-amz-content-sha256;x-amz-date"
    
#     # 构建Canonical Request - 使用精确的换行符
#     local canonical_request="$http_method"$'\n'"$canonical_uri"$'\n'"$canonical_querystring"$'\n'"$canonical_headers"$'\n'"$signed_headers"$'\n'"$payload_hash"
    
#     # 计算Canonical Request哈希
#     local canonical_request_hash=$(printf "%s" "$canonical_request" | sha256sum | awk '{print $1}')
    
#     # 构建String to Sign
#     local credential_scope="$date_stamp/$region/$service/aws4_request"
#     local string_to_sign="AWS4-HMAC-SHA256"$'\n'"$timestamp"$'\n'"$credential_scope"$'\n'"$canonical_request_hash"
    
#     # 生成签名密钥 - 使用简单方法避免null byte问题
#     local kSecret="AWS4$S3_SECRET_KEY"
#     local temp_dir=$(mktemp -d)
#     # 注意：trap 在函数内部可能导致过早清理，改为手动清理
#     # 确保临时目录存在
#     if [ ! -d "$temp_dir" ]; then
#         handle_error "FILE_ERROR" "无法创建临时目录" "ERROR" "false"
#         return 1
#     fi
    
#     # 调试信息
#     log_info "临时目录: $temp_dir"
#     log_info "kSecret: ${kSecret:0:20}..."
#     log_info "S3_SECRET_KEY: ${S3_SECRET_KEY:0:10}..."
#     log_info "S3_ACCESS_KEY: ${S3_ACCESS_KEY:0:10}..."
    
#     # kDate
#     local kDate=$(echo -n "$date_stamp" | openssl dgst -sha256 -hmac "$kSecret" -binary)
    
#     # kRegion
#     local kRegion=$(echo -n "$region" | openssl dgst -sha256 -hmac "$kDate" -binary)
    
#     # kService
#     local kService=$(echo -n "$service" | openssl dgst -sha256 -hmac "$kRegion" -binary)
    
#     # kSigning
#     local kSigning=$(echo -n "aws4_request" | openssl dgst -sha256 -hmac "$kService" -binary)
    
#     # 生成签名
#     echo -n "$string_to_sign" > "$temp_dir/string_input"
#     local signature=$(openssl dgst -sha256 -hmac "$kSigning" "$temp_dir/string_input" | awk '{print $2}')
    
#     # 生成授权头
#     local authorization_header="AWS4-HMAC-SHA256 Credential=$S3_ACCESS_KEY/$credential_scope,SignedHeaders=$signed_headers,Signature=$signature"
    
#     # 构建完整URL
#     local s3_url="https://$host$canonical_uri"
    
#     # 使用curl下载
#     log_info "开始下载文件..."
#     if curl -L -o "$local_path" "$s3_url" \
#         -H "Authorization: $authorization_header" \
#         -H "x-amz-content-sha256: $payload_hash" \
#         -H "x-amz-date: $timestamp" \
#         --connect-timeout 30 --max-time "${DOWNLOAD_TIMEOUT:-300}"; then
        
#         # 检查文件大小，确保下载成功
#         local file_size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path" 2>/dev/null)
#         if [ "$file_size" -gt 0 ]; then
#             log_info "文件下载成功: $local_path (${file_size} bytes)"
#             return 0
#         else
#             handle_error "NETWORK_ERROR" "下载的文件为空: $key" "ERROR" "false"
#             return 1
#         fi
#     else
#         handle_error "NETWORK_ERROR" "下载失败: $key" "ERROR" "false"
#         # 清理临时目录
#         rm -rf "$temp_dir" 2>/dev/null || true
#         return 1
#     fi
    
#     # 清理临时目录
#     rm -rf "$temp_dir" 2>/dev/null || true
# }

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

# # 创建备份（重命名避免冲突）
# create_package_backup() {
#     local source_path="$1"
#     local backup_dir="$2"
    
#     if [ ! -e "$source_path" ]; then
#         log_info "源路径不存在，无需备份: $source_path"
#         return 0
#     fi
    
#     # 创建备份目录
#     mkdir -p "$backup_dir"
    
#     # 生成备份文件名
#     local timestamp=$(date +%Y%m%d_%H%M%S)
#     local basename=$(basename "$source_path")
#     local backup_path="$backup_dir/${basename}.backup.${timestamp}"
    
#     # 执行备份
#     if cp -r "$source_path" "$backup_path"; then
#         log_info "备份创建成功: $backup_path"
#         return 0
#     else
#         handle_error "BACKUP_ERROR" "备份创建失败: $source_path" "ERROR" "false"
#         return 1
#     fi
# }

# 清理临时文件（重命名避免冲突）
# cleanup_package_temp_files() {
#     local temp_dir="$1"
    
#     if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
#         log_info "清理临时文件: $temp_dir"
#         rm -rf "$temp_dir"
#         log_info "临时文件清理完成"
#     fi
# }

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
    

    
    # 更新配置文件
    safe_execute "echo '$json_data' | yj -jt > '$toml_file'" "更新配置文件" || return 1
    log_info "配置文件更新成功: $toml_file"
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


get_dataway_token_from_datakit_config() {
    # 读取datakit.conf 的toml 文件，根据.dataway.urls[0] 获取完整值
    local datakit_config_file="/usr/local/datakit/conf.d/datakit.conf"
    
    # 检查配置文件是否存在
    if [ ! -f "$datakit_config_file" ]; then
        log_warning "Datakit配置文件不存在: $datakit_config_file"
        handle_error "FILE_ERROR" "Datakit配置文件不存在: $datakit_config_file" "ERROR" "true"
    fi
    
    # 读取配置文件并提取dataway URL
    local dataway_url
    if ! dataway_url=$(read_toml_config "$datakit_config_file" | jq -r ".dataway.urls[0]" 2>/dev/null); then
        log_warning "读取dataway配置失败"
        return 1
    fi
   

    # 检查是否成功获取到URL
    if [ -z "$dataway_url" ] || [ "$dataway_url" = "null" ]; then
        log_warning "未找到dataway URL配置"
        return 1
    fi

    set_global_state "DATAWAY_FULL_URL" "$dataway_url"
    set_global_state "DATAWAY_TOKEN" "$(echo "$dataway_url" | awk -F'token=' '{print $2}')"

}

# dataway 统一读取runtime/log/current/release_id.log 日志文件上报
upload_log_to_dataway() {
    log_info "上传日志文件到dataway..."
    
    # 判断 /usr/local/datakit/conf.d/datakit.conf 是否存在
    if [ ! -f "/usr/local/datakit/conf.d/datakit.conf" ]; then
        handle_error "FILE_ERROR" "datakit.conf 文件不存在" "ERROR" "true"
    fi
    
    get_dataway_token_from_datakit_config
    

    log_info "DATAWAY_FULL_URL: $(get_global_state "DATAWAY_FULL_URL")"
    log_info "DATAWAY_TOKEN: $(get_global_state "DATAWAY_TOKEN")"

    # 判断 DATAWAY_FULL_URL 和 DATAWAY_TOKEN 是否存在
    if [ -z "$(get_global_state "DATAWAY_FULL_URL")" ] || [ -z "$(get_global_state "DATAWAY_TOKEN")" ]; then
        log_info "DATAWAY_FULL_URL 或 DATAWAY_TOKEN 未设置，查询datakit.conf 文件"
        get_dataway_token_from_datakit_config
    fi
    
    # 获取必要的全局状态变量
    local release_id=$(get_global_state "RELEASE_ID")
    local runtime_dir=$(get_global_state "RUNTIME_DIR")
    local runtime_release_dir=$(get_global_state "RUNTIME_RELEASE_DIR")

    
    
    # 构建日志文件路径
    local log_file="$runtime_release_dir/log/datakit_install.log"
    
    if [ ! -f "$log_file" ]; then
        handle_error "FILE_ERROR" "日志文件不存在: $log_file" "ERROR" "true"
    fi
    
    # 检查Dataway配置
    local dataway_url=$(get_global_state "DATAWAY_FULL_URL")
    if [ -z "$dataway_url" ]; then
        log_warning "DATAWAY_FULL_URL 未设置，跳过日志上报"
        return 1
    fi
    
    # 检查是否启用Dataway日志上报
    local enable_report="${ENABLE_DATAWAY_LOG_REPORT:-true}"
    if [ "$enable_report" != "true" ]; then
        log_info "Dataway日志上报已禁用，跳过上报"
        return 0
    fi
    
    log_info "开始读取日志文件: $log_file"
    
    # 读取日志文件内容
    local log_content=""
    local line_count=0
    
    if [ -f "$log_file" ]; then
        # 读取文件内容，过滤空行
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                log_content="$log_content$line"$'\n'
                line_count=$((line_count + 1))
            fi
        done < "$log_file"
    fi
    
    if [ -z "$log_content" ]; then
        log_warning "日志文件为空，跳过上报"
        return 1
    fi
    
    log_info "读取到 $line_count 行日志内容"
    
    # 检查是否有批量上报函数可用
    if command -v dataway_log_batch >/dev/null 2>&1; then
        log_info "使用批量上报功能"
        if dataway_log_batch "info" "$log_content" "$release_id"; then
            log_info "日志批量上报成功: $release_id"
            return 0
        else
            log_warning "日志批量上报失败: $release_id"
            return 1
        fi
    else
        log_info "批量上报函数不可用，使用单条上报"
        
        # 获取Dataway配置
        local dataway_host=$(echo "$dataway_url" | awk -F'?' '{print $1}')
        local dataway_token=$(echo "$dataway_url" | awk -F'token=' '{print $2}')
        
        if [ -z "$dataway_host" ] || [ -z "$dataway_token" ]; then
            log_warning "Dataway配置不完整，跳过上报"
            return 1
        fi
        
        # 逐行上报日志
        local success_count=0
        local fail_count=0
        local batch_size="${DATAWAY_LOG_BATCH_SIZE:-10}"
        local timeout="${DATAWAY_LOG_TIMEOUT:-30}"
        local current_batch=""
        local batch_count=0
        
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                current_batch="$current_batch$line"$'\n'
                batch_count=$((batch_count + 1))
                
                # 达到批次大小时上报
                if [ $batch_count -ge $batch_size ]; then
                    if upload_batch_to_dataway "$current_batch" "$dataway_host" "$dataway_token" "$timeout" "$release_id"; then
                        success_count=$((success_count + batch_count))
                        log_info "批次上报成功: $batch_count 条"
                    else
                        fail_count=$((fail_count + batch_count))
                        log_warning "批次上报失败: $batch_count 条"
                    fi
                    
                    # 重置批次
                    current_batch=""
                    batch_count=0
                    
                    # 批次间短暂延迟
                    sleep 0.1
                fi
            fi
        done <<< "$log_content"
        
        # 上报剩余内容
        if [ -n "$current_batch" ]; then
            if upload_batch_to_dataway "$current_batch" "$dataway_host" "$dataway_token" "$timeout" "$release_id"; then
                success_count=$((success_count + batch_count))
                log_info "最后批次上报成功: $batch_count 条"
            else
                fail_count=$((fail_count + batch_count))
                log_warning "最后批次上报失败: $batch_count 条"
            fi
        fi
        
        # 输出上报结果
        if [ $fail_count -eq 0 ]; then
            log_info "日志上报完成: 成功 $success_count 条，失败 $fail_count 条"
            return 0
        else
            log_warning "日志上报部分失败: 成功 $success_count 条，失败 $fail_count 条"
            return 1
        fi
    fi
}


