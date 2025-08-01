#!/bin/bash

#=================================================
# Datakit 环境变量配置示例
#=================================================
# 使用方法：复制此文件为 env_config.sh 并修改值
#=================================================

# 基础路径配置
export DATAKIT_LOG_FILE="${DATAKIT_LOG_FILE:-/var/log/datakit_install.log}"
export DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-/opt/datakit_install}"
export LOG_LEVEL="${LOG_LEVEL:-1}"

# Datakit 版本配置
export DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"

# AWS S3 配置
export S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ap-southeast-1.amazonaws.com}"
export S3_ACCESS_KEY="${S3_ACCESS_KEY:-your_access_key_here}"
export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
export S3_BUCKET="${S3_BUCKET:-your_bucket_name}"
export S3_DATAKIT_DIR="${S3_DATAKIT_DIR:-datakit}"

# Dataway 配置
export DATAWAY_URL="${DATAWAY_URL:-https://dataway.prod-guance.houtai.io}"

# 运维平台配置
export OPS_ADDR="${OPS_ADDR:-http://localhost:5000}"
export OPS_TOKEN="${OPS_TOKEN:-your_ops_token_here}"

# 资源限制配置
export ENABLE_CGROUP="${ENABLE_CGROUP:-true}"
export CPU_LIMIT_PERCENT="${CPU_LIMIT_PERCENT:-50}"
export MEMORY_LIMIT_PERCENT="${MEMORY_LIMIT_PERCENT:-30}"


echo "✅ 环境变量配置已加载" 