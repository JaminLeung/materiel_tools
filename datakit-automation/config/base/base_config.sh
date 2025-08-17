#!/bin/bash

#=================================================
# Datakit 基础配置文件
#=================================================
# 包含脚本元信息和基础路径配置
#=================================================

# =============================================================================
# 脚本元信息
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="0.1.1"

# =============================================================================
# 基础路径配置
# =============================================================================
# 如果SCRIPT_DIR已经被定义为readonly，则使用不同的变量名
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
BASE_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 直接计算项目根目录
if [[ -n "${SCENARIO_PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$SCENARIO_PROJECT_ROOT"
else
    PROJECT_ROOT="$(cd "$BASE_CONFIG_DIR/../.." && pwd)"
fi
PROJECT_ROOT="$(cd "$BASE_CONFIG_DIR/../.." && pwd)"
MODULES_DIR="$PROJECT_ROOT/modules"
CONFIG_DIR="$PROJECT_ROOT/config"
RUNTIME_DIR="$PROJECT_ROOT/runtime"
WORKSPACE=default
ENV=test


set_global_state "RUNTIME_DIR" "$RUNTIME_DIR"
# =============================================================================
# 安装路径配置（可被环境配置覆盖）
# =============================================================================
DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-/opt/datakit_install}"
DATAKIT_BIN_DIR="/usr/local/bin"
DATAKIT_CONFIG_DIR="/usr/local/datakit/conf.d"
DATAKIT_DATA_DIR="/usr/local/datakit/data"
DATAKIT_LOG_DIR="/var/log/datakit"
DATAKIT_PID_FILE="/var/run/datakit_install.pid"

# =============================================================================
# 日志配置
# =============================================================================
RELEASE_ID="$(get_global_state "RELEASE_ID")"
DATAKIT_LOG_FILE=$RUNTIME_DIR/log/current/$RELEASE_ID.log
LOG_FILE="${DATAKIT_LOG_FILE:-/var/log/datakit_install.log}"
LOG_LEVEL="${LOG_LEVEL:-1}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-3}"
LOG_MAX_FILES_PER_SCRIPT="${LOG_MAX_FILES_PER_SCRIPT:-10}"

# =============================================================================
# Dataway日志上报配置
# =============================================================================
ENABLE_DATAWAY_LOG_REPORT="${ENABLE_DATAWAY_LOG_REPORT:-true}"
DATAWAY_LOG_BATCH_SIZE="${DATAWAY_LOG_BATCH_SIZE:-10}"
DATAWAY_LOG_TIMEOUT="${DATAWAY_LOG_TIMEOUT:-30}"

# =============================================================================
# Runtime目录配置
# =============================================================================
RUNTIME_ROOT="${RUNTIME_ROOT:-$PROJECT_ROOT/runtime}"
RUNTIME_LOG_DIR="${RUNTIME_LOG_DIR:-$RUNTIME_ROOT/log}"
RUNTIME_LOG_CURRENT_DIR="${RUNTIME_LOG_CURRENT_DIR:-$RUNTIME_LOG_DIR/current}"
RUNTIME_LOG_ARCHIVE_DIR="${RUNTIME_LOG_ARCHIVE_DIR:-$RUNTIME_LOG_DIR/archive}"
RUNTIME_RELEASES_DIR="${RUNTIME_RELEASES_DIR:-$RUNTIME_ROOT/releases}"

# Runtime清理配置
RUNTIME_MAX_RELEASES="${RUNTIME_MAX_RELEASES:-10}"


# =============================================================================
# 外部脚本配置
# =============================================================================
CONFIG_PY_FILE="${DATAKIT_CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}"

# =============================================================================
# 通用配置
# =============================================================================
# 备份配置
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_MAX_FILES="${BACKUP_MAX_FILES:-10}"
BACKUP_TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"

# 错误处理配置
MAX_RETRY_ATTEMPTS="${MAX_RETRY_ATTEMPTS:-3}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-30}"

# 健康检查配置
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"
HEALTH_CHECK_URL="http://localhost:9529/v1/ping"
HEALTH_CHECK_MAX_FAILURE_COUNT="${HEALTH_CHECK_MAX_FAILURE_COUNT:-3}"

# 锁文件基础路径
LOCK_FILE_BASE="/var/run"

