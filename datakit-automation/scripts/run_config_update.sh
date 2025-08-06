#!/bin/bash

# Config Update 启动脚本
# 自动设置环境变量并运行config_update.sh

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 设置默认环境变量
export DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"
export S3_BUCKET="${S3_BUCKET:-benjamin--test}"
export S3_ACCESS_KEY="${S3_ACCESS_KEY:-AWS_ACCESS_KEY_ID_PLACEHOLDER}"
export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
export DATAWAY_URL="${DATAWAY_URL:-https://openway.guance.com?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82}"
export OPS_ADDR="${OPS_ADDR:-http://localhost:5000}"

echo "=== Config Update 启动脚本 ==="
echo "环境变量设置:"
echo "  DATAKIT_VERSION: $DATAKIT_VERSION"
echo "  S3_BUCKET: $S3_BUCKET"
echo "  S3_ACCESS_KEY: ${S3_ACCESS_KEY:0:10}..."
echo "  DATAWAY_URL: $DATAWAY_URL"
echo "  OPS_ADDR: $OPS_ADDR"
echo ""

# 运行config_update.sh
echo "开始执行 config_update.sh..."
"$SCRIPT_DIR/config_update.sh"

echo ""
echo "Config Update 执行完成" 