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

# 退出清理
cleanup_on_exit() {
    log_info "开始执行退出清理..."
    
    # 执行清理步骤
    local cleanup_steps=(
        "cleanup_temp_files:清理临时文件"
        "cleanup_log_files:清理日志文件"
    )
    
    local success_count=0
    local total_steps=${#cleanup_steps[@]}
    
    for step in "${cleanup_steps[@]}"; do
        local step_func="${step%%:*}"
        local step_desc="${step##*:}"
        
        if command -v "$step_func" >/dev/null 2>&1; then
            log_info "执行清理步骤: $step_desc"
            if "$step_func"; then
                log_success "清理步骤成功: $step_desc"
                success_count=$((success_count + 1))
            else
                log_warning "清理步骤失败: $step_desc"
            fi
        else
            log_debug "跳过不存在的清理函数: $step_func"
        fi
    done
}

# 清理临时文件
cleanup_temp_files() {
    log_info "清理临时文件..."
    
    local temp_patterns=(
        "datakit_install_*"
        "datakit_*"
        "install_*"
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
        log_success "临时文件清理完成，成功: $cleaned_count，失败: $error_count"
    fi
    
    return $((error_count == 0 ? 0 : 1))
}


# 清理日志文件
cleanup_log_files() {
    log_info "清理日志文件..."
    
    # 清理过期的日志文件
    local log_patterns=(
        "datakit_install.log.*"
        "datakit_*.log"
    )
    
    local cleaned_count=0
    local error_count=0
    
    for pattern in "${log_patterns[@]}"; do
        # 清理 /var/log 目录
        local var_log_files=$(find /var/log -name "$pattern" -type f -mtime +7 2>/dev/null)
        if [[ -n "$var_log_files" ]]; then
            if find /var/log -name "$pattern" -type f -mtime +7 -delete 2>/dev/null; then
                log_debug "清理成功: /var/log/$pattern"
                cleaned_count=$((cleaned_count + 1))
            else
                log_warning "清理失败: /var/log/$pattern"
                error_count=$((error_count + 1))
            fi
        fi
        
        # 清理 /tmp 目录
        local tmp_log_files=$(find /tmp -name "$pattern" -type f -mtime +7 2>/dev/null)
        if [[ -n "$tmp_log_files" ]]; then
            if find /tmp -name "$pattern" -type f -mtime +7 -delete 2>/dev/null; then
                log_debug "清理成功: /tmp/$pattern"
                cleaned_count=$((cleaned_count + 1))
            else
                log_warning "清理失败: /tmp/$pattern"
                error_count=$((error_count + 1))
            fi
        fi
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_success "日志文件清理完成，清理: $cleaned_count 个文件"
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
    
    # 根据严重程度记录日志
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
    
    # 如果是致命错误，立即退出
    if [[ "$severity" == "CRITICAL" ]]; then
        exit "$(get_error_code "$error_code")"
    fi
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