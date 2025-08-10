#!/bin/bash

#=================================================
# 基础测试脚本
#=================================================
# 功能: 验证测试框架的基本功能
#=================================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../" && pwd)"

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

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"
    local message="$3"
    
    if [[ -f "$file_path" ]]; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message (文件不存在: $file_path)"
        return 1
    fi
}

assert_dir_exists() {
    local dir_path="$1"
    local test_name="$2"
    local message="$3"
    
    if [[ -d "$dir_path" ]]; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message (目录不存在: $dir_path)"
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

# 测试函数
test_basic_functionality() {
    log_info "测试基本功能..."
    
    # 测试1: 检查项目根目录
    assert_true "[[ -d '$PROJECT_ROOT' ]]" "project_root_exists" "项目根目录应该存在"
    
    # 测试2: 检查install目录
    assert_true "[[ -d '$PROJECT_ROOT/install' ]]" "install_dir_exists" "install目录应该存在"
    
    # 测试3: 检查status_check.sh文件
    assert_file_exists "$PROJECT_ROOT/install/status_check.sh" "status_check_file_exists" "status_check.sh文件应该存在"
    
    # 测试4: 检查download.sh文件
    assert_file_exists "$PROJECT_ROOT/install/download.sh" "download_file_exists" "download.sh文件应该存在"
    
    # 测试5: 检查install.sh文件
    assert_file_exists "$PROJECT_ROOT/install/install.sh" "install_file_exists" "install.sh文件应该存在"
    
    # 测试6: 检查configure.sh文件
    assert_file_exists "$PROJECT_ROOT/install/configure.sh" "configure_file_exists" "configure.sh文件应该存在"
    
    # 测试7: 检查setup_cron.sh文件
    assert_file_exists "$PROJECT_ROOT/install/setup_cron.sh" "setup_cron_file_exists" "setup_cron.sh文件应该存在"
    
    # 测试8: 检查verify.sh文件
    assert_file_exists "$PROJECT_ROOT/install/verify.sh" "verify_file_exists" "verify.sh文件应该存在"
    
    # 测试9: 检查host_info.sh文件
    assert_file_exists "$PROJECT_ROOT/install/host_info.sh" "host_info_file_exists" "host_info.sh文件应该存在"
    
    # 测试10: 检查config目录
    assert_dir_exists "$PROJECT_ROOT/config" "config_dir_exists" "config目录应该存在"
    
    # 测试11: 检查base_config.sh文件
    assert_file_exists "$PROJECT_ROOT/config/base/base_config.sh" "base_config_file_exists" "base_config.sh文件应该存在"
}

# 主函数
main() {
    log_info "开始基础测试..."
    echo ""
    
    # 运行测试
    test_basic_functionality
    
    # 显示结果
    show_test_results
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 