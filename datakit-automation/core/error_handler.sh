#!/bin/bash

#=================================================
# 错误处理标准化模块
#=================================================
# 功能: 统一错误处理、错误分类、错误恢复、错误追踪
#=================================================


# 获取脚本所在目录
CORE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 错误代码定义
declare -A ERROR_CODES
ERROR_CODES["SUCCESS"]=0
ERROR_CODES["GENERAL_ERROR"]=1
ERROR_CODES["CONFIG_ERROR"]=2
ERROR_CODES["NETWORK_ERROR"]=3
ERROR_CODES["PERMISSION_ERROR"]=4
ERROR_CODES["RESOURCE_ERROR"]=5
ERROR_CODES["VALIDATION_ERROR"]=6
ERROR_CODES["SERVICE_ERROR"]=7
ERROR_CODES["TIMEOUT_ERROR"]=8
ERROR_CODES["DEPENDENCY_ERROR"]=9
ERROR_CODES["FILE_ERROR"]=10
ERROR_CODES["COMMAND_ERROR"]=11
ERROR_CODES["API_ERROR"]=12
ERROR_CODES["DATABASE_ERROR"]=13
ERROR_CODES["CRYPTO_ERROR"]=14
ERROR_CODES["BACKUP_ERROR"]=15
ERROR_CODES["ROLLBACK_ERROR"]=16
ERROR_CODES["CLEANUP_ERROR"]=17

# 错误严重程度定义
declare -A ERROR_SEVERITY
ERROR_SEVERITY["CRITICAL"]=1    # 致命错误，必须立即退出
ERROR_SEVERITY["ERROR"]=2       # 严重错误，需要处理
ERROR_SEVERITY["WARNING"]=3     # 警告，可以继续执行
ERROR_SEVERITY["INFO"]=4        # 信息，不影响执行


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
        "/tmp/datakit_install_*"
        "/tmp/datakit_*"
        "/tmp/install_*"
        "/var/tmp/datakit_*"
    )
    
    local cleaned_count=0
    local error_count=0
    
    for pattern in "${temp_patterns[@]}"; do
        # 使用 find 命令更安全地清理文件
        local pattern_name=$(basename "$pattern")
        if find /tmp /var/tmp -name "$pattern_name" \( -type f -o -type d \) 2>/dev/null | head -1 | grep -q .; then
            if find /tmp /var/tmp -name "$pattern_name" \( -type f -o -type d \) -delete 2>/dev/null; then
                log_debug "清理成功: $pattern"
                cleaned_count=$((cleaned_count + 1))
            else
                log_warning "清理失败: $pattern"
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
        "/var/log/datakit_install.log.*"
        "/tmp/datakit_*.log"
    )
    
    local cleaned_count=0
    local error_count=0
    
    for pattern in "${log_patterns[@]}"; do
        if [[ -f "$pattern" ]] || [[ -d "$(dirname "$pattern")" ]]; then
            # 检查文件年龄，只删除超过7天的日志
            if find "$(dirname "$pattern")" -name "$(basename "$pattern")" -type f -mtime +7 -delete 2>/dev/null; then
                cleaned_count=$((cleaned_count + 1))
            else
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
        exit "${ERROR_CODES[$error_code]:-1}"
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
        exit "${ERROR_CODES[$error_code]:-1}"
    fi
    
    return "${ERROR_CODES[$error_code]:-1}"
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
    exit "${ERROR_CODES[$error_code]:-1}"
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