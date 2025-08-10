#!/bin/bash

#=================================================
# 错误处理模块单元测试
#=================================================
# 功能: 测试error_handler.sh中的所有函数
#=================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

# 检查核心文件是否存在
if [[ ! -f "$CORE_DIR/logging.sh" ]]; then
    echo "错误: 找不到 logging.sh 文件: $CORE_DIR/logging.sh"
    exit 1
fi

if [[ ! -f "$CORE_DIR/error_handler.sh" ]]; then
    echo "错误: 找不到 error_handler.sh 文件: $CORE_DIR/error_handler.sh"
    exit 1
fi

# 加载核心模块
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/error_handler.sh"

# 初始化日志系统
init_logging

# 测试结果统计（使用普通变量而不是关联数组，提高兼容性）
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0

# 测试辅助函数
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TEST_TOTAL=$((TEST_TOTAL + 1))
    
    log_info "运行测试: $test_name"
    
    if "$test_function"; then
        log_info "测试通过: $test_name"
        TEST_PASSED=$((TEST_PASSED + 1))
        return 0
    else
        log_error "测试失败: $test_name"
        TEST_FAILED=$((TEST_FAILED + 1))
        return 1
    fi
}

# 错误代码定义
test_error_codes_definition() {
    log_info "测试错误代码定义..."
    
    # 检查错误代码数组是否定义
    if [[ ${#ERROR_CODES_NAMES[@]} -eq 0 ]]; then
        log_error "错误代码数组未定义"
        return 1
    fi
    
    # 检查关键错误代码是否存在
    local required_codes=("SUCCESS" "GENERAL_ERROR" "CONFIG_ERROR" "NETWORK_ERROR")
    for code in "${required_codes[@]}"; do
        if [[ -z "$(get_error_code "$code")" ]]; then
            log_error "缺少错误代码: $code"
            return 1
        fi
    done
    
    # 检查 SUCCESS代码是否为0
    if [[ "$(get_error_code "SUCCESS")" -ne 0 ]]; then
        log_error "SUCCESS错误代码应该为0"
        return 1
    fi
    
    log_info "错误代码定义测试通过"
    return 0
}

# 测试2: 错误严重程度定义
test_error_severity_definition() {
    log_info "测试错误严重程度定义..."
    
    # 检查错误严重程度数组是否定义
    if [[ ${#ERROR_SEVERITY_NAMES[@]} -eq 0 ]]; then
        log_error "错误严重程度数组未定义"
        return 1
    fi
    
    # 检查关键严重程度是否存在
    local required_severities=("CRITICAL" "ERROR" "WARNING" "INFO")
    for severity in "${required_severities[@]}"; do
        if [[ -z "$(get_error_severity "$severity")" ]]; then
            log_error "缺少错误严重程度: $severity"
            return 1
        fi
    done
    
    # 检查严重程度数值是否正确
    if [[ "$(get_error_severity "CRITICAL")" -ne 1 ]]; then
        log_error "CRITICAL严重程度应该为1"
        return 1
    fi
    
    if [[ "$(get_error_severity "INFO")" -ne 4 ]]; then
        log_error "INFO严重程度应该为4"
        return 1
    fi
    
    log_info "错误严重程度定义测试通过"
    return 0
}

# 测试3: 错误处理器初始化
test_error_handler_init() {
    log_info "测试错误处理器初始化..."
    
    # 初始化错误处理器
    if ! init_error_handler; then
        log_error "错误处理器初始化失败"
        return 1
    fi
    
    log_info "错误处理器初始化测试通过"
    return 0
}

# 测试4: 记录错误函数
test_record_error() {
    log_info "测试记录错误函数..."
    
    # 测试记录普通错误
    if ! record_error "TEST_ERROR" "测试错误消息" "ERROR"; then
        log_error "记录普通错误失败"
        return 1
    fi
    
    # 测试记录警告
    if ! record_error "TEST_WARNING" "测试警告消息" "WARNING"; then
        log_error "记录警告失败"
        return 1
    fi
    
    # 测试记录信息
    if ! record_error "TEST_INFO" "测试信息消息" "INFO"; then
        log_error "记录信息失败"
        return 1
    fi
    
    log_info "记录错误函数测试通过"
    return 0
}

# 测试5: 标准错误处理函数
test_handle_error() {
    log_info "测试标准错误处理函数..."
    
    # 测试非致命错误处理
    if handle_error "NETWORK_ERROR" "网络连接失败" "ERROR" "false"; then
        log_error "错误处理函数应该返回非零退出码"
        return 1
    fi
    
    # 测试警告处理
    if ! handle_error "CONFIG_ERROR" "配置警告" "WARNING" "false"; then
        log_error "警告处理应该成功"
        return 1
    fi
    
    log_info "标准错误处理函数测试通过"
    return 0
}

# 测试6: die函数
test_die_function() {
    log_info "测试die函数..."
    
    # 创建一个临时脚本来测试die函数
    local temp_script="/tmp/test_die_$$.sh"
    cat > "$temp_script" << 'EOF'
#!/bin/bash
source "$1"
die "测试致命错误" "GENERAL_ERROR"
EOF
    
    chmod +x "$temp_script"
    
    # 运行临时脚本，应该退出
    if "$temp_script" "$CORE_DIR/error_handler.sh" 2>/dev/null; then
        log_error "die函数应该导致脚本退出"
        rm -f "$temp_script"
        return 1
    fi
    
    rm -f "$temp_script"
    log_info "die函数测试通过"
    return 0
}

# 测试7: 错误检查函数
test_check_error() {
    log_info "测试错误检查函数..."
    
    # 测试成功情况
    if ! check_error 0 "成功操作"; then
        log_error "成功情况检查失败"
        return 1
    fi
    
    # 测试失败情况
    if check_error 1 "失败操作" 2>/dev/null; then
        log_error "失败情况检查应该返回非零退出码"
        return 1
    fi
    
    log_info "错误检查函数测试通过"
    return 0
}

# 测试8: 清理临时文件函数
test_cleanup_temp_files() {
    log_info "测试清理临时文件函数..."
    
    # 创建测试临时文件（使用与清理函数匹配的模式）
    local test_files=(
        "/tmp/datakit_install_test_$$"
        "/tmp/datakit_test_$$"
        "/tmp/install_test_$$"
        "/var/tmp/datakit_test_$$"
    )
    
    for file in "${test_files[@]}"; do
        touch "$file"
    done
    
    # 验证文件已创建
    for file in "${test_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "测试文件创建失败: $file"
            return 1
        fi
    done
    
    # 运行清理函数
    if ! cleanup_temp_files; then
        log_error "清理临时文件失败"
        # 清理测试文件
        for file in "${test_files[@]}"; do
            rm -f "$file" 2>/dev/null
        done
        return 1
    fi
    
    # 检查文件是否被清理
    for file in "${test_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_error "测试文件未被清理: $file"
            rm -f "$file" 2>/dev/null
            return 1
        fi
    done
    
    log_info "清理临时文件函数测试通过"
    return 0
}

# 测试9: 清理日志文件函数
test_cleanup_log_files() {
    log_info "测试清理日志文件函数..."
    
    # 创建测试日志文件
    local test_log="/tmp/datakit_test_$$.log"
    touch "$test_log"
    
    # 验证文件已创建
    if [[ ! -f "$test_log" ]]; then
        log_error "测试日志文件创建失败: $test_log"
        return 1
    fi
    
    # 修改文件时间为8天前（macOS兼容格式）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 使用 -t 参数
        touch -t "$(date -v-8d +%Y%m%d%H%M)" "$test_log"
    else
        # Linux 使用 -d 参数
        touch -d "8 days ago" "$test_log"
    fi
    
    # 验证文件时间已修改
    local file_age=$(find "$test_log" -mtime +7 2>/dev/null | wc -l)
    if [[ $file_age -eq 0 ]]; then
        log_error "文件时间修改失败，文件年龄不足7天"
        rm -f "$test_log" 2>/dev/null
        return 1
    fi
    
    # 运行清理函数
    if ! cleanup_log_files; then
        log_error "清理日志文件失败"
        rm -f "$test_log" 2>/dev/null
        return 1
    fi
    
    # 检查文件是否被清理
    if [[ -f "$test_log" ]]; then
        log_error "测试日志文件未被清理: $test_log"
        rm -f "$test_log" 2>/dev/null
        return 1
    fi
    
    log_info "清理日志文件函数测试通过"
    return 0
}

# 测试10: 退出清理函数
test_cleanup_on_exit() {
    log_info "测试退出清理函数..."
    
    # 运行退出清理函数
    if ! cleanup_on_exit; then
        log_error "退出清理函数失败"
        return 1
    fi
    
    log_info "退出清理函数测试通过"
    return 0
}

# 测试11: 信号处理函数
test_signal_handler() {
    log_info "测试信号处理函数..."
    
    # 创建一个临时脚本来测试信号处理
    local temp_script="/tmp/test_signal_$$.sh"
    cat > "$temp_script" << 'EOF'
#!/bin/bash
source "$1"
init_error_handler
# 发送信号给当前进程
kill -INT $$ 2>/dev/null
sleep 1
EOF
    
    chmod +x "$temp_script"
    
    # 运行临时脚本，应该因为信号处理而退出
    if "$temp_script" "$CORE_DIR/error_handler.sh" 2>/dev/null; then
        log_error "信号处理测试失败"
        rm -f "$temp_script"
        return 1
    fi
    
    rm -f "$temp_script"
    log_info "信号处理函数测试通过"
    return 0
}

# 测试12: 错误代码映射
test_error_code_mapping() {
    log_info "测试错误代码映射..."
    
    # 测试已知错误代码
    if [[ "$(get_error_code "GENERAL_ERROR")" -ne 1 ]]; then
        log_error "GENERAL_ERROR代码映射错误"
        return 1
    fi
    
    if [[ "$(get_error_code "NETWORK_ERROR")" -ne 3 ]]; then
        log_error "NETWORK_ERROR代码映射错误"
        return 1
    fi
    
    if [[ "$(get_error_code "PERMISSION_ERROR")" -ne 4 ]]; then
        log_error "PERMISSION_ERROR代码映射错误"
        return 1
    fi
    
    log_info "错误代码映射测试通过"
    return 0
}

# 主测试函数
main() {
    log_info "开始错误处理模块单元测试..."
    
    # 运行所有测试
    local tests=(
        "test_error_codes_definition"
        "test_error_severity_definition"
        "test_error_handler_init"
        "test_record_error"
        "test_handle_error"
        "test_die_function"
        "test_check_error"
        "test_cleanup_temp_files"
        "test_cleanup_log_files"
        "test_cleanup_on_exit"
        "test_signal_handler"
        "test_error_code_mapping"
    )
    
    local failed_tests=()
    
    for test in "${tests[@]}"; do
        if ! run_test "$test" "$test"; then
            failed_tests+=("$test")
        fi
    done
    
    # 输出测试结果
    log_info "=== 单元测试结果汇总 ==="
    log_info "总测试数: $TEST_TOTAL"
    log_info "通过测试: $TEST_PASSED"
    log_info "失败测试: $TEST_FAILED"
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        log_error "失败的测试:"
        for test in "${failed_tests[@]}"; do
            log_error "  - $test"
        done
        return 1
    else
        log_info "所有单元测试通过！"
        return 0
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 