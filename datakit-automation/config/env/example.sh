#!/bin/bash

#=================================================
# Datakit 环境配置文件模板
#=================================================
# 使用方法：复制此文件为具体环境的配置文件（如 production.sh, staging.sh）
# 并修改相应的配置值
#=================================================

# 加载基础配置（如果未加载）
if [ -z "${SCRIPT_NAME:-}" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../base/base_config.sh"
fi

# =============================================================================
# 脚本配置
# =============================================================================
readonly CONFIG_UPDATE_SCRIPT_NAME="datakit_config_update"
readonly CONFIG_UPDATE_SCRIPT_VERSION="2.0.0"


# =============================================================================
# 路径配置
# =============================================================================
readonly CONFIG_UPDATE_CORE_DIR="$(dirname "$CONFIG_UPDATE_SCRIPT_DIR")/core"
readonly CONFIG_UPDATE_DATAKIT_CONF="/usr/local/datakit/conf.d/datakit.conf"
readonly CONFIG_UPDATE_DATAKIT_CONF_DIR="/usr/local/datakit/conf.d"
readonly CONFIG_UPDATE_HEALTH_CHECK_SCRIPT="$CONFIG_UPDATE_SCRIPT_DIR/datakit_health_check.sh"
readonly CONFIG_UPDATE_BACKUP_BASE_DIR="$(dirname "$CONFIG_UPDATE_SCRIPT_DIR")/backup"
readonly CONFIG_UPDATE_BACKUP_DIR="$CONFIG_UPDATE_BACKUP_DATE_DIR/config_update"

# =============================================================================
# API配置
# =============================================================================
# 运维平台API地址
readonly CONFIG_UPDATE_OPS_API_URL="${CONFIG_UPDATE_OPS_API_URL:-http://localhost:5000/api/v2/cmdb/observation-agent}"
# Dataway地址
readonly DATAWAY_URL="${DATAWAY_URL:-https://openway.guance.com?token=YOUR_TOKEN_HERE}"

# =============================================================================
# 全局变量初始化
# =============================================================================
# 这些变量会在脚本执行过程中被设置
# HOST_IP=""
# ENV=""
# WORKSPACE=""
# DATAKIT_CONFIG=""
# CONFIG_CHANGED=false

# =============================================================================
# 服务控制配置
# =============================================================================

# =============================================================================
# 备份配置
# =============================================================================



# =============================================================================
# main_install.sh 特定配置
# =============================================================================

# S3配置
readonly S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ap-southeast-1.amazonaws.com}"
readonly S3_ACCESS_KEY="${S3_ACCESS_KEY:-YOUR_S3_ACCESS_KEY}"
readonly S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
readonly S3_BUCKET="${S3_BUCKET:-YOUR_S3_BUCKET_NAME}"
readonly S3_DATAKIT_DIR="${S3_DATAKIT_DIR:-datakit}"

# Datakit版本和安装配置（覆盖base配置）
readonly DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"
readonly DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-/opt/datakit_install}"

# 运维平台配置
readonly OPS_ADDR="${OPS_ADDR:-http://localhost:5000}"
readonly OPS_TOKEN="${OPS_TOKEN:-YOUR_OPS_TOKEN}"

# Dataway配置
readonly DATAWAY_URL="${DATAWAY_URL:-https://openway.guance.com?token=YOUR_DATAWAY_TOKEN}"
readonly DATAWAY_LOG_URL="${DATAWAY_LOG_URL:-https://openway.guance.com/v1/write/logging?token=YOUR_DATAWAY_TOKEN}"

# 资源限制配置
readonly CGROUP_CPU_LIMIT="${CGROUP_CPU_LIMIT:-}"
readonly CGROUP_MEMORY_LIMIT="${CGROUP_MEMORY_LIMIT:-}"

# 定时任务配置
readonly CRON_SCRIPT_DIR="${CRON_SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../scripts/cron_script}"

# 安装超时配置
readonly INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-600}"
readonly DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-300}"
readonly SERVICE_START_TIMEOUT="${SERVICE_START_TIMEOUT:-60}"

# 重试配置
readonly MAX_RETRY_ATTEMPTS="${MAX_RETRY_ATTEMPTS:-3}"
readonly RETRY_DELAY="${RETRY_DELAY:-5}"

# =============================================================================
# 环境特定配置（请根据实际环境修改）
# =============================================================================

# 环境标识
readonly ENV_NAME="${ENV_NAME:-example}"
readonly ENV_TYPE="${ENV_TYPE:-development}"

# 网络配置
# readonly PROXY_URL="${PROXY_URL:-}"
# readonly PROXY_USER="${PROXY_USER:-}"
# readonly PROXY_PASS="${PROXY_PASS:-}"

# 安全配置
# readonly ENABLE_SSL_VERIFY="${ENABLE_SSL_VERIFY:-true}"
# readonly SSL_CA_CERT="${SSL_CA_CERT:-}"

# 性能配置
# readonly DATAKIT_MAX_CPU="${DATAKIT_MAX_CPU:-}"
# readonly DATAKIT_MAX_MEMORY="${DATAKIT_MAX_MEMORY:-}"

echo "✅ 环境变量配置已加载 - 环境: $ENV_NAME ($ENV_TYPE)" 