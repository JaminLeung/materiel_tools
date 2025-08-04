#!/bin/bash

#=================================================
# Datakit Benjamin 环境配置文件
#=================================================
# 包含 config_update.sh 脚本的配置参数
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
readonly CONFIG_UPDATE_LOG_FILE="/var/log/datakit_config_update.log"

# =============================================================================
# 路径配置
# =============================================================================
readonly CONFIG_UPDATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
readonly CONFIG_UPDATE_CORE_DIR="$(dirname "$CONFIG_UPDATE_SCRIPT_DIR")/core"
readonly CONFIG_UPDATE_DATAKIT_CONF="/usr/local/datakit/conf.d/datakit.conf"
readonly CONFIG_UPDATE_DATAKIT_CONF_DIR="/usr/local/datakit/conf.d"
readonly CONFIG_UPDATE_HEALTH_CHECK_SCRIPT="$CONFIG_UPDATE_SCRIPT_DIR/datakit_health_check.sh"
readonly CONFIG_UPDATE_BACKUP_BASE_DIR="$(dirname "$CONFIG_UPDATE_SCRIPT_DIR")/backup"
readonly CONFIG_UPDATE_BACKUP_DATE_DIR="$CONFIG_UPDATE_BACKUP_BASE_DIR/$(date +%Y%m%d)"
readonly CONFIG_UPDATE_BACKUP_DIR="$CONFIG_UPDATE_BACKUP_DATE_DIR/config_update"

# =============================================================================
# API配置
# =============================================================================
readonly CONFIG_UPDATE_OPS_API_URL="${CONFIG_UPDATE_OPS_API_URL:-http://localhost:5000/api/v2/cmdb/observation-agent}"
readonly CONFIG_UPDATE_DATAWAY_URL="${CONFIG_UPDATE_DATAWAY_URL:-https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82}"

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
# 健康检查配置
# =============================================================================
readonly CONFIG_UPDATE_HEALTH_CHECK_TIMEOUT="${CONFIG_UPDATE_HEALTH_CHECK_TIMEOUT:-10}"
readonly CONFIG_UPDATE_HEALTH_CHECK_URL="http://localhost:9529/v1/ping"

# =============================================================================
# 服务控制配置
# =============================================================================
readonly CONFIG_UPDATE_SYSTEMD_SERVICE_NAME="datakit"
readonly CONFIG_UPDATE_HEALTH_CHECK_SERVICE_NAME="datakit-health-check"

# =============================================================================
# 备份配置
# =============================================================================
readonly CONFIG_UPDATE_BACKUP_RETENTION_DAYS="${CONFIG_UPDATE_BACKUP_RETENTION_DAYS:-7}"
readonly CONFIG_UPDATE_BACKUP_TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"

# =============================================================================
# 配置处理配置
# =============================================================================
readonly CONFIG_UPDATE_SAMPLE_FILE_SUFFIX=".sample"
readonly CONFIG_UPDATE_BACKUP_FILE_SUFFIX=".backup"
readonly CONFIG_UPDATE_DELETED_FILE_SUFFIX=".deleted"

# =============================================================================
# 日志配置
# =============================================================================
readonly CONFIG_UPDATE_LOG_LEVEL="${CONFIG_UPDATE_LOG_LEVEL:-INFO}"
readonly CONFIG_UPDATE_LOG_FORMAT="${CONFIG_UPDATE_LOG_FORMAT:-json}"

# =============================================================================
# 错误处理配置
# =============================================================================
readonly CONFIG_UPDATE_MAX_RETRY_ATTEMPTS="${CONFIG_UPDATE_MAX_RETRY_ATTEMPTS:-3}"
readonly CONFIG_UPDATE_COMMAND_TIMEOUT="${CONFIG_UPDATE_COMMAND_TIMEOUT:-30}"

# =============================================================================
# 验证配置
# =============================================================================
readonly CONFIG_UPDATE_REQUIRED_COMMANDS="jq yj curl systemctl datakit"

# =============================================================================
# main_install.sh 特定配置
# =============================================================================
# S3配置
readonly S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ap-southeast-1.amazonaws.com}"
readonly S3_ACCESS_KEY="${S3_ACCESS_KEY:-AWS_ACCESS_KEY_ID_PLACEHOLDER}"
readonly S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
readonly S3_BUCKET="${S3_BUCKET:-benjamin-test}"
readonly S3_DATAKIT_DIR="${S3_DATAKIT_DIR:-datakit}"

# Datakit版本和安装配置（覆盖base配置）
readonly DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"
readonly DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-/opt/datakit_install}"

# 运维平台配置
readonly OPS_ADDR="${OPS_ADDR:-http://localhost:5000}"
readonly OPS_TOKEN="${OPS_TOKEN:-mock_token}"

# Dataway配置
readonly DATAWAY_URL="${DATAWAY_URL:-https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82}"
readonly DATAWAY_LOG_URL="${DATAWAY_LOG_URL:-https://openway.guance.com/v1/write/logging?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82}"

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