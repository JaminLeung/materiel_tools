#!/bin/bash

#=================================================
# Health Check 脚本配置文件
#=================================================

# 加载基础配置（如果未加载）
if [ -z "${SCRIPT_NAME:-}" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../base/base_config.sh"
fi

# =============================================================================
# 脚本基本信息
# =============================================================================
HEALTH_CHECK_SCRIPT_NAME="datakit_health_check"
HEALTH_CHECK_SCRIPT_VERSION="2.0.0"
HEALTH_CHECK_LOG_FILE="/opt/datakit/health_check.log"
HEALTH_CHECK_FAILURE_COUNT_FILE="/var/run/datakit_health_check_failure_count"

# =============================================================================
# 健康检查配置
# =============================================================================
HEALTH_CHECK_MAX_FAILURE_COUNT="${HEALTH_CHECK_MAX_FAILURE_COUNT:-$HEALTH_CHECK_MAX_FAILURE_COUNT}"
HEALTH_CHECK_PING_TIMEOUT="${HEALTH_CHECK_PING_TIMEOUT:-$HEALTH_CHECK_TIMEOUT}"
HEALTH_CHECK_PING_URL="${HEALTH_CHECK_PING_URL:-$HEALTH_CHECK_URL}"

# =============================================================================
# 锁文件配置
# =============================================================================
HEALTH_CHECK_LOCK_FILE="$LOCK_FILE_BASE/datakit_health_check.lock"
HEALTH_CHECK_TASK_NAME="datakit_health_check.sh" 