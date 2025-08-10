#!/bin/bash

# 验证当前时间戳的签名计算

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
OBJECT_KEY="datakit/datakit_bundle-linux-amd64-1.78.0.tar.gz"

# AWS期望的签名（从错误响应中获取）
AWS_EXPECTED_SIGNATURE="398e32b04673ddb273bdf63d6f0aaf5cc515724918d5d9b57e02176c29e06fd5"
AWS_EXPECTED_CANONICAL_HASH="b6061b7d8e20307cb90526397e78982243cf8ae93c3ded8f9721b0233c08e388"
TIMESTAMP="20250729T042251Z"

log_info "=== 验证当前时间戳的签名计算 ==="

# 使用修复后的签名生成函数
generate_aws_signature_v4() {
    local http_method="$1"
    local canonical_uri="$2"
    local canonical_querystring="$3"
    local canonical_headers="$4"
    local signed_headers="$5"
    local payload_hash="$6"
    local timestamp="$7"
    local region="$8"
    local service="$9"
    local access_key="${10}"
    local secret_key="${11}"
    
    # 生成规范请求
    local canonical_request=$(printf "%s\n%s\n%s\n%s\n\n%s\n%s" \
        "$http_method" \
        "$canonical_uri" \
        "$canonical_querystring" \
        "$canonical_headers" \
        "$signed_headers" \
        "$payload_hash")
    
    # 生成待签名字符串
    local date_stamp=$(echo "$timestamp" | cut -c1-8)
    local credential_scope="$date_stamp/$region/$service/aws4_request"
    local string_to_sign="AWS4-HMAC-SHA256\n$timestamp\n$credential_scope\n$(echo -n "$canonical_request" | sha256sum | cut -d' ' -f1)"
    
    # 生成签名密钥 - 修复HMAC密钥传递方式
    local k_date=$(echo -n "$date_stamp" | openssl dgst -sha256 -hmac "AWS4$secret_key" -binary)
    local k_region=$(echo -n "$region" | openssl dgst -sha256 -hmac "$k_date" -binary)
    local k_service=$(echo -n "$service" | openssl dgst -sha256 -hmac "$k_region" -binary)
    local k_signing=$(echo -n "aws4_request" | openssl dgst -sha256 -hmac "$k_service" -binary)
    
    # 生成签名
    local signature=$(echo -e "$string_to_sign" | openssl dgst -sha256 -hmac "$k_signing" | cut -d' ' -f2)
    
    echo "$signature"
}

# 使用AWS错误响应中的时间戳
DATE_STAMP="20250729"

# 构建请求参数
HTTP_METHOD="GET"
CANONICAL_URI="/$OBJECT_KEY"
CANONICAL_QUERYSTRING=""
HOST="$BUCKET.s3.$REGION.amazonaws.com"
PAYLOAD_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# 构建Canonical Headers
CANONICAL_HEADERS=$(printf "host:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\n" \
    "$HOST" \
    "$PAYLOAD_HASH" \
    "$TIMESTAMP")

SIGNED_HEADERS="host;x-amz-content-sha256;x-amz-date"

# 构建Canonical Request
CANONICAL_REQUEST=$(printf "%s\n%s\n%s\n%s\n\n%s\n%s" \
    "$HTTP_METHOD" \
    "$CANONICAL_URI" \
    "$CANONICAL_QUERYSTRING" \
    "$CANONICAL_HEADERS" \
    "$SIGNED_HEADERS" \
    "$PAYLOAD_HASH")

# 计算Canonical Request哈希
OUR_CANONICAL_HASH=$(printf "%s" "$CANONICAL_REQUEST" | sha256sum | awk '{print $1}')

log_info "=== Canonical Request 哈希对比 ==="
echo "AWS期望的哈希: $AWS_EXPECTED_CANONICAL_HASH"
echo "我们计算的哈希: $OUR_CANONICAL_HASH"

if [ "$AWS_EXPECTED_CANONICAL_HASH" = "$OUR_CANONICAL_HASH" ]; then
    log_info "✅ Canonical Request 哈希匹配！"
else
    log_error "❌ Canonical Request 哈希不匹配！"
    
    # 显示Canonical Request内容
    echo ""
    log_info "=== Canonical Request 内容 ==="
    echo "$CANONICAL_REQUEST" | hexdump -C
fi

# 生成签名
OUR_SIGNATURE=$(generate_aws_signature_v4 "$HTTP_METHOD" "$CANONICAL_URI" "$CANONICAL_QUERYSTRING" "$CANONICAL_HEADERS" "$SIGNED_HEADERS" "$PAYLOAD_HASH" "$TIMESTAMP" "$REGION" "s3" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY")

log_info "=== 签名对比 ==="
echo "AWS期望的签名: $AWS_EXPECTED_SIGNATURE"
echo "我们计算的签名: $OUR_SIGNATURE"

if [ "$AWS_EXPECTED_SIGNATURE" = "$OUR_SIGNATURE" ]; then
    log_info "✅ 签名匹配！"
else
    log_error "❌ 签名不匹配！"
fi 