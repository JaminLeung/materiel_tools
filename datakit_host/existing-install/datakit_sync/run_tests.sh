#!/bin/bash

# Datakit物料同步脚本测试运行脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_info() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查Python环境
check_python_environment() {
    log_info "检查Python环境..."
    
    if ! command -v python3 &> /dev/null; then
        log_error "Python3未安装"
        exit 1
    fi
    
    local python_version=$(python3 --version | cut -d' ' -f2)
    log_info "Python版本: $python_version"
    
    # 检查必要的Python包
    local required_packages=("unittest" "tempfile" "os" "shutil" "json" "datetime")
    local missing_packages=()
    
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" 2>/dev/null; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_error "缺少Python包: ${missing_packages[*]}"
        exit 1
    fi
    
    log_info "Python环境检查通过"
}

# 安装测试依赖
install_test_dependencies() {
    log_info "安装测试依赖..."
    
    # 检查是否在虚拟环境中
    if [[ "$VIRTUAL_ENV" == "" ]]; then
        log_warning "建议在虚拟环境中运行测试"
    fi
    
    # 安装测试依赖
    pip install pytest pytest-cov pytest-mock coverage
    
    log_info "测试依赖安装完成"
}

# 运行单元测试
run_unit_tests() {
    log_info "运行单元测试..."
    
    # 切换到测试目录
    cd "$(dirname "$0")"
    
    # 运行unittest测试
    log_info "运行unittest测试..."
    python3 -m unittest test_datakit_sync.TestDatakitSync -v
    
    # 运行集成测试
    log_info "运行集成测试..."
    python3 -m unittest test_datakit_sync.TestDatakitSyncIntegration -v
    
    log_info "单元测试完成"
}

# 运行pytest测试
run_pytest_tests() {
    log_info "运行pytest测试..."
    
    # 切换到测试目录
    cd "$(dirname "$0")"
    
    # 运行pytest测试
    python3 -m pytest test_datakit_sync.py -v --tb=short
    
    log_info "pytest测试完成"
}

# 生成测试覆盖率报告
generate_coverage_report() {
    log_info "生成测试覆盖率报告..."
    
    # 切换到测试目录
    cd "$(dirname "$0")"
    
    # 运行覆盖率测试
    python3 -m coverage run --source=datakit_sync -m pytest test_datakit_sync.py
    
    # 生成HTML报告
    python3 -m coverage html
    
    # 显示覆盖率摘要
    python3 -m coverage report
    
    log_info "覆盖率报告生成完成"
    log_info "HTML报告位置: htmlcov/index.html"
}

# 运行性能测试
run_performance_tests() {
    log_info "运行性能测试..."
    
    # 切换到测试目录
    cd "$(dirname "$0")"
    
    # 创建性能测试脚本
    cat > performance_test.py << 'EOF'
#!/usr/bin/env python3
"""
性能测试脚本
"""

import time
import tempfile
import os
from unittest.mock import patch, Mock
from datakit_sync import DatakitSync

def test_download_performance():
    """测试下载性能"""
    print("测试下载性能...")
    
    with patch('boto3.client'):
        sync = DatakitSync(
            endpoint_url="https://test-endpoint.com",
            access_key="test-key",
            secret_key="test-secret"
        )
    
    # 创建临时目录
    temp_dir = tempfile.mkdtemp()
    sync.local_dir = temp_dir
    
    # Mock下载
    with patch.object(sync, 'download_file') as mock_download:
        mock_download.return_value = True
        
        start_time = time.time()
        result = sync.download_all_packages()
        end_time = time.time()
        
        print(f"下载耗时: {end_time - start_time:.2f}秒")
        print(f"下载文件数: {len(result)}")
    
    # 清理
    os.rmdir(temp_dir)

def test_upload_performance():
    """测试上传性能"""
    print("测试上传性能...")
    
    with patch('boto3.client'):
        sync = DatakitSync(
            endpoint_url="https://test-endpoint.com",
            access_key="test-key",
            secret_key="test-secret"
        )
    
    # 创建临时目录和文件
    temp_dir = tempfile.mkdtemp()
    sync.local_dir = temp_dir
    
    # 创建测试文件
    test_files = {}
    for i in range(5):
        file_path = os.path.join(temp_dir, f"test_file_{i}.txt")
        with open(file_path, 'w') as f:
            f.write(f"test content {i}" * 1000)  # 创建大文件
        test_files[f"file_{i}"] = file_path
    
    # Mock上传
    with patch.object(sync, 'upload_file') as mock_upload:
        mock_upload.return_value = True
        
        start_time = time.time()
        result = sync.upload_all_packages(test_files)
        end_time = time.time()
        
        print(f"上传耗时: {end_time - start_time:.2f}秒")
        print(f"上传文件数: {len(test_files)}")
    
    # 清理
    shutil.rmtree(temp_dir)

if __name__ == "__main__":
    test_download_performance()
    test_upload_performance()
EOF
    
    # 运行性能测试
    python3 performance_test.py
    
    # 清理性能测试文件
    rm -f performance_test.py
    
    log_info "性能测试完成"
}

# 运行所有测试
run_all_tests() {
    log_info "运行所有测试..."
    
    # 检查Python环境
    check_python_environment
    
    # 安装测试依赖
    install_test_dependencies
    
    # 运行单元测试
    run_unit_tests
    
    # 运行pytest测试
    run_pytest_tests
    
    # 生成覆盖率报告
    generate_coverage_report
    
    # 运行性能测试
    run_performance_tests
    
    log_info "所有测试完成"
}

# 显示帮助信息
show_help() {
    echo "Datakit物料同步脚本测试运行脚本"
    echo
    echo "使用方法:"
    echo "  $0 [选项]"
    echo
    echo "选项:"
    echo "  --unit        运行单元测试"
    echo "  --pytest      运行pytest测试"
    echo "  --coverage    生成覆盖率报告"
    echo "  --performance 运行性能测试"
    echo "  --all         运行所有测试（默认）"
    echo "  --help        显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 --unit"
    echo "  $0 --coverage"
    echo "  $0 --all"
}

# 主函数
main() {
    case "${1:---all}" in
        --unit)
            check_python_environment
            install_test_dependencies
            run_unit_tests
            ;;
        --pytest)
            check_python_environment
            install_test_dependencies
            run_pytest_tests
            ;;
        --coverage)
            check_python_environment
            install_test_dependencies
            generate_coverage_report
            ;;
        --performance)
            check_python_environment
            install_test_dependencies
            run_performance_tests
            ;;
        --all)
            run_all_tests
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@" 