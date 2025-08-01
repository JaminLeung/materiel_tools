#!/bin/bash

#=================================================
# Datakit 生产环境配置文件
#=================================================
# 包含生产环境特定的配置参数
#=================================================

# 加载基础配置
source "$(dirname "${BASH_SOURCE[0]}")/../base/base_config.sh"

# 生产环境配置
readonly LOCK_FILE="/var/run/datakit_install.lock"
readonly PID_FILE="/var/run/datakit_install.pid"
readonly BACKUP_DIR="/opt/datakit_backups"
readonly MAX_BACKUP_COUNT=5
readonly MAX_RETRY_ATTEMPTS=3
readonly COMMAND_TIMEOUT=300
readonly HEALTH_CHECK_TIMEOUT=60
readonly DOWNLOAD_TIMEOUT=600
readonly INSTALL_TIMEOUT=900

# Datakit 版本配置
readonly DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"

# AWS S3 配置
readonly S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ap-southeast-1.amazonaws.com}"
readonly S3_ACCESS_KEY="${S3_ACCESS_KEY}"
readonly S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
readonly S3_BUCKET="${S3_BUCKET}"
readonly S3_DATAKIT_DIR="${S3_DATAKIT_DIR:-datakit}"

# Dataway 配置
readonly DATAWAY_URL="${DATAWAY_URL:-https://dataway.prod-guance.houtai.io}"

# 运维平台配置
readonly OPS_ADDR="${OPS_ADDR:-http://localhost:5000}"
readonly OPS_TOKEN="${OPS_TOKEN}"

# 资源限制配置
readonly ENABLE_CGROUP="${ENABLE_CGROUP:-true}"
readonly CPU_LIMIT_PERCENT="${CPU_LIMIT_PERCENT:-50}"
readonly MEMORY_LIMIT_PERCENT="${MEMORY_LIMIT_PERCENT:-30}" 