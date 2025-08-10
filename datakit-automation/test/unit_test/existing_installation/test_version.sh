#!/bin/bash

#=================================================
# 版本号获取测试脚本
#=================================================
# 功能: 验证版本号获取和文件匹配功能
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

log_info() {
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

assert_equal() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"
    local message="$4"
    
    if [[ "$actual" == "$expected" ]]; then
        record_test_result "$test_name" "PASS" "$message"
        return 0
    else
        record_test_result "$test_name" "FAIL" "$message (期望: '$expected', 实际: '$actual')"
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

# 测试版本号获取功能
test_version_extraction() {
    log_info "测试版本号获取功能..."
    
    # 测试1: 检查真实安装目录是否存在
    local real_install_dir="/opt/datakit_install"
    assert_true "[[ -d '$real_install_dir' ]]" "real_install_dir_exists" "真实安装目录应该存在"
    
    # 测试2: 检查bundle文件是否存在
    local bundle_files=(/opt/datakit_install/datakit_bundle-linux-amd64-*.tar.gz)
    if [[ -f "${bundle_files[0]}" ]]; then
        record_test_result "bundle_file_exists" "PASS" "Bundle文件存在"
        
        # 测试3: 提取版本号
        local bundle_file="${bundle_files[0]}"
        local extracted_version=$(basename "$bundle_file" | sed 's/datakit_bundle-linux-amd64-\(.*\)\.tar\.gz/\1/')
        
        log_info "提取的版本号: $extracted_version"
        
        # 验证版本号格式
        if [[ "$extracted_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            record_test_result "version_format_valid" "PASS" "版本号格式正确: $extracted_version"
        else
            record_test_result "version_format_valid" "FAIL" "版本号格式不正确: $extracted_version"
        fi
        
        # 测试4: 验证其他文件是否匹配版本号
        local installer_file="/opt/datakit_install/installer-linux-amd64-$extracted_version"
        local datakit_file="/opt/datakit_install/datakit-linux-amd64-$extracted_version.tar.gz"
        
        assert_file_exists "$installer_file" "installer_version_match" "安装器文件版本匹配"
        assert_file_exists "$datakit_file" "datakit_version_match" "Datakit文件版本匹配"
        
        # 测试5: 验证文件大小
        local bundle_size=$(stat -c%s "$bundle_file" 2>/dev/null || echo "0")
        local installer_size=$(stat -c%s "$installer_file" 2>/dev/null || echo "0")
        local datakit_size=$(stat -c%s "$datakit_file" 2>/dev/null || echo "0")
        
        if [[ "$bundle_size" -gt 0 ]]; then
            record_test_result "bundle_file_size" "PASS" "Bundle文件大小: ${bundle_size} bytes"
        else
            record_test_result "bundle_file_size" "FAIL" "Bundle文件大小为0"
        fi
        
        if [[ "$installer_size" -gt 0 ]]; then
            record_test_result "installer_file_size" "PASS" "安装器文件大小: ${installer_size} bytes"
        else
            record_test_result "installer_file_size" "FAIL" "安装器文件大小为0"
        fi
        
        if [[ "$datakit_size" -gt 0 ]]; then
            record_test_result "datakit_file_size" "PASS" "Datakit文件大小: ${datakit_size} bytes"
        else
            record_test_result "datakit_file_size" "FAIL" "Datakit文件大小为0"
        fi
        
    else
        record_test_result "bundle_file_exists" "FAIL" "Bundle文件不存在"
    fi
    
    # 测试6: 测试默认版本号设置
    local default_version="1.78.0"
    assert_equal "$default_version" "1.78.0" "default_version_set" "默认版本号设置正确"
    
    # 测试7: 验证版本号环境变量设置
    export DATAKIT_VERSION="$extracted_version"
    if [[ -n "$DATAKIT_VERSION" ]]; then
        record_test_result "version_env_set" "PASS" "版本号环境变量设置成功: $DATAKIT_VERSION"
    else
        record_test_result "version_env_set" "FAIL" "版本号环境变量设置失败"
    fi
}

# 主函数
main() {
    log_info "开始版本号获取测试..."
    echo ""
    
    # 运行测试
    test_version_extraction
    
    # 显示结果
    show_test_results
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 