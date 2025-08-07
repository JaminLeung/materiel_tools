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

# 全局错误状态
declare -A ERROR_STATE
ERROR_STATE["LAST_ERROR_CODE"]=0
ERROR_STATE["LAST_ERROR_MESSAGE"]=""
ERROR_STATE["LAST_ERROR_CONTEXT"]=""
ERROR_STATE["ERROR_COUNT"]=0
ERROR_STATE["CRITICAL_ERROR_COUNT"]=0
ERROR_STATE["RECOVERY_ATTEMPTS"]=0
ERROR_STATE["MAX_RECOVERY_ATTEMPTS"]=3

# 错误上下文栈
declare -a ERROR_CONTEXT_STACK

# 错误恢复函数列表
declare -a ERROR_RECOVERY_FUNCTIONS

# 初始化错误处理器
init_error_handler() {
    # 重置错误状态
    ERROR_STATE["LAST_ERROR_CODE"]=0
    ERROR_STATE["LAST_ERROR_MESSAGE"]=""
    ERROR_STATE["LAST_ERROR_CONTEXT"]=""
    ERROR_STATE["ERROR_COUNT"]=0
    ERROR_STATE["CRITICAL_ERROR_COUNT"]=0
    ERROR_STATE["RECOVERY_ATTEMPTS"]=0
    
    # 清空上下文栈
    ERROR_CONTEXT_STACK=()
    
    # 清空恢复函数列表
    ERROR_RECOVERY_FUNCTIONS=()
    
    # 设置信号处理
    trap 'handle_signal' INT TERM
    
    # 设置退出处理
    trap 'cleanup_on_exit' EXIT
}

# 设置错误上下文
set_error_context() {
    local context="$1"
    ERROR_CONTEXT_STACK+=("$context")
    ERROR_STATE["LAST_ERROR_CONTEXT"]="$context"
}

# 清除错误上下文
clear_error_context() {
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        unset ERROR_CONTEXT_STACK[${#ERROR_CONTEXT_STACK[@]}-1]
    fi
}

# 获取当前错误上下文
get_error_context() {
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        echo "${ERROR_CONTEXT_STACK[-1]}"
    else
        echo ""
    fi
}

# 获取完整错误上下文链
get_error_context_chain() {
    local chain=""
    for context in "${ERROR_CONTEXT_STACK[@]}"; do
        if [[ -n "$chain" ]]; then
            chain="$chain -> $context"
        else
            chain="$context"
        fi
    done
    echo "$chain"
}

# 记录错误
record_error() {
    local error_code="$1"
    local error_message="$2"
    local severity="${3:-ERROR}"
    local context="${4:-$(get_error_context)}"
    
    # 更新错误状态
    ERROR_STATE["LAST_ERROR_CODE"]="${ERROR_CODES[$error_code]:-1}"
    ERROR_STATE["LAST_ERROR_MESSAGE"]="$error_message"
    ERROR_STATE["LAST_ERROR_CONTEXT"]="$context"
    ERROR_STATE["ERROR_COUNT"]=$((ERROR_STATE["ERROR_COUNT"] + 1))
    
    # 统计严重错误
    if [[ "$severity" == "CRITICAL" ]]; then
        ERROR_STATE["CRITICAL_ERROR_COUNT"]=$((ERROR_STATE["CRITICAL_ERROR_COUNT"] + 1))
    fi
    
    # 记录错误到日志
    local context_chain=$(get_error_context_chain)
    local log_message="错误 [$error_code]: $error_message"
    if [[ -n "$context_chain" ]]; then
        log_message="$log_message (上下文: $context_chain)"
    fi
    
    case "$severity" in
        "CRITICAL")
            log_error "$log_message"
            ;;
        "ERROR")
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
    
    # 尝试错误恢复
    if ! attempt_error_recovery "$error_code" "$error_message"; then
        # 恢复失败，记录失败信息
        record_error "RECOVERY_ERROR" "错误恢复失败: $error_message" "ERROR"
    fi
    
    # 如果指定退出，则退出
    if [[ "$exit_on_error" == "true" ]]; then
        exit "${ERROR_CODES[$error_code]:-1}"
    fi
    
    return "${ERROR_CODES[$error_code]:-1}"
}

# 尝试错误恢复
attempt_error_recovery() {
    local error_code="$1"
    local error_message="$2"
    
    # 检查是否超过最大恢复尝试次数
    if [[ ${ERROR_STATE["RECOVERY_ATTEMPTS"]} -ge ${ERROR_STATE["MAX_RECOVERY_ATTEMPTS"]} ]]; then
        log_warning "已达到最大错误恢复尝试次数 (${ERROR_STATE["MAX_RECOVERY_ATTEMPTS"]})"
        return 1
    fi
    
    # 增加恢复尝试次数
    ERROR_STATE["RECOVERY_ATTEMPTS"]=$((ERROR_STATE["RECOVERY_ATTEMPTS"] + 1))
    
    log_info "尝试错误恢复 (尝试 ${ERROR_STATE["RECOVERY_ATTEMPTS"]}/${ERROR_STATE["MAX_RECOVERY_ATTEMPTS"]})"
    
    # 根据错误类型执行相应的恢复策略
    case "$error_code" in
        "NETWORK_ERROR")
            recover_network_error "$error_message"
            ;;
        "SERVICE_ERROR")
            recover_service_error "$error_message"
            ;;
        "FILE_ERROR")
            recover_file_error "$error_message"
            ;;
        "PERMISSION_ERROR")
            recover_permission_error "$error_message"
            ;;
        "RESOURCE_ERROR")
            recover_resource_error "$error_message"
            ;;
        *)
            # 通用恢复策略
            recover_general_error "$error_message"
            ;;
    esac
    
    local recovery_result=$?
    
    if [[ $recovery_result -eq 0 ]]; then
        log_success "错误恢复成功"
        ERROR_STATE["RECOVERY_ATTEMPTS"]=0  # 重置恢复尝试次数
        return 0
    else
        log_warning "错误恢复失败"
        return 1
    fi
}

# 网络错误恢复
recover_network_error() {
    local error_message="$1"
    
    log_info "执行网络错误恢复策略..."
    
    # 等待一段时间后重试
    sleep 5
    
    # 检查网络连通性
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_info "网络连通性检查通过"
        return 0
    else
        log_warning "网络连通性检查失败"
        return 1
    fi
}

# 服务错误恢复
recover_service_error() {
    local error_message="$1"
    
    log_info "执行服务错误恢复策略..."
    
    # 尝试重启服务
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl restart datakit >/dev/null 2>&1; then
            log_info "Datakit服务重启成功"
            return 0
        fi
    fi
    
    return 1
}

# 文件错误恢复
recover_file_error() {
    local error_message="$1"
    
    log_info "执行文件错误恢复策略..."
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -gt 1048576 ]]; then  # 1GB
        log_info "磁盘空间充足"
        return 0
    else
        log_warning "磁盘空间不足"
        return 1
    fi
}

# 权限错误恢复
recover_permission_error() {
    local error_message="$1"
    
    log_info "执行权限错误恢复策略..."
    
    # 检查是否为root用户
    if [[ $EUID -eq 0 ]]; then
        log_info "当前为root用户，权限充足"
        return 0
    else
        log_warning "需要root权限"
        return 1
    fi
}

# 资源错误恢复
recover_resource_error() {
    local error_message="$1"
    
    log_info "执行资源错误恢复策略..."
    
    # 检查内存使用情况
    local available_memory=$(free -k | awk 'NR==2 {print $7}')
    if [[ $available_memory -gt 524288 ]]; then  # 512MB
        log_info "内存资源充足"
        return 0
    else
        log_warning "内存资源不足"
        return 1
    fi
}

# 通用错误恢复
recover_general_error() {
    local error_message="$1"
    
    log_info "执行通用错误恢复策略..."
    
    # 等待一段时间
    sleep 3
    
    # 清理临时文件
    cleanup_temp_files
    
    return 0
}

# 添加错误恢复函数
add_error_recovery_function() {
    local recovery_function="$1"
    ERROR_RECOVERY_FUNCTIONS+=("$recovery_function")
}

# 执行所有错误恢复函数
execute_recovery_functions() {
    local error_code="$1"
    local error_message="$2"
    
    for recovery_func in "${ERROR_RECOVERY_FUNCTIONS[@]}"; do
        if command -v "$recovery_func" >/dev/null 2>&1; then
            log_info "执行恢复函数: $recovery_func"
            if "$recovery_func" "$error_code" "$error_message"; then
                log_success "恢复函数 $recovery_func 执行成功"
            else
                log_warning "恢复函数 $recovery_func 执行失败"
            fi
        fi
    done
}

# 信号处理
handle_signal() {
    local signal="$1"
    log_warning "收到信号: $signal"
    
    # 记录错误
    record_error "SIGNAL_ERROR" "收到中断信号: $signal" "CRITICAL"
    
    # 执行清理
    cleanup_on_exit
    
    exit 1
}

# 退出清理
cleanup_on_exit() {
    local exit_code="${ERROR_STATE["LAST_ERROR_CODE"]}"
    
    log_info "执行退出清理..."
    
    # 执行所有恢复函数
    execute_recovery_functions "EXIT" "脚本退出"
    
    # 清理临时文件
    cleanup_temp_files
    
    # 记录退出信息
    if [[ $exit_code -ne 0 ]]; then
        log_error "脚本异常退出，错误代码: $exit_code"
    else
        log_success "脚本正常退出"
    fi
}

# 清理临时文件
cleanup_temp_files() {
    # 清理临时目录
    if [[ -d "/tmp/datakit_install_*" ]]; then
        rm -rf /tmp/datakit_install_* 2>/dev/null || true
    fi
    
    # 清理锁文件
    if [[ -f "/tmp/datakit_install.lock" ]]; then
        rm -f /tmp/datakit_install.lock 2>/dev/null || true
    fi
}

# 获取错误统计
get_error_statistics() {
    echo "=== 错误统计 ==="
    echo "总错误数: ${ERROR_STATE["ERROR_COUNT"]}"
    echo "致命错误数: ${ERROR_STATE["CRITICAL_ERROR_COUNT"]}"
    echo "恢复尝试次数: ${ERROR_STATE["RECOVERY_ATTEMPTS"]}"
    echo "最后错误代码: ${ERROR_STATE["LAST_ERROR_CODE"]}"
    echo "最后错误信息: ${ERROR_STATE["LAST_ERROR_MESSAGE"]}"
    echo "最后错误上下文: ${ERROR_STATE["LAST_ERROR_CONTEXT"]}"
}

# 重置错误状态
reset_error_state() {
    ERROR_STATE["LAST_ERROR_CODE"]=0
    ERROR_STATE["LAST_ERROR_MESSAGE"]=""
    ERROR_STATE["LAST_ERROR_CONTEXT"]=""
    ERROR_STATE["ERROR_COUNT"]=0
    ERROR_STATE["CRITICAL_ERROR_COUNT"]=0
    ERROR_STATE["RECOVERY_ATTEMPTS"]=0
    ERROR_CONTEXT_STACK=()
}

# 标准化的die函数
die() {
    local message="$1"
    local error_code="${2:-GENERAL_ERROR}"
    local context="${3:-$(get_error_context)}"
    
    # 记录错误
    record_error "$error_code" "$message" "CRITICAL" "$context"
    
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
    local context="${4:-$(get_error_context)}"
    
    if [[ $exit_code -ne 0 ]]; then
        handle_error "$error_code" "$error_message" "ERROR" "false"
        return $exit_code
    fi
    
    return 0
}

# 标准化的断言函数
assert() {
    local condition="$1"
    local error_message="$2"
    local error_code="${3:-VALIDATION_ERROR}"
    local context="${4:-$(get_error_context)}"
    
    if ! eval "$condition"; then
        handle_error "$error_code" "$error_message" "ERROR" "true"
    fi
}

# 标准化的文件检查函数
assert_file_exists() {
    local file_path="$1"
    local error_message="${2:-文件不存在: $file_path}"
    
    assert "[[ -f '$file_path' ]]" "$error_message" "FILE_ERROR"
}

# 标准化的目录检查函数
assert_dir_exists() {
    local dir_path="$1"
    local error_message="${2:-目录不存在: $dir_path}"
    
    assert "[[ -d '$dir_path' ]]" "$error_message" "FILE_ERROR"
}

# 标准化的命令检查函数
assert_command_exists() {
    local command_name="$1"
    local error_message="${2:-命令不存在: $command_name}"
    
    assert "command -v '$command_name' >/dev/null 2>&1" "$error_message" "COMMAND_ERROR"
}

# 标准化的权限检查函数
assert_root_permission() {
    local error_message="${1:-需要root权限}"
    
    assert "[[ \$EUID -eq 0 ]]" "$error_message" "PERMISSION_ERROR"
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
            set_error_context "测试上下文"
            handle_error "NETWORK_ERROR" "网络连接失败" "ERROR"
            get_error_statistics
            ;;
        "stats")
            get_error_statistics
            ;;
        "reset")
            reset_error_state
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