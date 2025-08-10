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

# 测试前准备
setup() {
    # 设置测试环境变量
    export LOG_FILE="$TEST_LOG_FILE"
    export SCRIPT_NAME="test_script"
    export SCRIPT_VERSION="1.0.0"
    
    # 初始化日志系统
    init_logging
    
    # 清理测试文件
    rm -f "$TEST_LOG_FILE"
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
    log_info "测试SUCCESS日志"
    assert_contains "$(cat "$TEST_LOG_FILE")" "SUCCESS" "日志文件应该包含SUCCESS级别"
}

# 测试JSON日志格式
test_json_log_format() {
    # 记录一条测试日志
    log_info "测试JSON日志格式"
    
    # 检查日志格式
    local log_content=$(cat "$TEST_LOG_FILE")
    
    # 检查JSON格式
    assert_contains "$log_content" '"timestamp"' "JSON日志应该包含timestamp字段"
    assert_contains "$log_content" '"level"' "JSON日志应该包含level字段"
    assert_contains "$log_content" '"message"' "JSON日志应该包含message字段"
    assert_contains "$log_content" '"pid"' "JSON日志应该包含pid字段"
    assert_contains "$log_content" '"script_name"' "JSON日志应该包含script_name字段"
    assert_contains "$log_content" '"script_version"' "JSON日志应该包含script_version字段"
    assert_contains "$log_content" '"hostname"' "JSON日志应该包含hostname字段"
    assert_contains "$log_content" '"user"' "JSON日志应该包含user字段"
    assert_contains "$log_content" '"context"' "JSON日志应该包含context字段"
    
    # 检查时间戳格式
    assert_contains "$log_content" "$(date '+%Y-%m-%d')" "日志应该包含当前日期"
    
    # 检查日志级别
    assert_contains "$log_content" '"level": "INFO"' "日志应该包含INFO级别"
    
    # 检查消息内容
    assert_contains "$log_content" '"message": "测试JSON日志格式"' "日志应该包含消息内容"
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
    log_info "这条SUCCESS日志应该出现"
    
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

# 测试日志系统初始化
test_log_system_init() {
    # 清理日志文件
    rm -f "$TEST_LOG_FILE"
    
    # 重新初始化日志系统
    init_logging
    
    # 检查日志文件是否被创建
    assert_file_exists "$TEST_LOG_FILE" "初始化后日志文件应该被创建"
    
    # 检查初始化日志记录
    local log_content=$(cat "$TEST_LOG_FILE")
    assert_contains "$log_content" "日志系统初始化完成" "应该记录初始化完成信息"
    assert_contains "$log_content" '"action": "logging_init"' "应该包含初始化动作标识"
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

# 测试环境变量依赖
test_environment_variables() {
    # 测试缺少环境变量的情况
    unset SCRIPT_NAME
    unset SCRIPT_VERSION
    
    # 记录一条日志（应该不会失败）
    log_info "测试缺少环境变量的情况"
    
    # 检查日志文件
    assert_file_exists "$TEST_LOG_FILE" "缺少环境变量时日志文件仍应该被创建"
    
    # 恢复环境变量
    export SCRIPT_NAME="test_script"
    export SCRIPT_VERSION="1.0.0"
}

# 测试日志级别控制函数
test_log_level_control() {
    # 测试设置日志级别函数
    set_log_level "DEBUG"
    assert_equal "$CURRENT_LOG_LEVEL" "0" "set_log_level应该能设置DEBUG级别"
    
    set_log_level "ERROR"
    assert_equal "$CURRENT_LOG_LEVEL" "3" "set_log_level应该能设置ERROR级别"
    
    # 测试无效级别
    local result
    result=$(set_log_level "INVALID" 2>&1)
    assert_not_equal "$?" "0" "无效日志级别应该返回错误"
    
    # 恢复默认级别
    set_log_level "INFO"
}

# 测试工具函数
test_utility_functions() {
    # 测试获取日志级别数值
    local debug_num=$(get_log_level_num "DEBUG")
    assert_equal "$debug_num" "0" "DEBUG级别应该对应数值0"
    
    local info_num=$(get_log_level_num "INFO")
    assert_equal "$info_num" "1" "INFO级别应该对应数值1"
    
    local warning_num=$(get_log_level_num "WARNING")
    assert_equal "$warning_num" "2" "WARNING级别应该对应数值2"
    
    # 测试获取日志颜色
    local debug_color=$(get_log_color "DEBUG")
    assert_not_equal "$debug_color" "" "DEBUG级别应该有颜色"
    
    local info_color=$(get_log_color "INFO")
    assert_not_equal "$info_color" "" "INFO级别应该有颜色"
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