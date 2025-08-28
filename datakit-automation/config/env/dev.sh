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
CONFIG_UPDATE_OPS_API_URL="${CONFIG_UPDATE_OPS_API_URL:-http://localhost:5000/api/v2/cmdb/observation-agent}"
CONFIG_UPDATE_DATAWAY_URL="${CONFIG_UPDATE_DATAWAY_URL:-https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82}"
CONFIG_PY_FILE="${DATAKIT_CONFIG_PY_FILE:-/usr/lib/zabbix/externalscripts/config.py}" 

# =============================================================================
# 健康检查配置
# =============================================================================
CONFIG_UPDATE_HEALTH_CHECK_TIMEOUT="${CONFIG_UPDATE_HEALTH_CHECK_TIMEOUT:-10}"
CONFIG_UPDATE_HEALTH_CHECK_URL="http://localhost:9529/v1/ping"


# 业务配置
GLOBAL_CODE="local"
GLOBAL_ENV="dev"
GLOBAL_OPS_ENV="test"
GLOBAL_SYSTEM="system"

# =============================================================================
# main_install.sh 特定配置
# =============================================================================
# S3配置
S3_REGION="${S3_REGION:-ap-southeast-1}"
S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ap-southeast-1.amazonaws.com}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-xxxxxx}"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
S3_BUCKET="${S3_BUCKET:-benjamin--test}"
S3_DATAKIT_DIR="${S3_DATAKIT_DIR:-datakit}"

# Datakit版本和安装配置（覆盖base配置）


# 运维平台配置
OPS_ADDR="${OPS_ADDR:-http://172.31.16.4:5000}"

# Dataway配置
DATAWAY_URL="${DATAWAY_URL:-https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82}"


# runtime地址
RUNTIME_DIR="/var/log/datakit/runtime"