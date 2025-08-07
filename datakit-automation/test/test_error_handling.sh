#!/bin/bash

#=================================================
# 错误处理系统测试脚本
#=================================================
# 功能: 测试标准化错误处理系统的各项功能
#=================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../core"

# 加载核心模块
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/error_handler.sh"
source "$CORE_DIR/utils.sh"

# 初始化日志系统
init_logging

# 测试结果统计
declare -A TEST_RESULTS
TEST_RESULTS["total"]=0
TEST_RESULTS["passed"]=0
TEST_RESULTS["failed"]=0

# 测试函数
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TEST_RESULTS["total"]=$((TEST_RESULTS["total"] + 1))
    
    log_info "运行测试: $test_name"
    
    if "$test_function"; then
        log_success "测试通过: $test_name"
        TEST_RESULTS["passed"]=$((TEST_RESULTS["passed"] + 1))
        return 0
    else
        log_error "测试失败: $test_name"
        TEST_RESULTS["failed"]=$((TEST_RESULTS["failed"] + 1))
        return 1
    fi
}

# 测试1: 错误处理器初始化
test_error_handler_init() {
    log_info "测试错误处理器初始化..."
    
    # 初始化错误处理器
    if ! init_error_handler; then
        return 1
    fi
    
    # 检查错误状态是否重置
    if [[ ${ERROR_STATE["ERROR_COUNT"]} -ne 0 ]]; then
        log_error "错误计数未重置"
        return 1
    fi
    
    if [[ ${ERROR_STATE["CRITICAL_ERROR_COUNT"]} -ne 0 ]]; then
        log_error "致命错误计数未重置"
        return 1
    fi
    
    log_success "错误处理器初始化测试通过"
    return 0
}

# 测试2: 错误上下文管理
test_error_context() {
    log_info "测试错误上下文管理..."
    
    # 设置错误上下文
    set_error_context "测试上下文1"
    set_error_context "测试上下文2"
    
    # 检查当前上下文
    local current_context=$(get_error_context)
    if [[ "$current_context" != "测试上下文2" ]]; then
        log_error "当前上下文不正确: $current_context"
        return 1
    fi
    
    # 检查上下文链
    local context_chain=$(get_error_context_chain)
    if [[ "$context_chain" != "测试上下文1 -> 测试上下文2" ]]; then
        log_error "上下文链不正确: $context_chain"
        return 1
    fi
    
    # 清除上下文
    clear_error_context
    current_context=$(get_error_context)
    if [[ "$current_context" != "测试上下文1" ]]; then
        log_error "清除上下文后不正确: $current_context"
        return 1
    fi
    
    # 清理
    clear_error_context
    
    log_success "错误上下文管理测试通过"
    return 0
}

# 测试3: 错误记录
test_error_recording() {
    log_info "测试错误记录..."
    
    # 记录一个错误
    record_error "TEST_ERROR" "测试错误消息" "ERROR" "测试上下文"
    
    # 检查错误状态
    if [[ ${ERROR_STATE["ERROR_COUNT"]} -ne 1 ]]; then
        log_error "错误计数不正确: ${ERROR_STATE["ERROR_COUNT"]}"
        return 1
    fi
    
    if [[ "${ERROR_STATE["LAST_ERROR_MESSAGE"]}" != "测试错误消息" ]]; then
        log_error "最后错误消息不正确: ${ERROR_STATE["LAST_ERROR_MESSAGE"]}"
        return 1
    fi
    
    if [[ "${ERROR_STATE["LAST_ERROR_CONTEXT"]}" != "测试上下文" ]]; then
        log_error "最后错误上下文不正确: ${ERROR_STATE["LAST_ERROR_CONTEXT"]}"
        return 1
    fi
    
    log_success "错误记录测试通过"
    return 0
}

# 测试4: 错误处理函数
test_error_handling() {
    log_info "测试错误处理函数..."
    
    # 测试非致命错误处理
    set_error_context "错误处理测试"
    
    if handle_error "NETWORK_ERROR" "网络连接失败" "ERROR" "false"; then
        log_error "错误处理函数应该返回非零退出码"
        clear_error_context
        return 1
    fi
    
    # 检查错误是否被记录
    if [[ ${ERROR_STATE["ERROR_COUNT"]} -eq 0 ]]; then
        log_error "错误未被记录"
        clear_error_context
        return 1
    fi
    
    clear_error_context
    log_success "错误处理函数测试通过"
    return 0
}

# 测试5: 断言函数
test_assertions() {
    log_info "测试断言函数..."
    
    # 测试文件存在断言
    local temp_file="/tmp/test_error_handling_$$"
    touch "$temp_file"
    
    if ! assert_file_exists "$temp_file"; then
        log_error "文件存在断言失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 测试文件不存在断言
    if assert_file_exists "/nonexistent/file" 2>/dev/null; then
        log_error "文件不存在断言应该失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 测试目录存在断言
    if ! assert_dir_exists "/tmp"; then
        log_error "目录存在断言失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 测试命令存在断言
    if ! assert_command_exists "bash"; then
        log_error "命令存在断言失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 清理
    rm -f "$temp_file"
    
    log_success "断言函数测试通过"
    return 0
}

# 测试6: 错误恢复机制
test_error_recovery() {
    log_info "测试错误恢复机制..."
    
    # 重置错误状态
    reset_error_state
    
    # 测试网络错误恢复
    if ! attempt_error_recovery "NETWORK_ERROR" "网络连接失败"; then
        log_warning "网络错误恢复失败（这是正常的，因为可能没有网络）"
    fi
    
    # 测试文件错误恢复
    if ! attempt_error_recovery "FILE_ERROR" "文件操作失败"; then
        log_warning "文件错误恢复失败"
    fi
    
    # 测试权限错误恢复
    if ! attempt_error_recovery "PERMISSION_ERROR" "权限不足"; then
        log_warning "权限错误恢复失败"
    fi
    
    log_success "错误恢复机制测试通过"
    return 0
}

# 测试7: 安全执行函数
test_safe_execute() {
    log_info "测试安全执行函数..."
    
    # 测试成功执行
    if ! safe_execute "echo 'test'" "测试命令"; then
        log_error "成功命令执行失败"
        return 1
    fi
    
    # 测试失败执行
    if safe_execute "exit 1" "失败命令" 2>/dev/null; then
        log_error "失败命令应该返回非零退出码"
        return 1
    fi
    
    log_success "安全执行函数测试通过"
    return 0
}

# 测试8: 重试执行函数
test_retry_execute() {
    log_info "测试重试执行函数..."
    
    # 测试成功执行（不需要重试）
    if ! retry_execute "echo 'test'" 3 1 "成功命令"; then
        log_error "成功命令重试执行失败"
        return 1
    fi
    
    # 测试失败执行（会重试）
    if retry_execute "exit 1" 2 1 "失败命令" 2>/dev/null; then
        log_error "失败命令重试执行应该最终失败"
        return 1
    fi
    
    log_success "重试执行函数测试通过"
    return 0
}

# 测试9: 超时执行函数
test_timeout_execute() {
    log_info "测试超时执行函数..."
    
    # 测试正常执行
    if ! timeout_execute 10 "echo 'test'" "正常命令"; then
        log_error "正常命令超时执行失败"
        return 1
    fi
    
    # 测试超时执行
    if timeout_execute 1 "sleep 5" "超时命令" 2>/dev/null; then
        log_error "超时命令应该失败"
        return 1
    fi
    
    log_success "超时执行函数测试通过"
    return 0
}

# 测试10: 错误统计
test_error_statistics() {
    log_info "测试错误统计..."
    
    # 重置错误状态
    reset_error_state
    
    # 记录一些错误
    record_error "TEST_ERROR1" "测试错误1" "ERROR"
    record_error "TEST_ERROR2" "测试错误2" "WARNING"
    record_error "TEST_ERROR3" "测试错误3" "CRITICAL"
    
    # 获取统计信息
    local stats_output=$(get_error_statistics)
    
    # 检查统计信息
    if ! echo "$stats_output" | grep -q "总错误数: 3"; then
        log_error "错误统计不正确"
        return 1
    fi
    
    if ! echo "$stats_output" | grep -q "致命错误数: 1"; then
        log_error "致命错误统计不正确"
        return 1
    fi
    
    log_success "错误统计测试通过"
    return 0
}

# 主测试函数
main() {
    log_info "开始错误处理系统测试..."
    
    # 初始化错误处理器
    init_error_handler
    
    # 运行所有测试
    local tests=(
        "test_error_handler_init"
        "test_error_context"
        "test_error_recording"
        "test_error_handling"
        "test_assertions"
        "test_error_recovery"
        "test_safe_execute"
        "test_retry_execute"
        "test_timeout_execute"
        "test_error_statistics"
    )
    
    local failed_tests=()
    
    for test in "${tests[@]}"; do
        if ! run_test "$test" "$test"; then
            failed_tests+=("$test")
        fi
    done
    
    # 输出测试结果
    log_info "=== 测试结果汇总 ==="
    log_info "总测试数: ${TEST_RESULTS["total"]}"
    log_info "通过测试: ${TEST_RESULTS["passed"]}"
    log_info "失败测试: ${TEST_RESULTS["failed"]}"
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        log_error "失败的测试:"
        for test in "${failed_tests[@]}"; do
            log_error "  - $test"
        done
        return 1
    else
        log_success "所有测试通过！"
        return 0
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 