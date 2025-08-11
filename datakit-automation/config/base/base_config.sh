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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODULES_DIR="$PROJECT_ROOT/modules"
CONFIG_DIR="$PROJECT_ROOT/config"
SCENARIO_DIR="$PROJECT_ROOT/scenario"
WORKSPACE=default
ENV=test

# =============================================================================
# 安装路径配置（可被环境配置覆盖）
# =============================================================================
DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-/opt/datakit_install}"
DATAKIT_BIN_DIR="/usr/local/bin"
DATAKIT_CONFIG_DIR="/usr/local/datakit/conf.d"
DATAKIT_DATA_DIR="/usr/local/datakit/data"
DATAKIT_LOG_DIR="/var/log/datakit"

# =============================================================================
# 日志配置
# =============================================================================
LOG_FILE="${DATAKIT_LOG_FILE:-/var/log/datakit_install.log}"
LOG_LEVEL="${LOG_LEVEL:-1}"

# =============================================================================
# 外部脚本配置
# =============================================================================
CONFIG_PY_FILE="${DATAKIT_CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}"

# =============================================================================
# 通用配置
# =============================================================================
# 备份配置
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
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

