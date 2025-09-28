#!/bin/bash

# 最终修复版本的下载脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1${NC}"
}

log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"
}

# 参数
AWS_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
AWS_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
BUCKET="benjamin--test"
REGION="ap-southeast-1"
OBJECT_KEY="datakit/datakit_bundle-linux-amd64-1.82.0.tar.gz"
LOCAL_FILE="./datakit_bundle-linux-amd64-1.82.0.tar.gz"

log_info "=== 最终修复版本下载测试 ==="

# 生成时间戳
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
DATE_STAMP=$(date -u +%Y%m%d)

log_info "使用时间戳: $TIMESTAMP"

# 构建请求参数
HTTP_METHOD="GET"
CANONICAL_URI="/$OBJECT_KEY"
CANONICAL_QUERYSTRING=""
HOST="$BUCKET.s3.$REGION.amazonaws.com"
PAYLOAD_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# 构建Canonical Headers - 确保格式完全正确
CANONICAL_HEADERS="host:$HOST"$'\n'"x-amz-content-sha256:$PAYLOAD_HASH"$'\n'"x-amz-date:$TIMESTAMP"$'\n'
SIGNED_HEADERS="host;x-amz-content-sha256;x-amz-date"

# 构建Canonical Request - 使用精确的换行符
CANONICAL_REQUEST="$HTTP_METHOD"$'\n'"$CANONICAL_URI"$'\n'"$CANONICAL_QUERYSTRING"$'\n'"$CANONICAL_HEADERS"$'\n'"$SIGNED_HEADERS"$'\n'"$PAYLOAD_HASH"

# 计算Canonical Request哈希
CANONICAL_REQUEST_HASH=$(printf "%s" "$CANONICAL_REQUEST" | sha256sum | awk '{print $1}')

log_info "Canonical Request哈希: $CANONICAL_REQUEST_HASH"

# 构建String to Sign
CREDENTIAL_SCOPE="$DATE_STAMP/$REGION/s3/aws4_request"
STRING_TO_SIGN="AWS4-HMAC-SHA256"$'\n'"$TIMESTAMP"$'\n'"$CREDENTIAL_SCOPE"$'\n'"$CANONICAL_REQUEST_HASH"

# 生成签名密钥
kSecret="AWS4$AWS_SECRET_KEY"
kDate=$(printf "%s" "$DATE_STAMP" | openssl dgst -sha256 -hmac "$kSecret" -binary)
kRegion=$(printf "%s" "$REGION" | openssl dgst -sha256 -hmac "$kDate" -binary)
kService=$(printf "%s" "s3" | openssl dgst -sha256 -hmac "$kRegion" -binary)
kSigning=$(printf "%s" "aws4_request" | openssl dgst -sha256 -hmac "$kService" -binary)

# 生成签名
SIGNATURE=$(printf "%s" "$STRING_TO_SIGN" | openssl dgst -sha256 -hmac "$kSigning" | awk '{print $2}')

log_info "计算的签名: $SIGNATURE"

# 构建Authorization header
AUTH_HEADER="AWS4-HMAC-SHA256 Credential=$AWS_ACCESS_KEY/$CREDENTIAL_SCOPE,SignedHeaders=$SIGNED_HEADERS,Signature=$SIGNATURE"

# 构建完整URL
S3_URL="https://$HOST$CANONICAL_URI"

log_info "请求URL: $S3_URL"

# 使用curl下载
log_info "开始下载..."

if curl -v -o "$LOCAL_FILE" "$S3_URL" \
    -H "Authorization: $AUTH_HEADER" \
    -H "x-amz-content-sha256: $PAYLOAD_HASH" \
    -H "x-amz-date: $TIMESTAMP" \
    --connect-timeout 30 --max-time 300 2>&1; then
    
    # 检查文件大小
    if [ -f "$LOCAL_FILE" ]; then
        FILE_SIZE=$(stat -c%s "$LOCAL_FILE" 2>/dev/null || stat -f%z "$LOCAL_FILE" 2>/dev/null)
        log_info "下载完成，文件大小: ${FILE_SIZE} bytes"
        
        # 检查文件类型
        FILE_TYPE=$(file "$LOCAL_FILE")
        log_info "文件类型: $FILE_TYPE"
        
        if [[ "$FILE_TYPE" == *"XML"* ]]; then
            log_error "下载的是XML错误响应，不是目标文件"
            head -5 "$LOCAL_FILE"
        else
            log_info "文件下载成功！"
        fi
    else
        log_error "文件下载失败"
    fi
else
    log_error "curl命令执行失败"
fi 