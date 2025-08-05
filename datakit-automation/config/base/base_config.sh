#!/bin/bash

#=================================================
# Datakit 基础配置文件
#=================================================
# 包含脚本元信息和基础路径配置
#=================================================


DATAKIT_VERSION=1.78.0
S3_BUCKET=
S3_ACCESS_KEY=
DATAWAY_URL=https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82
OPS_ADDR=http://localhost:5000

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

# =============================================================================
# App Init 脚本配置
# =============================================================================
# 脚本基本信息
APP_INIT_SCRIPT_NAME="datakit_app_init"
APP_INIT_SCRIPT_VERSION="2.0.0"
APP_INIT_LOG_FILE="/opt/datakit/app_init.log"

# 运维平台配置
APP_INIT_CONFIG_PY_FILE="/usr/lib/zabbix/externalscripts/config.py"
APP_INIT_OPS_API_URL="${OPS_ADDR}/api/v2/cmdb/observation-metadata"
APP_INIT_DATAWAY_URL="https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82"

# Datakit配置目录
APP_INIT_LOGGING_DIR="/usr/local/datakit/conf.d/logging"
APP_INIT_METRICS_DIR="/usr/local/datakit/conf.d/prom"
APP_INIT_HEALTH_DIR="/usr/local/datakit/conf.d/host"

# 备份配置
APP_INIT_BACKUP_BASE_DIR="/opt/datakit/backup"
APP_INIT_BACKUP_DATE_DIR="${APP_INIT_BACKUP_BASE_DIR}/$(date +%Y%m%d)"
APP_INIT_BACKUP_APP_INIT_DIR="${APP_INIT_BACKUP_DATE_DIR}/app_init"

# 临时存储目录
APP_INIT_LOGGING_TMP_DIR="${APP_INIT_BACKUP_APP_INIT_DIR}/log"
APP_INIT_METRICS_TMP_DIR="${APP_INIT_BACKUP_APP_INIT_DIR}/prom"
APP_INIT_HEALTH_TMP_DIR="${APP_INIT_BACKUP_APP_INIT_DIR}/host"

# 前一次存储目录
APP_INIT_LOGGING_PREV_DIR="${APP_INIT_BACKUP_APP_INIT_DIR}/log_prev"
APP_INIT_METRICS_PREV_DIR="${APP_INIT_BACKUP_APP_INIT_DIR}/prom_prev"
APP_INIT_HEALTH_PREV_DIR="${APP_INIT_BACKUP_APP_INIT_DIR}/host_prev"

# 模板文件路径
APP_INIT_LOGGING_TEMPLATE="logging_template.conf"
APP_INIT_METRICS_TEMPLATE="metrics_template.conf"
APP_INIT_HEALTH_TEMPLATE="health_template.conf"

# API配置
APP_INIT_API_CONNECT_TIMEOUT="10"
APP_INIT_API_MAX_TIME="30"
APP_INIT_API_RANDOM_DELAY_MAX="60"

# 备份保留天数
APP_INIT_BACKUP_KEEP_DAYS="7"

# =============================================================================
# Health Check 脚本配置
# =============================================================================
# 脚本基本信息
HEALTH_CHECK_SCRIPT_NAME="datakit_health_check"
HEALTH_CHECK_SCRIPT_VERSION="2.0.0"
HEALTH_CHECK_LOG_FILE="/var/log/datakit/health_check.log"
HEALTH_CHECK_LOCK_FILE="/var/run/datakit_health_check.lock"
HEALTH_CHECK_FAILURE_COUNT_FILE="/var/run/datakit_health_check_failure_count"

# 健康检查配置
HEALTH_CHECK_MAX_FAILURE_COUNT="3"
HEALTH_CHECK_PING_TIMEOUT="10"
HEALTH_CHECK_PING_URL="http://localhost:9529/v1/ping"

# =============================================================================
# Cron Wrapper 脚本配置
# =============================================================================
# Config Update 任务配置
CONFIG_UPDATE_LOCK_FILE="/var/run/config_update.lock"
CONFIG_UPDATE_LOG_FILE="/var/log/datakit/config_update.log"
CONFIG_UPDATE_TASK_NAME="config_update.sh"

# Health Check 任务配置
HEALTH_CHECK_LOCK_FILE="/var/run/datakit_health_check.lock"
HEALTH_CHECK_LOG_FILE="/var/log/datakit/health_check.log"
HEALTH_CHECK_TASK_NAME="datakit_health_check.sh"

# App Init 任务配置
APP_INIT_LOCK_FILE="/var/run/app_init.lock"
APP_INIT_LOG_FILE="/var/log/datakit/app_init.log"
APP_INIT_TASK_NAME="app_init.sh"