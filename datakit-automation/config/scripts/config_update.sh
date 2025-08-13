#!/bin/bash

#=================================================
# Config Update 脚本配置文件
#=================================================

# 加载基础配置（如果未加载）
if [ -z "${SCRIPT_NAME:-}" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../base/base_config.sh"
fi

# =============================================================================
# 脚本基本信息
# =============================================================================
CONFIG_UPDATE_SCRIPT_NAME="datakit_config_update"
CONFIG_UPDATE_SCRIPT_VERSION="2.0.0"
CONFIG_UPDATE_LOG_FILE="${RUNTIME_LOG_DIR}/config_update.log"

# =============================================================================
# 路径配置
# =============================================================================
CONFIG_UPDATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
CONFIG_UPDATE_CORE_DIR="$(dirname "$CONFIG_UPDATE_SCRIPT_DIR")/core"
CONFIG_UPDATE_DATAKIT_CONF="/usr/local/datakit/conf.d/datakit.conf"
CONFIG_UPDATE_DATAKIT_CONF_DIR="/usr/local/datakit/conf.d"
CONFIG_UPDATE_HEALTH_CHECK_SCRIPT="$CONFIG_UPDATE_SCRIPT_DIR/datakit_health_check.sh"
CONFIG_UPDATE_TEMP_DIR="${RUNTIME_ROOT}/temp/config_update"
CONFIG_UPDATE_BACKUP_DIR="${CONFIG_UPDATE_TEMP_DIR}/backup"

# =============================================================================
# 服务控制配置
# =============================================================================
CONFIG_UPDATE_SYSTEMD_SERVICE_NAME="datakit"
CONFIG_UPDATE_HEALTH_CHECK_SERVICE_NAME="datakit-health-check"

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
CONFIG_UPDATE_MAX_RETRY_ATTEMPTS="${CONFIG_UPDATE_MAX_RETRY_ATTEMPTS:-$MAX_RETRY_ATTEMPTS}"
CONFIG_UPDATE_COMMAND_TIMEOUT="${CONFIG_UPDATE_COMMAND_TIMEOUT:-$COMMAND_TIMEOUT}"

# =============================================================================
# 验证配置
# =============================================================================
CONFIG_UPDATE_REQUIRED_COMMANDS="jq yj curl systemctl datakit"

# =============================================================================
# 锁文件配置
# =============================================================================
CONFIG_UPDATE_LOCK_FILE="$LOCK_FILE_BASE/config_update.lock"
CONFIG_UPDATE_TASK_NAME="config_update.sh" 