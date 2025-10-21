#!/bin/bash

#=================================================
# 错误处理标准化模块
#=================================================
# 功能: 统一错误处理、错误分类、错误恢复、错误追踪
#=================================================

#=================================================
# 错误代码定义
#=================================================

# 系统级错误代码
ERROR_CODES_NAMES=(
    "SUCCESS"           # 成功
    "GENERAL_ERROR"     # 一般错误
    "CONFIG_ERROR"      # 配置错误
    "NETWORK_ERROR"     # 网络错误
    "PERMISSION_ERROR"  # 权限错误
    "RESOURCE_ERROR"    # 资源错误
    "VALIDATION_ERROR"  # 验证错误
    "SERVICE_ERROR"     # 服务错误
    "TIMEOUT_ERROR"     # 超时错误
    "DEPENDENCY_ERROR"  # 依赖错误
    "FILE_ERROR"        # 文件错误
    "COMMAND_ERROR"     # 命令错误
    "API_ERROR"         # API错误
    "DATABASE_ERROR"    # 数据库错误
    "CRYPTO_ERROR"      # 加密错误
    "BACKUP_ERROR"      # 备份错误
    "ROLLBACK_ERROR"    # 回滚错误
    "CLEANUP_ERROR"     # 清理错误
)

# 对应的错误代码值
ERROR_CODES_VALUES=(
    0   # SUCCESS
    1   # GENERAL_ERROR
    2   # CONFIG_ERROR
    3   # NETWORK_ERROR
    4   # PERMISSION_ERROR
    5   # RESOURCE_ERROR
    6   # VALIDATION_ERROR
    7   # SERVICE_ERROR
    8   # TIMEOUT_ERROR
    9   # DEPENDENCY_ERROR
    10  # FILE_ERROR
    11  # COMMAND_ERROR
    12  # API_ERROR
    13  # DATABASE_ERROR
    14  # CRYPTO_ERROR
    15  # BACKUP_ERROR
    16  # ROLLBACK_ERROR
    17  # CLEANUP_ERROR
)

#=================================================
# 错误严重程度定义
#=================================================

# 错误严重程度名称
ERROR_SEVERITY_NAMES=(
    "CRITICAL"  # 致命错误，必须立即退出
    "ERROR"     # 严重错误，需要处理
    "WARNING"   # 警告，可以继续执行
    "INFO"      # 信息，不影响执行
)

# 对应的严重程度值（数值越小越严重）
ERROR_SEVERITY_VALUES=(
    1   # CRITICAL
    2   # ERROR
    3   # WARNING
    4   # INFO
)

#=================================================
# 错误代码查询函数
#=================================================

# 根据错误名称获取错误代码
# 参数: $1 - 错误名称
# 返回: 错误代码值，如果未找到则返回1（GENERAL_ERROR）
get_error_code() {
    local error_name="$1"
    
    # 遍历错误代码名称数组
    for i in "${!ERROR_CODES_NAMES[@]}"; do
        if [[ "${ERROR_CODES_NAMES[$i]}" == "$error_name" ]]; then
            echo "${ERROR_CODES_VALUES[$i]}"
            return 0
        fi
    done
    
    # 未找到时返回默认错误代码
    echo "1"  # GENERAL_ERROR
}

# 根据严重程度名称获取数值
# 参数: $1 - 严重程度名称
# 返回: 严重程度值，如果未找到则返回2（ERROR）
get_error_severity() {
    local severity_name="$1"
    
    # 遍历严重程度名称数组
    for i in "${!ERROR_SEVERITY_NAMES[@]}"; do
        if [[ "${ERROR_SEVERITY_NAMES[$i]}" == "$severity_name" ]]; then
            echo "${ERROR_SEVERITY_VALUES[$i]}"
            return 0
        fi
    done
    
    # 未找到时返回默认严重程度
    echo "2"  # ERROR
}


# 初始化错误处理器
init_error_handler() {
    # 设置信号处理，
    # INT 中断信号，一般用于用户主动中断程序执行
    # TERM 终止信号，一般用于系统强制终止程序执行
    trap 'handle_error_signal' INT TERM
    
    # 设置退出处理
    trap 'cleanup_on_exit' EXIT
}

# 信号处理
handle_error_signal() {
    local signal_name=""
    
    # 获取信号名称
    case "$1" in
        "INT") signal_name="用户中断 (Ctrl+C)" ;;
        "TERM") signal_name="系统终止" ;;
        *) signal_name="未知信号 ($1)" ;;
    esac
    
    log_warning "收到信号: $signal_name"
    
    # 记录错误
    record_error "SIGNAL_ERROR" "收到中断信号: $signal_name" "CRITICAL"
    
    # 执行清理
    cleanup_on_exit
    
    exit 1
}

backup_log_files_to_release() {
    log_info "备份日志文件到版本目录..."
    
    # 备份日志文件到版本目录
    CONFIG_CHANGED=$(get_global_state "CONFIG_CHANGED")
    RELEASE_ID=$(get_global_state "RELEASE_ID")
    RUNTIME_DIR=$(get_global_state "RUNTIME_DIR")
    RUNTIME_RELEASE_DIR=$(get_global_state "RUNTIME_RELEASE_DIR")

    if [ "$CONFIG_CHANGED" = "true" ]; then

        log_info "把当前的 RUNTIME_RELEASE_DIR 移动到 RUNTIME_DIR/releases/archive"
        if [ -d "$RUNTIME_DIR/releases/archive" ]; then
            cp -rf  $RUNTIME_RELEASE_DIR $RUNTIME_DIR/releases/archive 2>/dev/null
        else
            log_info "RUNTIME_DIR/releases/archive 不存在，跳过移动"
        fi
        log_info "release 归档完成"

    else
        log_info "配置未变更，无需归档release"
    fi
}


# 辅助函数：上传批次日志到Dataway
upload_batch_to_dataway() {
    local batch_content="$1"
    local dataway_host="$2"
    local dataway_token="$3"
    local timeout="$4"
    local release_id="$5"
    
    # 构建上报数据结构
    local batch_data="["
    local first_line=true
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            if [ "$first_line" = true ]; then
                first_line=false
            else
                batch_data="$batch_data,"
            fi
            
            # 解析JSON日志行，提取关键信息
            local timestamp=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null || echo "$(date -Iseconds)")
            local level=$(echo "$line" | jq -r '.level // "info"' 2>/dev/null || echo "info")
            local message=$(echo "$line" | jq -r '.message // empty' 2>/dev/null || echo "$line")
            local script_name=$(echo "$line" | jq -r '.script_name // empty' 2>/dev/null || echo "unknown")
            
            # 构建单条日志记录
            local log_record=$(cat <<EOF
{
    "measurement": "datakit_host",
    "tags": {
        "level": "$level",
        "host_ip": "$(get_global_state 'HOST_IP')",
        "env": "$(get_global_state 'ENV')",
        "workspace": "$(get_global_state 'WORKSPACE')",
        "script_name": "$script_name",
        "release_id": "$release_id"
    },
    "time": "$timestamp",
    "fields": {
        "status": "$level",
        "message": "$message"
    }
}
EOF
)
            batch_data="$batch_data$log_record"
        fi
    done <<< "$batch_content"
    
    batch_data="$batch_data]"
    
    # 上报到Dataway
    if curl -s --max-time "$timeout" -X POST "$dataway_host/v1/write/logging?token=$dataway_token" \
        -H "Content-Type: application/json" \
        -d "$batch_data" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}


# 退出清理
cleanup_on_exit() {
    log_info "开始执行退出清理..."
    
    # 获取当前脚本类型（用于清理函数参数）
    local script_type=$(get_global_state "SCRIPT_TYPE" 2>/dev/null || echo "")
    local max_releases=$(get_global_state "RUNTIME_MAX_RELEASES" 2>/dev/null || echo "10")
    
    # 执行清理步骤
    local success_count=0
    local total_steps=0
    
    
 
    if [ "$(get_global_state "command")" != "clean-install" ]; then
        total_steps=$((total_steps + 1))
        if command -v cleanup_log_files >/dev/null 2>&1; then
            log_info "执行清理步骤: 清理日志文件"
            if cleanup_log_files; then
                log_info "清理步骤成功: 清理日志文件"
                success_count=$((success_count + 1))
            else
                log_warning "清理步骤失败: 清理日志文件"
            fi
        else
            log_debug "跳过不存在的清理函数: cleanup_log_files"
        fi
        
        total_steps=$((total_steps + 1))
        if command -v cleanup_old_runtime_releases >/dev/null 2>&1; then
            log_info "执行清理步骤: 清理旧Runtime版本目录"
            if cleanup_old_runtime_releases "$max_releases" "$script_type"; then
                log_info "清理步骤成功: 清理旧Runtime版本目录"
                success_count=$((success_count + 1))
            else
                log_warning "清理步骤失败: 清理旧Runtime版本目录"
            fi
        else
            log_debug "跳过不存在的清理函数: cleanup_old_runtime_releases"
        fi

        total_steps=$((total_steps + 1))
        if command -v backup_log_files_to_release >/dev/null 2>&1; then
            log_info "执行清理步骤: 备份日志文件到版本目录"
            if backup_log_files_to_release; then
                log_info "清理步骤成功: 备份日志文件到版本目录"
                success_count=$((success_count + 1))
            else
                log_warning "清理步骤失败: 备份日志文件到版本目录"
            fi
        else
            log_debug "跳过不存在的清理函数: backup_log_files_to_release"
        fi
    else
        log_info "跳过清理日志文件"
    fi

    
    
    total_steps=$((total_steps + 1))
    if command -v cleanup_safe_delete_dir >/dev/null 2>&1; then
        log_info "执行清理步骤: 清理安全删除目录"
        if cleanup_safe_delete_dir; then
            log_info "清理步骤成功: 清理安全删除目录"
            success_count=$((success_count + 1))
        else
            log_warning "清理步骤失败: 清理安全删除目录"
        fi
    else
        log_debug "跳过不存在的清理函数: cleanup_safe_delete_dir"
    fi
    

    total_steps=$((total_steps + 1))
    if command -v upload_log_to_dataway >/dev/null 2>&1; then
        log_info "执行清理步骤: 上传日志到Dataway"
        if upload_log_to_dataway; then
            log_info "清理步骤成功: 上传日志到Dataway"
            success_count=$((success_count + 1))
        else
            log_warning "清理步骤失败: 上传日志到Dataway"
        fi
    else
        log_debug "跳过不存在的清理函数: upload_log_to_dataway"
    fi
    
    log_info "退出清理完成，成功步骤: $success_count/$total_steps"
}

# 清理临时文件
cleanup_temp_files() {
    log_info "清理临时文件..."
    
    local temp_patterns=(
        "datakit_install_*"
        "datakit_*"
        "install_*"
        "datakit"
    )
    
    local cleaned_count=0
    local error_count=0
    
    for pattern in "${temp_patterns[@]}"; do
        # 清理 /tmp 目录
        local tmp_files=$(find /tmp -name "$pattern" \( -type f -o -type d \) 2>/dev/null)
        if [[ -n "$tmp_files" ]]; then
            if find /tmp -name "$pattern" \( -type f -o -type d \) -delete 2>/dev/null; then
                log_debug "清理成功: /tmp/$pattern"
                cleaned_count=$((cleaned_count + 1))
            else
                log_warning "清理失败: /tmp/$pattern"
                error_count=$((error_count + 1))
            fi
        fi
        
        # 清理 /var/tmp 目录
        local var_tmp_files=$(find /var/tmp -name "$pattern" \( -type f -o -type d \) 2>/dev/null)
        if [[ -n "$var_tmp_files" ]]; then
            if find /var/tmp -name "$pattern" \( -type f -o -type d \) -delete 2>/dev/null; then
                log_debug "清理成功: /var/tmp/$pattern"
                cleaned_count=$((cleaned_count + 1))
            else
                log_warning "清理失败: /var/tmp/$pattern"
                error_count=$((error_count + 1))
            fi
        fi
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_info "临时文件清理完成，成功: $cleaned_count，失败: $error_count"
    fi
    
    return $((error_count == 0 ? 0 : 1))
}




# 清理日志目录
cleanup_log_files() {
    log_info "清理日志目录..."
    
    # 清理过期的日志目录
    local log_patterns=(
        "datakit_auto_installer_*"
    )
    
    local cleaned_count=0
    local error_count=0
    local retention_days="${LOG_RETENTION_DAYS:-0}"
    local runtime_dir=$(get_global_state "RUNTIME_DIR" 2>/dev/null || echo "/var/log/datakit/runtime")
    
    for pattern in "${log_patterns[@]}"; do
        # 清理 runtime/log/current 目录
        local current_log_dir="$runtime_dir/releases/current"
        log_info "清理 runtime/log/current 目录: $current_log_dir"
        if [[ -d "$current_log_dir" ]]; then
            local current_dirs=$(find "$current_log_dir" -name "$pattern" -type d -mtime +$retention_days 2>/dev/null)
            if [[ -n "$current_dirs" ]]; then
                if find "$current_log_dir" -name "$pattern" -type d -mtime +$retention_days -delete 2>/dev/null; then
                    log_info "清理成功: $current_log_dir/$pattern"
                    cleaned_count=$((cleaned_count + 1))
                else
                    log_warning "清理失败: $current_log_dir/$pattern"
                    error_count=$((error_count + 1))
                fi
            fi
        fi

        # 清理 runtime/log/archive 目录
        local archive_log_dir="$runtime_dir/releases/archive"
        if [[ -d "$archive_log_dir" ]]; then
            local archive_dirs=$(find "$archive_log_dir" -name "$pattern" -type d -mtime +$retention_days 2>/dev/null)
            if [[ -n "$archive_dirs" ]]; then
                if find "$archive_log_dir" -name "$pattern" -type d -mtime +$retention_days -delete 2>/dev/null; then
                    log_info "清理成功: $archive_log_dir/$pattern"
                    cleaned_count=$((cleaned_count + 1))
                else
                    log_warning "清理失败: $archive_log_dir/$pattern"
                    error_count=$((error_count + 1))
                fi
            fi
        fi
        
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_info "日志目录清理完成，清理: $cleaned_count 个目录"
    fi
    
    return $((error_count == 0 ? 0 : 1))
}


# 记录错误
record_error() {
    local error_code="$1"
    local error_message="$2"
    local severity="${3:-ERROR}"

    # 记录错误到日志
    local log_message="错误 [$error_code]: $error_message"
    
    # 根据严重程度记录日志，兼容处理
    case "$severity" in
        "CRITICAL"|"ERROR")
            log_error "$log_message"
            ;;
        "WARNING")
            log_warning "$log_message"
            ;;
        "INFO")
            log_info "$log_message"
            ;;
    esac
    

}

# 标准错误处理函数
handle_error() {
    local error_code="$1"
    local error_message="$2"
    local severity="${3:-ERROR}"
    local exit_on_error="${4:-false}"
    
    # 记录错误
    record_error "$error_code" "$error_message" "$severity"
    
    # 如果指定退出，则退出
    if [[ "$exit_on_error" == "true" ]]; then
        exit "$(get_error_code "$error_code")"
        # exit 0
    fi
    
    # 如果是致命错误，立即退出
    if [[ "$severity" == "CRITICAL" ]]; then
        exit "$(get_error_code "$error_code")"
        # exit 0
    fi

    # 根据严重程度决定返回值
    case "$severity" in
        "CRITICAL"|"ERROR")
            return "$(get_error_code "$error_code")"
            ;;
        "WARNING"|"INFO")
            return 0  # 警告和信息不返回错误码
            ;;
        *)
            return "$(get_error_code "$error_code")"
            ;;
    esac
}


# 标准化的die函数
# 临时兼容，不建议使用
die() {
    local message="$1"
    local error_code="${2:-GENERAL_ERROR}"
    
    # 记录错误
    record_error "$error_code" "$message" "CRITICAL"
    
    # 执行清理
    cleanup_on_exit
    
    # 退出
    exit "$(get_error_code "$error_code")"
}

# 标准化的错误检查函数
check_error() {
    local exit_code="$1"
    local error_message="$2"
    local error_code="${3:-COMMAND_ERROR}"
    
    if [[ $exit_code -ne 0 ]]; then
        handle_error "$error_code" "$error_message" "ERROR" "false"
        return $exit_code
    fi
    
    return 0
}

# =============================================================================
# Runtime清理函数（从initialize.sh移动过来）
# =============================================================================

# 初始化安全删除目录
init_safe_delete_dir() {
    if [ ! -d "/tmp/datakit" ]; then
        safe_execute "mkdir -p '/tmp/datakit'" "创建安全删除目录"
        safe_execute "chmod 700 '/tmp/datakit'" "设置安全删除目录权限"
        log_info "安全删除目录初始化完成: /tmp/datakit"
    fi
}

# 安全删除文件/目录
safe_delete() {
    local source_path="$1"
    local description="${2:-删除文件}"
    
    if [ ! -e "$source_path" ]; then
        log_info "源路径不存在，无需删除: $source_path"
        return 0
    fi
    
    # 确保安全删除目录存在
    init_safe_delete_dir
    
    # 生成目标路径（在安全删除目录中）
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$source_path")
    local target_path="/tmp/datakit/${basename}.deleted.${timestamp}"
    
    log_info "安全删除: $source_path -> $target_path"
    
    # 移动到安全删除目录
    if safe_execute "mv '$source_path' '$target_path'" "$description"; then
        log_info "文件已移动到安全删除目录: $target_path"
        return 0
    else
        record_error "DELETE_ERROR" "$description 失败" "WARNING"
        return 1
    fi
}

# 清理安全删除目录（真正的删除操作）
cleanup_safe_delete_dir() {
    local keep_hours="${1:-24}"  # 默认保留24小时
    
    if [ ! -d "/tmp/datakit" ]; then
        log_info "安全删除目录不存在，跳过清理"
        return 0
    fi
    
    log_info "清理安全删除目录: /tmp/datakit (保留 $keep_hours 小时)"
    
    local deleted_count=0
    local current_time=$(date +%s)
    

    cd /tmp/datakit

    # 清理过期目录，只保留时间最近的10个目录，其他目录删除
    local dirs_to_delete=$(find /tmp/datakit -name "*" -type d -mtime +0)
    log_info "/tmp/datakit删除过期目录: $dirs_to_delete"
    
    if [ -n "$dirs_to_delete" ]; then
        for dir in $dirs_to_delete; do
            log_info "删除过期目录: $dir"
            # 在/tmp/datakit 清理，相对可控
            if safe_execute "rm -rf '$dir'" "删除过期目录"; then
                deleted_count=$((deleted_count + 1))
            fi
        done
    fi
    log_info "安全删除目录清理完成，删除了 $deleted_count 个文件/目录"
    # 查找并删除超过保留时间的文件
    # while IFS= read -r -d '' file; do
    #     local file_time=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    #     local age_hours=$(( (current_time - file_time) / 3600 ))
        
    #     if [ "$age_hours" -gt "$keep_hours" ]; then
    #         log_info "删除过期文件: $(basename "$file") (已保留 $age_hours 小时)"
    #         if safe_execute "rm -rf '$file'" "删除过期文件"; then
    #             deleted_count=$((deleted_count + 1))
    #         fi
    #     fi
    # done < <(find "/tmp/datakit" -type f -o -type d -print0 2>/dev/null)
    
    # log_info "安全删除目录清理完成，删除了 $deleted_count 个文件/目录"
}

# 清理旧Runtime版本目录（基于文件数保留版本）
cleanup_old_runtime_releases() {
    local max_releases="${1:-$RUNTIME_MAX_RELEASES}"
    local script_type="${2:-}"
    
    log_info "清理旧Runtime版本目录（保留最新的 $max_releases 个版本）"
    
    if [ ! -d "$RUNTIME_DIR/releases/current" ]; then
        log_info "Runtime版本目录不存在，跳过清理"
        return 0
    fi
    
    # 确保安全删除目录存在
    if ! command -v init_safe_delete_dir >/dev/null 2>&1; then
        log_warning "安全删除函数不可用，跳过版本目录清理"
        return 1
    fi
    
    init_safe_delete_dir
    
    # 统计当前版本目录数量
    local current_releases=$(find "$RUNTIME_DIR/releases/current" -maxdepth 1 -type d -name "datakit_auto_installer_*" | wc -l)
    log_info "当前Runtime版本目录数量: $current_releases"
    log_info "最大保留版本目录数量: $max_releases"
    
    if [ "$current_releases" -gt "$max_releases" ]; then
        log_info "清理旧Runtime版本目录，保留最新的 $max_releases 个版本"
        
        # 查找需要删除的版本目录（按修改时间排序，保留最新的）
        local dirs_to_delete=$(find "$RUNTIME_DIR/releases/current" -maxdepth 1 -type d -name "datakit_auto_installer_*" -printf '%T@ %p\n' | sort -n | head -n $((current_releases - max_releases)) | awk '{print $2}' 2>/dev/null)
        
        local deleted_count=0
        if [ -n "$dirs_to_delete" ]; then
            for dir in $dirs_to_delete; do
            if [ -d "$dir" ]; then
                local dir_name=$(basename "$dir")
                log_info "安全删除旧Runtime版本目录: $dir_name"
                if safe_delete "$dir" "移动旧Runtime版本目录"; then
                    deleted_count=$((deleted_count + 1))
                fi
            fi
        done
        fi
        
        log_info "Runtime版本目录清理完成，删除了 $deleted_count 个旧版本目录"
    else
        log_info "Runtime版本目录数量 ($current_releases) 未超过限制 ($max_releases)，无需清理"
    fi

    cleanup_expired_logs_safe "$script_type"
}

# 清理过期日志文件（安全删除版本）
cleanup_expired_logs_safe() {
    local script_log_dir="$RUNTIME_LOG_CURRENT_DIR/"
    log_info "清理过期日志文件: $script_log_dir" 
    
    if [ ! -d "$script_log_dir" ]; then
        return 0
    fi
    
    # 确保安全删除目录存在
    if ! command -v init_safe_delete_dir >/dev/null 2>&1; then
        log_warning "安全删除函数不可用，跳过日志清理" "log_cleanup"
        return 1
    fi
    
    init_safe_delete_dir
    
    # 按修改时间排序，保留最新的N个文件
    local max_files="$LOG_MAX_FILES_PER_SCRIPT"
    local current_files=$(find "$script_log_dir" -name "*.log" -type f | wc -l)
    log_info "当前日志文件数量: $current_files" "log_cleanup"
    log_info "最大保留日志文件数量: $max_files" "log_cleanup"
    if [ "$current_files" -gt "$max_files" ]; then
        log_info "清理过期日志文件，保留最新的 $max_files 个文件" "log_cleanup"
        
        # 查找需要删除的文件（按修改时间排序，保留最新的）
        local files_to_delete=$(find "$script_log_dir" -name "*.log" -type f -printf '%T@ %p\n' | sort -n | head -n $((current_files - max_files)) | awk '{print $2}')
        
        local deleted_count=0
        for file in $files_to_delete; do
            if [ -f "$file" ]; then
                if safe_delete "$file" "清理过期日志文件"; then
                    deleted_count=$((deleted_count + 1))
                fi
            fi
        done
        
        log_info "日志清理完成，删除了 $deleted_count 个过期文件" "log_cleanup"
    else
        log_info "日志文件数量 ($current_files) 未超过限制 ($max_files)，无需清理" "log_cleanup"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "init")
            init_error_handler
            ;;
        "test")
            # 测试错误处理
            init_error_handler
            handle_error "NETWORK_ERROR" "网络连接失败" "ERROR"
            ;;
        *)
            echo "用法: $0 {init|test|stats|reset}"
            echo ""
            echo "命令说明:"
            echo "  init  - 初始化错误处理器"
            echo "  test  - 测试错误处理功能"
            echo "  stats - 显示错误统计"
            echo "  reset - 重置错误状态"
            ;;
    esac
fi 