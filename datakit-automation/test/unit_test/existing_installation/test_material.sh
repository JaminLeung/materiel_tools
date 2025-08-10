#!/bin/bash

#=================================================
# 物料包复制测试脚本
#=================================================
# 功能: 验证从/opt/datakit_install复制物料包的功能
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

# 测试物料包复制功能
test_material_copy() {
    log_info "测试物料包复制功能..."
    
    # 创建临时测试目录
    local test_temp_dir=$(mktemp -d -t datakit_material_test.XXXXXX)
    local test_install_dir="$test_temp_dir/install"
    
    log_info "测试临时目录: $test_temp_dir"
    
    # 测试1: 检查真实安装目录是否存在
    local real_install_dir="/opt/datakit_install"
    assert_true "[[ -d '$real_install_dir' ]]" "real_install_dir_exists" "真实安装目录应该存在"
    
    # 测试2: 检查关键文件是否存在
    assert_file_exists "$real_install_dir/datakit_bundle-linux-amd64-1.78.0.tar.gz" "bundle_file_exists" "Bundle文件应该存在"
    assert_file_exists "$real_install_dir/installer-linux-amd64-1.78.0" "installer_file_exists" "安装器文件应该存在"
    assert_file_exists "$real_install_dir/datakit-linux-amd64-1.78.0.tar.gz" "datakit_file_exists" "Datakit包文件应该存在"
    assert_file_exists "$real_install_dir/dk_upgrader-linux-amd64.tar.gz" "upgrader_file_exists" "升级器文件应该存在"
    assert_file_exists "$real_install_dir/data.tar.gz" "data_file_exists" "数据包文件应该存在"
    assert_file_exists "$real_install_dir/node_exporter-1.8.2.linux-amd64.tar.gz" "node_exporter_file_exists" "Node Exporter文件应该存在"
    
    # 测试3: 创建测试目录并复制文件
    mkdir -p "$test_install_dir"
    if cp -r "$real_install_dir"/* "$test_install_dir/" 2>/dev/null; then
        record_test_result "copy_files" "PASS" "文件复制成功"
    else
        record_test_result "copy_files" "FAIL" "文件复制失败"
    fi
    
    # 测试4: 验证复制的文件
    assert_file_exists "$test_install_dir/datakit_bundle-linux-amd64-1.78.0.tar.gz" "copied_bundle_exists" "复制的Bundle文件应该存在"
    assert_file_exists "$test_install_dir/installer-linux-amd64-1.78.0" "copied_installer_exists" "复制的安装器文件应该存在"
    assert_file_exists "$test_install_dir/datakit-linux-amd64-1.78.0.tar.gz" "copied_datakit_exists" "复制的Datakit包文件应该存在"
    
    # 测试5: 验证文件大小
    local original_size=$(stat -c%s "$real_install_dir/datakit_bundle-linux-amd64-1.78.0.tar.gz" 2>/dev/null || echo "0")
    local copied_size=$(stat -c%s "$test_install_dir/datakit_bundle-linux-amd64-1.78.0.tar.gz" 2>/dev/null || echo "0")
    
    if [[ "$original_size" == "$copied_size" && "$original_size" != "0" ]]; then
        record_test_result "file_size_match" "PASS" "文件大小匹配 (${original_size} bytes)"
    else
        record_test_result "file_size_match" "FAIL" "文件大小不匹配 (原始: ${original_size}, 复制: ${copied_size})"
    fi
    
    # 测试6: 验证安装器执行权限
    if [[ -x "$test_install_dir/installer-linux-amd64-1.78.0" ]]; then
        record_test_result "installer_executable" "PASS" "安装器有执行权限"
    else
        record_test_result "installer_executable" "FAIL" "安装器没有执行权限"
    fi
    
    # 清理测试目录
    rm -rf "$test_temp_dir"
    log_info "已清理测试临时目录: $test_temp_dir"
}

# 主函数
main() {
    log_info "开始物料包复制测试..."
    echo ""
    
    # 运行测试
    test_material_copy
    
    # 显示结果
    show_test_results
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 