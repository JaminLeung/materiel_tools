#!/bin/bash

#=================================================
# Datakit 基础配置文件
#=================================================
# 包含脚本元信息和基础路径配置
#=================================================

# 脚本元信息
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="0.1.1"

# 基础路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$PROJECT_ROOT/modules"
CONFIG_DIR="$PROJECT_ROOT/config"
SCENARIO_DIR="$PROJECT_ROOT/scenario"

# 日志配置
LOG_FILE="${DATAKIT_LOG_FILE:-/var/log/datakit_install.log}"
LOG_LEVEL="${LOG_LEVEL:-1}"

# 安装路径配置（可被环境配置覆盖）
DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-/opt/datakit_install}"
DATAKIT_BIN_DIR="/usr/local/bin"
DATAKIT_CONFIG_DIR="/usr/local/datakit/conf.d"
DATAKIT_DATA_DIR="/usr/local/datakit/data"
DATAKIT_LOG_DIR="/var/log/datakit"

# =============================================================================
# 脚本配置
# =============================================================================
CONFIG_UPDATE_SCRIPT_NAME="datakit_config_update"
CONFIG_UPDATE_SCRIPT_VERSION="2.0.0"
CONFIG_UPDATE_LOG_FILE="/var/log/datakit_config_update.log"

# =============================================================================
# 路径配置
# =============================================================================
CONFIG_UPDATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
CONFIG_UPDATE_CORE_DIR="$(dirname "$CONFIG_UPDATE_SCRIPT_DIR")/core"
CONFIG_UPDATE_DATAKIT_CONF="/usr/local/datakit/conf.d/datakit.conf"
CONFIG_UPDATE_DATAKIT_CONF_DIR="/usr/local/datakit/conf.d"
CONFIG_UPDATE_HEALTH_CHECK_SCRIPT="$CONFIG_UPDATE_SCRIPT_DIR/datakit_health_check.sh"
CONFIG_UPDATE_BACKUP_BASE_DIR="$(dirname "$CONFIG_UPDATE_SCRIPT_DIR")/backup"
CONFIG_UPDATE_BACKUP_DATE_DIR="$CONFIG_UPDATE_BACKUP_BASE_DIR/$(date +%Y%m%d)"
CONFIG_UPDATE_BACKUP_DIR="$CONFIG_UPDATE_BACKUP_DATE_DIR/config_update"

# 外部脚本配置
CONFIG_PY_FILE="${DATAKIT_CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}" 

# =============================================================================
# 服务控制配置
# =============================================================================
CONFIG_UPDATE_SYSTEMD_SERVICE_NAME="datakit"
CONFIG_UPDATE_HEALTH_CHECK_SERVICE_NAME="datakit-health-check"

# =============================================================================
# 备份配置
# =============================================================================
CONFIG_UPDATE_BACKUP_RETENTION_DAYS="${CONFIG_UPDATE_BACKUP_RETENTION_DAYS:-7}"
CONFIG_UPDATE_BACKUP_TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"

# =============================================================================
# 配置处理配置
# =============================================================================
CONFIG_UPDATE_SAMPLE_FILE_SUFFIX=".sample"
CONFIG_UPDATE_BACKUP_FILE_SUFFIX=".backup"
CONFIG_UPDATE_DELETED_FILE_SUFFIX=".deleted"

# =============================================================================
# 日志配置
# =============================================================================
CONFIG_UPDATE_LOG_LEVEL="${CONFIG_UPDATE_LOG_LEVEL:-INFO}"
CONFIG_UPDATE_LOG_FORMAT="${CONFIG_UPDATE_LOG_FORMAT:-json}"

# =============================================================================
# 错误处理配置
# =============================================================================
CONFIG_UPDATE_MAX_RETRY_ATTEMPTS="${CONFIG_UPDATE_MAX_RETRY_ATTEMPTS:-3}"
CONFIG_UPDATE_COMMAND_TIMEOUT="${CONFIG_UPDATE_COMMAND_TIMEOUT:-30}"

# =============================================================================
# 验证配置
# =============================================================================
CONFIG_UPDATE_REQUIRED_COMMANDS="jq yj curl systemctl datakit"