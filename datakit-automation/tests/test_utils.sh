#!/bin/bash

#=================================================
# 测试工具函数模块
#=================================================
# 功能: 断言函数、测试框架、测试报告生成
#=================================================

# 测试统计
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

# 测试开始时间
TEST_START_TIME=$(date +%s)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试结果文件
TEST_RESULT_FILE=""
TEST_LOG_FILE=""

# 初始化测试环境
init_test_environment() {
    local test_name="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # 创建结果目录
    mkdir -p "results/test_reports"
    mkdir -p "results/coverage"
    
    # 设置测试文件
    TEST_RESULT_FILE="results/test_reports/${test_name}_${timestamp}.json"
    TEST_LOG_FILE="results/test_reports/${test_name}_${timestamp}.log"
    
    # 初始化测试统计
    TEST_TOTAL=0
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0
    
    # 记录测试开始
    echo "=== 测试开始: $test_name ===" | tee -a "$TEST_LOG_FILE"
    echo "开始时间: $(date)" | tee -a "$TEST_LOG_FILE"
    echo "" | tee -a "$TEST_LOG_FILE"
}

# 记录测试结果
record_test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    local duration="$4"
    
    TEST_TOTAL=$((TEST_TOTAL + 1))
    
    case "$result" in
        "PASS")
            TEST_PASSED=$((TEST_PASSED + 1))
            echo -e "  ${GREEN}✓ PASS${NC} $test_name ($duration)" | tee -a "$TEST_LOG_FILE"
            ;;
        "FAIL")
            TEST_FAILED=$((TEST_FAILED + 1))
            echo -e "  ${RED}✗ FAIL${NC} $test_name: $message ($duration)" | tee -a "$TEST_LOG_FILE"
            ;;
        "SKIP")
            TEST_SKIPPED=$((TEST_SKIPPED + 1))
            echo -e "  ${YELLOW}⚠ SKIP${NC} $test_name: $message ($duration)" | tee -a "$TEST_LOG_FILE"
            ;;
    esac
}

# 生成测试报告
generate_test_report() {
    local test_name="$1"
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    
    # 计算成功率
    local success_rate=0
    if [ $TEST_TOTAL -gt 0 ]; then
        success_rate=$(echo "scale=2; $TEST_PASSED * 100 / $TEST_TOTAL" | bc)
    fi
    
    # 生成JSON报告
    cat > "$TEST_RESULT_FILE" << EOF
{
    "test_name": "$test_name",
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": $duration,
    "summary": {
        "total": $TEST_TOTAL,
        "passed": $TEST_PASSED,
        "failed": $TEST_FAILED,
        "skipped": $TEST_SKIPPED,
        "success_rate": $success_rate
    }
}
EOF
    
    # 输出摘要
    echo "" | tee -a "$TEST_LOG_FILE"
    echo "=== 测试摘要 ===" | tee -a "$TEST_LOG_FILE"
    echo "总测试数: $TEST_TOTAL" | tee -a "$TEST_LOG_FILE"
    echo "通过: $TEST_PASSED" | tee -a "$TEST_LOG_FILE"
    echo "失败: $TEST_FAILED" | tee -a "$TEST_LOG_FILE"
    echo "跳过: $TEST_SKIPPED" | tee -a "$TEST_LOG_FILE"
    echo "成功率: ${success_rate}%" | tee -a "$TEST_LOG_FILE"
    echo "执行时间: ${duration}秒" | tee -a "$TEST_LOG_FILE"
    echo "报告文件: $TEST_RESULT_FILE" | tee -a "$TEST_LOG_FILE"
    
    # 返回退出码
    if [ $TEST_FAILED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# 断言函数

# 断言两个值相等
assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-期望值 '$expected'，实际值 '$actual'}"
    
    if [ "$expected" = "$actual" ]; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言两个值不相等
assert_not_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-值不应该等于 '$expected'}"
    
    if [ "$expected" != "$actual" ]; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言条件为真
assert_true() {
    local condition="$1"
    local message="${2:-条件应该为真}"
    
    if eval "$condition"; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言条件为假
assert_false() {
    local condition="$1"
    local message="${2:-条件应该为假}"
    
    if ! eval "$condition"; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言文件存在
assert_file_exists() {
    local file="$1"
    local message="${2:-文件 '$file' 应该存在}"
    
    if [ -f "$file" ]; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言文件不存在
assert_file_not_exists() {
    local file="$1"
    local message="${2:-文件 '$file' 不应该存在}"
    
    if [ ! -f "$file" ]; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言目录存在
assert_dir_exists() {
    local dir="$1"
    local message="${2:-目录 '$dir' 应该存在}"
    
    if [ -d "$dir" ]; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言命令存在
assert_command_exists() {
    local command="$1"
    local message="${2:-命令 '$command' 应该存在}"
    
    if command -v "$command" >/dev/null 2>&1; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言字符串包含子字符串
assert_contains() {
    local string="$1"
    local substring="$2"
    local message="${3:-字符串应该包含 '$substring'}"
    
    if [[ "$string" == *"$substring"* ]]; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 断言字符串不包含子字符串
assert_not_contains() {
    local string="$1"
    local substring="$2"
    local message="${3:-字符串不应该包含 '$substring'}"
    
    if [[ "$string" != *"$substring"* ]]; then
        record_test_result "${FUNCNAME[1]}" "PASS" "" "$(get_test_duration)"
        return 0
    else
        record_test_result "${FUNCNAME[1]}" "FAIL" "$message" "$(get_test_duration)"
        return 1
    fi
}

# 跳过测试
skip_test() {
    local reason="$1"
    record_test_result "${FUNCNAME[1]}" "SKIP" "$reason" "$(get_test_duration)"
    return 0
}

# 获取测试执行时间
get_test_duration() {
    local current_time=$(date +%s)
    local duration=$((current_time - TEST_START_TIME))
    echo "${duration}s"
}

# 运行测试函数
run_test() {
    local test_function="$1"
    local test_start_time=$(date +%s)
    
    # 设置测试开始时间
    TEST_START_TIME=$test_start_time
    
    # 执行测试
    if $test_function; then
        return 0
    else
        return 1
    fi
}

# 运行所有测试
run_tests() {
    local test_name="${1:-$(basename "$0" .sh)}"
    
    # 初始化测试环境
    init_test_environment "$test_name"
    
    # 获取所有测试函数
    local test_functions=($(declare -F | awk '{print $3}' | grep '^test_'))
    
    echo "发现 ${#test_functions[@]} 个测试函数:"
    for func in "${test_functions[@]}"; do
        echo "  - $func"
    done
    echo ""
    
    # 运行每个测试
    for func in "${test_functions[@]}"; do
        echo "运行测试函数: $func" | tee -a "$TEST_LOG_FILE"
        run_test "$func"
    done
    
    # 生成报告
    generate_test_report "$test_name"
} 