#!/bin/bash

#=================================================
# 日志系统模块测试
#=================================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 加载测试工具
source "$SCRIPT_DIR/../test_utils.sh"

# 加载被测试的模块
source "$PROJECT_ROOT/core/logging.sh"

# 测试临时文件
TEMP_DIR=$(mktemp -d)
TEST_LOG_FILE="$TEMP_DIR/test.log"
TEST_JSON_LOG_FILE="$TEMP_DIR/test.json"

# 测试前准备
setup() {
    # 设置测试环境变量
    export LOG_FILE="$TEST_LOG_FILE"
    export SCRIPT_NAME="test_script"
    export SCRIPT_VERSION="1.0.0"
    export SCRIPT_EXIT_CODE="0"
    
    # 初始化日志系统
    init_logging
    
    # 清理测试文件
    rm -f "$TEST_LOG_FILE"
    rm -f "$TEST_JSON_LOG_FILE"
}

# 测试后清理
teardown() {
    rm -rf "$TEMP_DIR"
}

# 测试日志级别设置
test_log_levels() {
    # 测试默认日志级别
    assert_equal "$CURRENT_LOG_LEVEL" "1" "默认日志级别应该是INFO(1)"
    
    # 测试设置不同日志级别
    export LOG_LEVEL=0  # DEBUG
    source ../../core/logging.sh
    assert_equal "$CURRENT_LOG_LEVEL" "0" "DEBUG日志级别应该设置为0"
    
    export LOG_LEVEL=2  # WARNING
    source ../../core/logging.sh
    assert_equal "$CURRENT_LOG_LEVEL" "2" "WARNING日志级别应该设置为2"
    
    export LOG_LEVEL=3  # ERROR
    source ../../core/logging.sh
    assert_equal "$CURRENT_LOG_LEVEL" "3" "ERROR日志级别应该设置为3"
    
    # 恢复默认级别
    export LOG_LEVEL=1
    source ../../core/logging.sh
}

# 测试日志函数
test_log_functions() {
    # 测试DEBUG日志
    log_debug "测试DEBUG日志"
    assert_file_exists "$TEST_LOG_FILE" "日志文件应该被创建"
    assert_contains "$(cat "$TEST_LOG_FILE")" "DEBUG" "日志文件应该包含DEBUG级别"
    
    # 测试INFO日志
    log_info "测试INFO日志"
    assert_contains "$(cat "$TEST_LOG_FILE")" "INFO" "日志文件应该包含INFO级别"
    
    # 测试WARNING日志
    log_warning "测试WARNING日志"
    assert_contains "$(cat "$TEST_LOG_FILE")" "WARNING" "日志文件应该包含WARNING级别"
    
    # 测试ERROR日志
    log_error "测试ERROR日志"
    assert_contains "$(cat "$TEST_LOG_FILE")" "ERROR" "日志文件应该包含ERROR级别"
    
    # 测试SUCCESS日志
    log_success "测试SUCCESS日志"
    assert_contains "$(cat "$TEST_LOG_FILE")" "SUCCESS" "日志文件应该包含SUCCESS级别"
}

# 测试日志格式
test_log_format() {
    # 记录一条测试日志
    log_info "测试日志格式"
    
    # 检查日志格式
    local log_content=$(cat "$TEST_LOG_FILE")
    
    # 检查时间戳格式
    assert_contains "$log_content" "$(date '+%Y-%m-%d')" "日志应该包含当前日期"
    
    # 检查日志级别
    assert_contains "$log_content" "[INFO]" "日志应该包含INFO级别标记"
    
    # 检查消息内容
    assert_contains "$log_content" "测试日志格式" "日志应该包含消息内容"
}

# 测试日志级别过滤
test_log_level_filtering() {
    # 设置日志级别为WARNING
    export LOG_LEVEL=2
    source ../../core/logging.sh
    
    # 清理日志文件
    rm -f "$TEST_LOG_FILE"
    
    # 记录不同级别的日志
    log_debug "这条DEBUG日志不应该出现"
    log_info "这条INFO日志不应该出现"
    log_warning "这条WARNING日志应该出现"
    log_error "这条ERROR日志应该出现"
    log_success "这条SUCCESS日志应该出现"
    
    # 检查日志内容
    local log_content=$(cat "$TEST_LOG_FILE")
    
    # DEBUG和INFO日志不应该出现
    assert_not_contains "$log_content" "DEBUG" "DEBUG日志不应该出现在WARNING级别"
    assert_not_contains "$log_content" "INFO" "INFO日志不应该出现在WARNING级别"
    
    # WARNING、ERROR、SUCCESS日志应该出现
    assert_contains "$log_content" "WARNING" "WARNING日志应该出现在WARNING级别"
    assert_contains "$log_content" "ERROR" "ERROR日志应该出现在WARNING级别"
    assert_contains "$log_content" "SUCCESS" "SUCCESS日志应该出现在WARNING级别"
    
    # 恢复默认级别
    export LOG_LEVEL=1
    source ../../core/logging.sh
}

# 测试日志文件创建
test_log_file_creation() {
    # 测试无法创建日志文件的情况
    local readonly_dir="$TEMP_DIR/readonly"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir"  # 只读目录
    
    export LOG_FILE="$readonly_dir/test.log"
    source ../../core/logging.sh
    
    # 应该回退到/dev/null
    assert_equal "$LOG_FILE" "/dev/null" "无法创建日志文件时应该回退到/dev/null"
    
    # 恢复权限
    chmod 755 "$readonly_dir"
}

# 测试脚本启动记录
test_script_start_record() {
    # 设置JSON日志文件
    export LOG_FILE="$TEST_JSON_LOG_FILE"
    source ../../core/logging.sh
    
    # 记录脚本启动
    record_script_start
    
    # 检查JSON日志文件
    assert_file_exists "$TEST_JSON_LOG_FILE.json" "JSON日志文件应该被创建"
    
    # 检查JSON格式
    local json_content=$(cat "$TEST_JSON_LOG_FILE.json")
    assert_contains "$json_content" "timestamp" "JSON应该包含timestamp字段"
    assert_contains "$json_content" "script_name" "JSON应该包含script_name字段"
    assert_contains "$json_content" "script_version" "JSON应该包含script_version字段"
    assert_contains "$json_content" "action" "JSON应该包含action字段"
    assert_contains "$json_content" "start" "action字段应该是start"
}

# 测试脚本结束记录
test_script_end_record() {
    # 设置JSON日志文件
    export LOG_FILE="$TEST_JSON_LOG_FILE"
    export SCRIPT_EXIT_CODE="0"
    source ../../core/logging.sh
    
    # 记录脚本结束
    record_script_end
    
    # 检查JSON日志文件
    assert_file_exists "$TEST_JSON_LOG_FILE.json" "JSON日志文件应该被创建"
    
    # 检查JSON格式
    local json_content=$(cat "$TEST_JSON_LOG_FILE.json")
    assert_contains "$json_content" "timestamp" "JSON应该包含timestamp字段"
    assert_contains "$json_content" "script_name" "JSON应该包含script_name字段"
    assert_contains "$json_content" "script_version" "JSON应该包含script_version字段"
    assert_contains "$json_content" "action" "JSON应该包含action字段"
    assert_contains "$json_content" "end" "action字段应该是end"
    assert_contains "$json_content" "exit_code" "JSON应该包含exit_code字段"
}

# 测试日志轮转
test_log_rotation() {
    # 创建大量日志内容
    for i in {1..100}; do
        log_info "测试日志条目 $i"
    done
    
    # 检查日志文件大小
    local file_size=$(stat -f%z "$TEST_LOG_FILE" 2>/dev/null || stat -c%s "$TEST_LOG_FILE" 2>/dev/null || echo "0")
    assert_true "[ $file_size -gt 0 ]" "日志文件应该有内容"
}

# 测试并发日志写入
test_concurrent_logging() {
    # 创建多个进程同时写入日志
    for i in {1..5}; do
        (
            log_info "并发日志 $i"
        ) &
    done
    
    # 等待所有进程完成
    wait
    
    # 检查日志文件
    assert_file_exists "$TEST_LOG_FILE" "并发写入后日志文件应该存在"
    
    # 检查日志条目数量
    local log_lines=$(wc -l < "$TEST_LOG_FILE")
    assert_true "[ $log_lines -ge 5 ]" "应该有至少5行日志"
}

# 测试特殊字符处理
test_special_characters() {
    # 测试包含特殊字符的日志消息
    log_info "测试特殊字符: !@#$%^&*()_+-=[]{}|;':\",./<>?"
    log_warning "测试换行符\n和制表符\t"
    log_error "测试中文日志：你好世界"
    
    # 检查日志文件
    assert_file_exists "$TEST_LOG_FILE" "包含特殊字符的日志文件应该存在"
    
    local log_content=$(cat "$TEST_LOG_FILE")
    assert_contains "$log_content" "特殊字符" "日志应该包含特殊字符"
    assert_contains "$log_content" "中文日志" "日志应该包含中文"
}

# 测试日志性能
# test_log_performance() {
#     local start_time=$(date +%s)
    
#     # 记录大量日志
#     for i in {1..1000}; do
#         log_info "性能测试日志 $i"
#     done
    
#     local end_time=$(date +%s)
#     local duration=$((end_time - start_time))
    
#     # 检查性能（应该在合理时间内完成）
#     assert_true "[ $duration -lt 10 ]" "1000条日志应该在10秒内完成"
# }

# 测试环境变量依赖
test_environment_variables() {
    # 测试缺少环境变量的情况
    unset SCRIPT_NAME
    unset SCRIPT_VERSION
    
    # 记录脚本启动（应该不会失败）
    record_script_start
    
    # 检查JSON日志文件
    assert_file_exists "$TEST_JSON_LOG_FILE.json" "缺少环境变量时JSON日志文件仍应该被创建"
    
    # 恢复环境变量
    export SCRIPT_NAME="test_script"
    export SCRIPT_VERSION="1.0.0"
}

# 运行测试
main() {
    echo "开始运行日志系统测试..."
    
    # 执行设置
    setup
    
    # 运行所有测试函数
    run_tests "logging"
    
    # 执行清理
    teardown
}

# 如果直接运行此脚本，则执行测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 