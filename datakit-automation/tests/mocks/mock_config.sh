#!/bin/bash

#=================================================
# 模拟配置文件
#=================================================
# 功能: 提供测试用的模拟配置数据
#=================================================

# 模拟环境变量
export MOCK_DATAKIT_VERSION="1.78.0"
export MOCK_S3_BUCKET="test-datakit-bucket"
export MOCK_S3_ACCESS_KEY="test-access-key"
export MOCK_S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
export MOCK_DATAWAY_URL="https://dataway.test.com"
export MOCK_OPS_ADDR="http://ops.test.com:5000"

# 模拟配置数组
declare -gA MOCK_CONFIG
MOCK_CONFIG[DATAKIT_VERSION]="$MOCK_DATAKIT_VERSION"
MOCK_CONFIG[S3_BUCKET]="$MOCK_S3_BUCKET"
MOCK_CONFIG[S3_ACCESS_KEY]="$MOCK_S3_ACCESS_KEY"
MOCK_CONFIG[S3_SECRET_KEY]="$MOCK_S3_SECRET_KEY"
MOCK_CONFIG[DATAWAY_URL]="$MOCK_DATAWAY_URL"
MOCK_CONFIG[OPS_ADDR]="$MOCK_OPS_ADDR"

# 模拟系统信息
export MOCK_SYSTEM_TYPE="Linux"
export MOCK_SYSTEM_VERSION="Ubuntu 20.04"
export MOCK_SYSTEM_ARCH="x86_64"
export MOCK_HOSTNAME="test-host"
export MOCK_USERNAME="test-user"

# 模拟网络信息
export MOCK_NETWORK_AVAILABLE="true"
export MOCK_DNS_WORKING="true"
export MOCK_S3_ACCESSIBLE="true"
export MOCK_DATAWAY_ACCESSIBLE="true"
export MOCK_OPS_ACCESSIBLE="true"

# 模拟系统资源
export MOCK_DISK_SPACE_AVAILABLE="1000000"  # KB
export MOCK_MEMORY_AVAILABLE="2000000"      # KB
export MOCK_CPU_LOAD="1.5"

# 模拟文件路径
export MOCK_INSTALL_DIR="/opt/datakit"
export MOCK_CONFIG_DIR="/etc/datakit"
export MOCK_LOG_DIR="/var/log/datakit"
export MOCK_BACKUP_DIR="/opt/datakit_backups"
export MOCK_PID_FILE="/var/run/datakit_install.pid"

# 模拟服务信息
export MOCK_SERVICE_NAME="datakit"
export MOCK_SERVICE_STATUS="inactive"
export MOCK_SERVICE_ENABLED="false"

# 模拟端口信息
export MOCK_PORT_9529_AVAILABLE="true"
export MOCK_PORT_9530_AVAILABLE="true"

# 模拟文件权限
export MOCK_FILE_READABLE="true"
export MOCK_FILE_WRITABLE="true"
export MOCK_FILE_EXECUTABLE="true"
export MOCK_DIR_READABLE="true"
export MOCK_DIR_WRITABLE="true"

# 模拟用户权限
export MOCK_USER_IS_ROOT="false"
export MOCK_USER_CAN_SUDO="true"

# 模拟命令可用性
export MOCK_COMMAND_CURL="true"
export MOCK_COMMAND_JQ="true"
export MOCK_COMMAND_SYSTEMCTL="true"
export MOCK_COMMAND_WGET="true"
export MOCK_COMMAND_TAR="true"
export MOCK_COMMAND_GUNZIP="true"

# 模拟下载信息
export MOCK_DOWNLOAD_URL="https://s3.test.com/datakit-1.78.0.tar.gz"
export MOCK_DOWNLOAD_SIZE="50000000"  # 50MB
export MOCK_DOWNLOAD_CHECKSUM="abc123def456"

# 模拟安装信息
export MOCK_INSTALL_SUCCESS="true"
export MOCK_INSTALL_TIME="30"  # 秒
export MOCK_CONFIG_SUCCESS="true"
export MOCK_SERVICE_START_SUCCESS="true"

# 模拟错误信息
export MOCK_ERROR_MESSAGE="模拟错误信息"
export MOCK_WARNING_MESSAGE="模拟警告信息"

# 加载模拟配置函数
load_mock_config() {
    local config_type="$1"
    
    case "$config_type" in
        "production")
            # 生产环境配置
            export DATAKIT_VERSION="$MOCK_DATAKIT_VERSION"
            export S3_BUCKET="$MOCK_S3_BUCKET"
            export S3_ACCESS_KEY="$MOCK_S3_ACCESS_KEY"
            export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
            export DATAWAY_URL="$MOCK_DATAWAY_URL"
            export OPS_ADDR="$MOCK_OPS_ADDR"
            ;;
        "development")
            # 开发环境配置
            export DATAKIT_VERSION="$MOCK_DATAKIT_VERSION"
            export S3_BUCKET="dev-$MOCK_S3_BUCKET"
            export S3_ACCESS_KEY="$MOCK_S3_ACCESS_KEY"
            export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
            export DATAWAY_URL="https://dev-dataway.test.com"
            export OPS_ADDR="http://dev-ops.test.com:5000"
            ;;
        "testing")
            # 测试环境配置
            export DATAKIT_VERSION="$MOCK_DATAKIT_VERSION"
            export S3_BUCKET="test-$MOCK_S3_BUCKET"
            export S3_ACCESS_KEY="$MOCK_S3_ACCESS_KEY"
            export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
            export DATAWAY_URL="https://test-dataway.test.com"
            export OPS_ADDR="http://test-ops.test.com:5000"
            ;;
        *)
            echo "未知的配置类型: $config_type"
            return 1
            ;;
    esac
    
    # 复制到CONFIG数组
    CONFIG[DATAKIT_VERSION]="$DATAKIT_VERSION"
    CONFIG[S3_BUCKET]="$S3_BUCKET"
    CONFIG[S3_ACCESS_KEY]="$S3_ACCESS_KEY"
    CONFIG[S3_SECRET_KEY]="$S3_SECRET_KEY"
    CONFIG[DATAWAY_URL]="$DATAWAY_URL"
    CONFIG[OPS_ADDR]="$OPS_ADDR"
}

# 清理模拟配置
cleanup_mock_config() {
    unset MOCK_DATAKIT_VERSION MOCK_S3_BUCKET MOCK_S3_ACCESS_KEY MOCK_S3_SECRET_KEY
    unset MOCK_DATAWAY_URL MOCK_OPS_ADDR
    unset MOCK_SYSTEM_TYPE MOCK_SYSTEM_VERSION MOCK_SYSTEM_ARCH
    unset MOCK_HOSTNAME MOCK_USERNAME
    unset MOCK_NETWORK_AVAILABLE MOCK_DNS_WORKING MOCK_S3_ACCESSIBLE
    unset MOCK_DATAWAY_ACCESSIBLE MOCK_OPS_ACCESSIBLE
    unset MOCK_DISK_SPACE_AVAILABLE MOCK_MEMORY_AVAILABLE MOCK_CPU_LOAD
    unset MOCK_INSTALL_DIR MOCK_CONFIG_DIR MOCK_LOG_DIR MOCK_BACKUP_DIR MOCK_PID_FILE
    unset MOCK_SERVICE_NAME MOCK_SERVICE_STATUS MOCK_SERVICE_ENABLED
    unset MOCK_PORT_9529_AVAILABLE MOCK_PORT_9530_AVAILABLE
    unset MOCK_FILE_READABLE MOCK_FILE_WRITABLE MOCK_FILE_EXECUTABLE
    unset MOCK_DIR_READABLE MOCK_DIR_WRITABLE
    unset MOCK_USER_IS_ROOT MOCK_USER_CAN_SUDO
    unset MOCK_COMMAND_CURL MOCK_COMMAND_JQ MOCK_COMMAND_SYSTEMCTL
    unset MOCK_COMMAND_WGET MOCK_COMMAND_TAR MOCK_COMMAND_GUNZIP
    unset MOCK_DOWNLOAD_URL MOCK_DOWNLOAD_SIZE MOCK_DOWNLOAD_CHECKSUM
    unset MOCK_INSTALL_SUCCESS MOCK_INSTALL_TIME MOCK_CONFIG_SUCCESS
    unset MOCK_SERVICE_START_SUCCESS MOCK_ERROR_MESSAGE MOCK_WARNING_MESSAGE
}

# 获取模拟配置信息
get_mock_config_info() {
    echo "=== 模拟配置信息 ==="
    echo "Datakit版本: $MOCK_DATAKIT_VERSION"
    echo "S3存储桶: $MOCK_S3_BUCKET"
    echo "Dataway地址: $MOCK_DATAWAY_URL"
    echo "运维平台地址: $MOCK_OPS_ADDR"
    echo "系统类型: $MOCK_SYSTEM_TYPE"
    echo "系统版本: $MOCK_SYSTEM_VERSION"
    echo "系统架构: $MOCK_SYSTEM_ARCH"
    echo "主机名: $MOCK_HOSTNAME"
    echo "用户名: $MOCK_USERNAME"
    echo "网络可用: $MOCK_NETWORK_AVAILABLE"
    echo "磁盘空间: ${MOCK_DISK_SPACE_AVAILABLE}KB"
    echo "可用内存: ${MOCK_MEMORY_AVAILABLE}KB"
    echo "CPU负载: $MOCK_CPU_LOAD"
    echo "=================="
} 