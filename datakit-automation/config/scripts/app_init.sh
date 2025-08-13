#!/bin/bash

#=================================================
# App Init 脚本配置文件
#=================================================

# 加载基础配置（如果未加载）
if [ -z "${SCRIPT_NAME:-}" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../base/base_config.sh"
fi

# =============================================================================
# 脚本基本信息
# =============================================================================
APP_INIT_SCRIPT_NAME="datakit_app_init"
APP_INIT_SCRIPT_VERSION="2.0.0"
APP_INIT_LOG_FILE="${RUNTIME_LOG_DIR}/app_init.log"

# =============================================================================
# 运维平台配置
# =============================================================================
APP_INIT_CONFIG_PY_FILE="$CONFIG_PY_FILE"
APP_INIT_OPS_API_URL="${OPS_ADDR}/api/v2/cmdb/observation-metadata"
APP_INIT_DATAWAY_URL="$DATAWAY_URL"

# =============================================================================
# Datakit配置目录
# =============================================================================
APP_INIT_LOGGING_DIR="/usr/local/datakit/conf.d/log"
APP_INIT_METRICS_DIR="/usr/local/datakit/conf.d/prom"
APP_INIT_HEALTH_DIR="/usr/local/datakit/conf.d/host"

# =============================================================================
# 运行时目录配置
# =============================================================================
# 临时目录始终放在 runtime/tmp 下
APP_INIT_TEMP_DIR="${RUNTIME_TMP_ROOT}/app_init"
APP_INIT_BACKUP_DIR="${APP_INIT_TEMP_DIR}/backup"

# 临时存储目录
APP_INIT_LOGGING_TMP_DIR="${APP_INIT_TEMP_DIR}/log"
APP_INIT_METRICS_TMP_DIR="${APP_INIT_TEMP_DIR}/prom"
APP_INIT_HEALTH_TMP_DIR="${APP_INIT_TEMP_DIR}/host"
# 前一次存储目录（放在 runtime/diff 下，独立于版本）
APP_INIT_LOGGING_PREV_DIR="${RUNTIME_DIFF_ROOT}/app_init/log_prev"
APP_INIT_METRICS_PREV_DIR="${RUNTIME_DIFF_ROOT}/app_init/prom_prev"
APP_INIT_HEALTH_PREV_DIR="${RUNTIME_DIFF_ROOT}/app_init/host_prev"

# =============================================================================
# 模板文件路径
# =============================================================================
APP_INIT_LOGGING_TEMPLATE="logging_template.conf"
APP_INIT_METRICS_TEMPLATE="metrics_template.conf"
APP_INIT_HEALTH_TEMPLATE="health_template.conf"

# =============================================================================
# API配置
# =============================================================================
APP_INIT_API_CONNECT_TIMEOUT="${APP_INIT_API_CONNECT_TIMEOUT:-10}"
APP_INIT_API_MAX_TIME="${APP_INIT_API_MAX_TIME:-30}"
APP_INIT_API_RANDOM_DELAY_MAX="${APP_INIT_API_RANDOM_DELAY_MAX:-60}"

# =============================================================================
# 备份保留天数
# =============================================================================
APP_INIT_BACKUP_KEEP_DAYS="${APP_INIT_BACKUP_KEEP_DAYS:-$BACKUP_RETENTION_DAYS}"

# =============================================================================
# 锁文件配置
# =============================================================================
APP_INIT_LOCK_FILE="$LOCK_FILE_BASE/app_init.lock"
APP_INIT_TASK_NAME="app_init.sh" 