#!/bin/bash

#=================================================
# Datakit 开发环境配置文件
#=================================================
# 包含开发环境特定的配置参数
#=================================================

# 加载基础配置
source "$(dirname "${BASH_SOURCE[0]}")/../base/base_config.sh"

# 开发环境配置
readonly LOCK_FILE="/tmp/datakit_install.lock"
readonly PID_FILE="/tmp/datakit_install.pid"
readonly BACKUP_DIR="/tmp/datakit_backups"
readonly MAX_BACKUP_COUNT=3
readonly MAX_RETRY_ATTEMPTS=2
readonly COMMAND_TIMEOUT=60
readonly HEALTH_CHECK_TIMEOUT=30
readonly DOWNLOAD_TIMEOUT=120
readonly INSTALL_TIMEOUT=180

# Datakit 版本配置
readonly DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"

# AWS S3 配置
readonly S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ap-southeast-1.amazonaws.com}"
readonly S3_ACCESS_KEY="${S3_ACCESS_KEY}"
readonly S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
readonly S3_BUCKET="${S3_BUCKET}"
readonly S3_DATAKIT_DIR="${S3_DATAKIT_DIR:-datakit}"

# Dataway 配置
readonly DATAWAY_URL="${DATAWAY_URL:-https://dataway.dev-guance.houtai.io}"

# 运维平台配置
readonly OPS_ADDR="${OPS_ADDR:-http://localhost:5000}"
readonly OPS_TOKEN="${OPS_TOKEN}"

# 资源限制配置
readonly ENABLE_CGROUP="${ENABLE_CGROUP:-false}"
readonly CPU_LIMIT_PERCENT="${CPU_LIMIT_PERCENT:-80}"
readonly MEMORY_LIMIT_PERCENT="${MEMORY_LIMIT_PERCENT:-80}" 