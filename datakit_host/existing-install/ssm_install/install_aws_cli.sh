#!/bin/bash

# AWS CLI安装脚本
# 自动下载并安装AWS CLI v2

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"
}

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "此脚本仅支持Linux系统"
        exit 1
    fi
    
    # 检查架构
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        log_error "此脚本仅支持x86_64架构，当前架构: $arch"
        exit 1
    fi
    
    # 检查必要工具
    local required_tools=("curl" "unzip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "缺少必要工具: $tool"
            exit 1
        fi
    done
    
    log_success "系统要求检查通过"
}

# 检查AWS CLI是否已安装
check_aws_cli_installed() {
    if command -v aws >/dev/null 2>&1; then
        local aws_version=$(aws --version 2>/dev/null | head -n1)
        log_info "AWS CLI已安装: $aws_version"
        
        # 询问是否重新安装
        read -p "是否要重新安装AWS CLI? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "跳过安装"
            exit 0
        fi
    fi
}

# 下载AWS CLI
download_aws_cli() {
    log_info "开始下载AWS CLI..."
    
    local aws_cli_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    local temp_dir="/tmp/aws_cli_install_$$"
    
    # 创建临时目录
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # 下载AWS CLI
    log_info "下载AWS CLI安装包..."
    if ! curl -L -o awscliv2.zip "$aws_cli_url"; then
        log_error "下载AWS CLI失败"
        cd /
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 验证下载文件
    local file_size=$(stat -c%s awscliv2.zip 2>/dev/null || stat -f%z awscliv2.zip 2>/dev/null)
    if [ "$file_size" -lt 1000000 ]; then  # 小于1MB可能是错误页面
        log_error "下载的文件大小异常: ${file_size} bytes"
        cd /
        rm -rf "$temp_dir"
        exit 1
    fi
    
    log_success "AWS CLI下载完成: ${file_size} bytes"
    
    # 解压安装包
    log_info "解压AWS CLI安装包..."
    if ! unzip -q awscliv2.zip; then
        log_error "解压AWS CLI失败"
        cd /
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 安装AWS CLI
    log_info "安装AWS CLI..."
    if ! ./aws/install --update; then
        log_error "安装AWS CLI失败"
        cd /
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 验证安装
    if command -v aws >/dev/null 2>&1; then
        local aws_version=$(aws --version 2>/dev/null | head -n1)
        log_success "AWS CLI安装成功: $aws_version"
    else
        log_error "AWS CLI安装验证失败"
        cd /
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 清理临时文件
    cd /
    rm -rf "$temp_dir"
    
    log_success "AWS CLI安装完成"
}

# 配置AWS CLI
configure_aws_cli() {
    log_info "配置AWS CLI..."
    
    # 创建配置目录
    mkdir -p ~/.aws
    
    # 检查是否已有配置
    if [ -f ~/.aws/credentials ] || [ -f ~/.aws/config ]; then
        log_warning "AWS配置文件已存在，跳过配置"
        return 0
    fi
    
    # 创建默认配置文件
    cat > ~/.aws/config << 'EOF'
[default]
region = us-east-1
output = json
EOF
    
    # 设置权限
    chmod 600 ~/.aws/config
    
    log_success "AWS CLI配置完成"
    log_info "请使用 'aws configure' 命令配置您的AWS凭证"
}

# 显示使用说明
show_usage() {
    echo "AWS CLI安装脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -c, --configure 安装后自动配置AWS CLI"
    echo ""
    echo "示例:"
    echo "  $0              # 仅安装AWS CLI"
    echo "  $0 --configure  # 安装并配置AWS CLI"
}

# 主函数
main() {
    local configure_only=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--configure)
                configure_only=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "开始AWS CLI安装流程..."
    
    # 检查系统要求
    check_system_requirements
    
    # 检查是否已安装
    check_aws_cli_installed
    
    # 下载并安装AWS CLI
    download_aws_cli
    
    # 配置AWS CLI
    configure_aws_cli
    
    log_success "AWS CLI安装和配置完成"
    log_info "使用 'aws --version' 验证安装"
    log_info "使用 'aws configure' 配置凭证"
}

# 运行主函数
main "$@" 