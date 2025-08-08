#!/bin/bash

#=================================================
# Core模块加载测试脚本
#=================================================
# 功能: 验证core模块的加载情况
#=================================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# 测试结果
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
TEST_RESULTS=()

# 记录测试结果
record_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    ((TEST_COUNT++))
    
    case "$status" in
        "PASS")
            ((PASS_COUNT++))
            echo -e "${GREEN}✅ PASS${NC}: $test_name - $message"
            ;;
        "FAIL")
            ((FAIL_COUNT++))
            echo -e "${RED}❌ FAIL${NC}: $test_name - $message"
            ;;
    esac
    
    TEST_RESULTS+=("$status: $test_name - $message")
}

# 基础断言
assert_true() {
    local condition="$1"
    local test_name="$2"
    local message="$3"
    
    if eval "$condition"; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message"
        return 1
    fi
}

assert_function_exists() {
    local function_name="$1"
    local test_name="$2"
    local message="$3"
    
    if declare -f "$function_name" >/dev/null 2>&1; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message (函数不存在: $function_name)"
        return 1
    fi
}

# 显示测试结果
show_test_results() {
    echo ""
    echo "=========================================="
    echo "测试结果统计"
    echo "=========================================="
    echo "总测试数: $TEST_COUNT"
    echo "通过: $PASS_COUNT"
    echo "失败: $FAIL_COUNT"
    
    if [[ $TEST_COUNT -gt 0 ]]; then
        local pass_rate=$((PASS_COUNT * 100 / TEST_COUNT))
        echo "通过率: ${pass_rate}%"
    fi
    
    echo ""
    echo "详细结果:"
    echo "------------------------------------------"
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    
    echo ""
    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}🎉 所有测试通过！${NC}"
        return 0
    else
        echo -e "${RED}⚠️  有 $FAIL_COUNT 个测试失败${NC}"
        return 1
    fi
}

# 测试core模块加载
test_core_modules() {
    log_info "测试core模块加载功能..."
    
    # 测试1: 检查core目录是否存在
    local core_dir="$PROJECT_ROOT/datakit-automation/core"
    assert_true "[[ -d '$core_dir' ]]" "core_dir_exists" "Core目录应该存在"
    
    # 测试2: 检查各个core模块文件是否存在
    local core_modules=(
        "logging.sh"
        "utils.sh"
        "validation.sh"
        "initialize.sh"
        "health_check.sh"
        "datakit_service.sh"
        "config_file.sh"
    )
    
    for module in "${core_modules[@]}"; do
        local module_path="$core_dir/$module"
        local module_name="${module%.sh}"
        assert_true "[[ -f '$module_path' ]]" "${module_name}_file_exists" "Core模块文件应该存在: $module"
    done
    
    # 测试3: 加载core模块并检查函数
    log_info "加载core模块..."
    
    # 加载logging模块
    if [[ -f "$core_dir/logging.sh" ]]; then
        source "$core_dir/logging.sh"
        assert_function_exists "log_info" "logging_log_info_function" "log_info函数应该存在"
        assert_function_exists "log_error" "logging_log_error_function" "log_error函数应该存在"
        assert_function_exists "log_warning" "logging_log_warning_function" "log_warning函数应该存在"
        assert_function_exists "log_success" "logging_log_success_function" "log_success函数应该存在"
    fi
    
    # 加载utils模块
    if [[ -f "$core_dir/utils.sh" ]]; then
        source "$core_dir/utils.sh"
        assert_function_exists "set_global_state" "utils_set_global_state_function" "set_global_state函数应该存在"
        assert_function_exists "get_global_state" "utils_get_global_state_function" "get_global_state函数应该存在"
    fi
    
    # 加载validation模块
    if [[ -f "$core_dir/validation.sh" ]]; then
        source "$core_dir/validation.sh"
        assert_function_exists "validate_config" "validation_validate_config_function" "validate_config函数应该存在"
    fi
    
    # 加载initialize模块
    if [[ -f "$core_dir/initialize.sh" ]]; then
        source "$core_dir/initialize.sh"
        assert_function_exists "initialize_datakit" "initialize_initialize_datakit_function" "initialize_datakit函数应该存在"
    fi
    
    # 加载health_check模块
    if [[ -f "$core_dir/health_check.sh" ]]; then
        source "$core_dir/health_check.sh"
        assert_function_exists "check_datakit_health" "health_check_check_datakit_health_function" "check_datakit_health函数应该存在"
    fi
    
    # 加载datakit_service模块
    if [[ -f "$core_dir/datakit_service.sh" ]]; then
        source "$core_dir/datakit_service.sh"
        assert_function_exists "start_datakit_service" "datakit_service_start_datakit_service_function" "start_datakit_service函数应该存在"
    fi
    
    # 加载config_file模块
    if [[ -f "$core_dir/config_file.sh" ]]; then
        source "$core_dir/utils.sh"
        assert_function_exists "update_config_file" "config_file_update_config_file_function" "update_config_file函数应该存在"
    fi
    
    # 测试4: 验证函数调用
    log_info "验证函数调用..."
    
    # 测试日志函数调用
    if declare -f log_info >/dev/null 2>&1; then
        local test_output=$(log_info "测试日志输出" 2>&1)
        if [[ -n "$test_output" ]]; then
            record_test_result "log_function_call" "PASS" "日志函数调用成功"
        else
            record_test_result "log_function_call" "FAIL" "日志函数调用失败"
        fi
    fi
    
    # 测试工具函数调用
    if declare -f set_global_state >/dev/null 2>&1; then
        set_global_state "test_key" "test_value" 2>/dev/null || true
        local retrieved_value=$(get_global_state "test_key" 2>/dev/null || echo "")
        if [[ "$retrieved_value" == "test_value" ]]; then
            record_test_result "utils_function_call" "PASS" "工具函数调用成功"
        else
            record_test_result "utils_function_call" "FAIL" "工具函数调用失败"
        fi
    fi
}

# 主函数
main() {
    log_info "开始core模块加载测试..."
    echo ""
    
    # 运行测试
    test_core_modules
    
    # 显示结果
    show_test_results
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 