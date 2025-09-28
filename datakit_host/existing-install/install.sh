#!/bin/bash

# Datakit自动化安装项目安装脚本

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

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "此脚本仅支持Linux系统"
        exit 1
    fi
    
    # 检查Python版本
    if ! command -v python3 &> /dev/null; then
        log_error "Python3未安装"
        exit 1
    fi
    
    local python_version=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
    if [[ $(echo "$python_version >= 3.6" | bc -l) -eq 0 ]]; then
        log_error "需要Python 3.6或更高版本，当前版本: $python_version"
        exit 1
    fi
    
    log_info "系统要求检查通过"
}

# 安装系统依赖
install_system_dependencies() {
    log_info "安装系统依赖..."
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y \
            curl \
            wget \
            git \
            bc \
            jq \
            yq \
            awscli \
            python3-pip \
            python3-venv
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        sudo yum update -y
        sudo yum install -y \
            curl \
            wget \
            git \
            bc \
            jq \
            yq \
            awscli \
            python3-pip \
            python3-venv
    elif command -v dnf &> /dev/null; then
        # Fedora
        sudo dnf update -y
        sudo dnf install -y \
            curl \
            wget \
            git \
            bc \
            jq \
            yq \
            awscli \
            python3-pip \
            python3-venv
    else
        log_error "不支持的包管理器"
        exit 1
    fi
    
    log_info "系统依赖安装完成"
}

# 安装Python依赖
install_python_dependencies() {
    log_info "安装Python依赖..."
    
    # 创建虚拟环境
    python3 -m venv venv
    source venv/bin/activate
    
    # 升级pip
    pip install --upgrade pip
    
    # 安装依赖
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    else
        # 安装基本依赖
        pip install boto3 requests PyYAML click colorlog
    fi
    
    log_info "Python依赖安装完成"
}

# 设置权限
setup_permissions() {
    log_info "设置脚本权限..."
    
    # 设置执行权限
    chmod +x resource_assessment/aws_resource_check.py
    chmod +x cgroup_check/verify_cgroup.sh
    chmod +x datakit_sync/datakit_sync.py
    chmod +x ssm_install/main_install.sh
    
    log_info "权限设置完成"
}

# 创建配置文件模板
create_config_template() {
    log_info "创建配置文件模板..."
    
    # 创建配置目录
    mkdir -p config
    
    # 创建AWS配置模板
    cat > config/aws_config.template << 'EOF'
# AWS配置模板
[AWS]
region = us-east-1
access_key = YOUR_ACCESS_KEY
secret_key = YOUR_SECRET_KEY

[S3]
endpoint_url = https://your-s3-endpoint.com
bucket_name = guance
datakit_dir = datakit

[Dataway]
url = https://dataway.prod-guance.houtai.io
token = YOUR_WORKSPACE_TOKEN

[OpsPlatform]
url = https://your-ops-platform.com
token = YOUR_OPS_TOKEN
EOF

    # 创建环境变量模板
    cat > config/env.template << 'EOF'
# 环境变量配置模板
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=AWS_ACCESS_KEY_ID_PLACEHOLDER
export AWS_SECRET_ACCESS_KEY=AWS_SECRET_ACCESS_KEY_PLACEHOLDER
export S3_ENDPOINT=https://your-s3-endpoint.com
export S3_ACCESS_KEY=YOUR_ACCESS_KEY
export S3_SECRET_KEY=YOUR_SECRET_KEY
export DATAWAY_URL=https://dataway.prod-guance.houtai.io
export WORKSPACE_TOKEN=YOUR_WORKSPACE_TOKEN
EOF

    log_info "配置文件模板创建完成"
}

# 创建使用示例
create_examples() {
    log_info "创建使用示例..."
    
    mkdir -p examples
    
    # 创建批量安装示例
    cat > examples/batch_install.sh << 'EOF'
#!/bin/bash

# 批量安装示例脚本

# 加载环境变量
source config/env.sh

# 1. 资源评估
echo "=== 步骤1: 资源评估 ==="
python3 resource_assessment/aws_resource_check.py \
    --region us-east-1 \
    --instance-ids i-1234567890abcdef0,i-0987654321fedcba0

# 2. 物料同步
echo "=== 步骤2: 物料同步 ==="
python3 datakit_sync/datakit_sync.py \
    --endpoint "$S3_ENDPOINT" \
    --access-key AWS_ACCESS_KEY_ID_PLACEHOLDER \
    --secret-key AWS_SECRET_ACCESS_KEY_PLACEHOLDER \
    --version 1.82.0

# 3. 批量安装
echo "=== 步骤3: 批量安装 ==="
aws ssm send-command \
    --instance-ids i-1234567890abcdef0,i-0987654321fedcba0 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["curl -s https://your-s3-endpoint.com/datakit/main_install.sh | bash"]'
EOF

    chmod +x examples/batch_install.sh
    
    log_info "使用示例创建完成"
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查Python脚本
    if ! python3 -c "import boto3, requests, yaml" 2>/dev/null; then
        log_error "Python依赖验证失败"
        return 1
    fi
    
    # 检查系统工具
    local tools=("curl" "jq" "yq" "aws" "bc")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "系统工具验证失败: $tool"
            return 1
        fi
    done
    
    # 检查脚本文件
    local scripts=(
        "resource_assessment/aws_resource_check.py"
        "cgroup_check/verify_cgroup.sh"
        "datakit_sync/datakit_sync.py"
        "ssm_install/main_install.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "脚本文件缺失: $script"
            return 1
        fi
    done
    
    log_info "安装验证通过"
    return 0
}

# 显示使用说明
show_usage() {
    echo
    log_info "=== 安装完成 ==="
    echo
    echo "项目已成功安装到当前目录。"
    echo
    echo "下一步操作："
    echo "1. 配置环境变量："
    echo "   cp config/env.template config/env.sh"
    echo "   vim config/env.sh"
    echo
    echo "2. 激活虚拟环境："
    echo "   source venv/bin/activate"
    echo
    echo "3. 运行示例："
    echo "   ./examples/batch_install.sh"
    echo
    echo "4. 查看文档："
    echo "   cat README.md"
    echo
    echo "项目结构："
    echo "├── resource_assessment/  # 资源评估模块"
    echo "├── cgroup_check/         # Cgroup检查模块"
    echo "├── datakit_sync/         # 物料同步模块"
    echo "├── ssm_install/          # SSM安装模块"
    echo "├── config/               # 配置文件"
    echo "├── examples/             # 使用示例"
    echo "└── venv/                 # Python虚拟环境"
    echo
}

# 主函数
main() {
    echo "=== Datakit自动化安装项目安装脚本 ==="
    echo
    
    # 检查系统要求
    check_system_requirements
    
    # 安装系统依赖
    install_system_dependencies
    
    # 安装Python依赖
    install_python_dependencies
    
    # 设置权限
    setup_permissions
    
    # 创建配置文件模板
    create_config_template
    
    # 创建使用示例
    create_examples
    
    # 验证安装
    if verify_installation; then
        show_usage
        log_info "项目安装完成！"
    else
        log_error "安装验证失败，请检查错误信息"
        exit 1
    fi
}

# 运行主函数
main "$@" 