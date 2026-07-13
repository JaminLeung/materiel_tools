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
# API配置
# =============================================================================
CONFIG_UPDATE_OPS_API_URL="__REPLACE_ME__"
CONFIG_UPDATE_DATAWAY_URL="__REPLACE_ME__"
CONFIG_PY_FILE="${DATAKIT_CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}" 




# =============================================================================
# 预检配置
# =============================================================================
FINAL_CPU_USAGE_LIMIT=${FINAL_CPU_USAGE_LIMIT:-80}
FINAL_MEMORY_USAGE_LIMIT=${FINAL_MEMORY_USAGE_LIMIT:-80}

MIN_CPU_SIZE=${MIN_CPU_SIZE:-2}
MIN_MEMORY_SIZE=${MIN_MEMORY_SIZE:-2}
# =============================================================================
# 健康检查配置
# =============================================================================
CONFIG_UPDATE_HEALTH_CHECK_TIMEOUT="${CONFIG_UPDATE_HEALTH_CHECK_TIMEOUT:-10}"
CONFIG_UPDATE_HEALTH_CHECK_URL="http://localhost:9529/v1/ping"


# 业务配置
ACCOUNT_NAME="eu"
GLOBAL_ENV="pre"
GLOBAL_OPS_ENV="pre"
GLOBAL_SYSTEM="system"
CLOUD_PROVIDER="tencent"


# =============================================================================
# main_install.sh 特定配置
# =============================================================================
# S3配置
S3_REGION="${S3_REGION:-ap-southeast-1}"
S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ap-southeast-1.amazonaws.com}"
S3_ACCESS_KEY="__REPLACE_ME__"
S3_SECRET_KEY="__REPLACE_ME__"
S3_BUCKET="${S3_BUCKET:-benjamin--test}"
S3_DATAKIT_DIR="${S3_DATAKIT_DIR:-datakit}"

# Datakit版本和安装配置（覆盖base配置）


# 运维平台配置
OPS_ADDR="__REPLACE_ME__"

# Dataway配置
DATAWAY_URL="__REPLACE_ME__"
DATAWAY_FULL_URL="__REPLACE_ME__"
