#!/bin/bash

# 调试AWS签名对比脚本
# 基于AWS错误响应中的信息进行对比

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

# AWS提供的错误信息
AWS_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
AWS_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
BUCKET="benjamin--test"
REGION="ap-southeast-1"
OBJECT_KEY="datakit/datakit_bundle-linux-amd64-1.82.0.tar.gz"

# AWS提供的期望值
AWS_EXPECTED_CANONICAL_HASH="4bc821ffd15acddc5455ece53b3afe153faf639aad67d7395cc39fe94ace9929"
AWS_EXPECTED_STRING_TO_SIGN="AWS4-HMAC-SHA256
20250729T041833Z
20250729/ap-southeast-1/s3/aws4_request
4bc821ffd15acddc5455ece53b3afe153faf639aad67d7395cc39fe94ace9929"

# AWS提供的Canonical Request
AWS_EXPECTED_CANONICAL_REQUEST="GET
/datakit/datakit_bundle-linux-amd64-1.82.0.tar.gz

host:benjamin--test.s3.ap-southeast-1.amazonaws.com
x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date:20250729T041833Z

host;x-amz-content-sha256;x-amz-date
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

log_info "=== AWS签名对比调试 ==="

# 1. 使用AWS提供的时间戳
TIMESTAMP="20250729T041833Z"
DATE_STAMP="20250729"

log_info "使用AWS提供的时间戳: $TIMESTAMP"

# 2. 构建我们的Canonical Request
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
OUR_CANONICAL_REQUEST=$(printf "%s\n%s\n%s\n%s\n\n%s\n%s" \
    "$HTTP_METHOD" \
    "$CANONICAL_URI" \
    "$CANONICAL_QUERYSTRING" \
    "$CANONICAL_HEADERS" \
    "$SIGNED_HEADERS" \
    "$PAYLOAD_HASH")

# 3. 计算我们的Canonical Request哈希
OUR_CANONICAL_HASH=$(printf "%s" "$OUR_CANONICAL_REQUEST" | sha256sum | awk '{print $1}')

log_info "=== Canonical Request 对比 ==="
echo "AWS期望的Canonical Request:"
echo "$AWS_EXPECTED_CANONICAL_REQUEST"
echo ""
echo "我们计算的Canonical Request:"
echo "$OUR_CANONICAL_REQUEST"
echo ""

log_info "=== Canonical Request 哈希对比 ==="
echo "AWS期望的哈希: $AWS_EXPECTED_CANONICAL_HASH"
echo "我们计算的哈希: $OUR_CANONICAL_HASH"

if [ "$AWS_EXPECTED_CANONICAL_HASH" = "$OUR_CANONICAL_HASH" ]; then
    log_info "✅ Canonical Request 哈希匹配！"
else
    log_error "❌ Canonical Request 哈希不匹配！"
    
    # 使用hexdump对比字节差异
    echo ""
    log_info "=== 字节级对比 ==="
    echo "AWS期望的Canonical Request字节:"
    echo "$AWS_EXPECTED_CANONICAL_REQUEST" | hexdump -C
    echo ""
    echo "我们计算的Canonical Request字节:"
    echo "$OUR_CANONICAL_REQUEST" | hexdump -C
fi

# 4. 构建String to Sign
CREDENTIAL_SCOPE="$DATE_STAMP/$REGION/s3/aws4_request"
OUR_STRING_TO_SIGN=$(printf "AWS4-HMAC-SHA256\n%s\n%s\n%s" \
    "$TIMESTAMP" \
    "$CREDENTIAL_SCOPE" \
    "$OUR_CANONICAL_HASH")

log_info "=== String to Sign 对比 ==="
echo "AWS期望的String to Sign:"
echo "$AWS_EXPECTED_STRING_TO_SIGN"
echo ""
echo "我们计算的String to Sign:"
echo "$OUR_STRING_TO_SIGN"

# 5. 生成签名密钥
kSecret="AWS4$AWS_SECRET_KEY"
kDate=$(printf "%s" "$DATE_STAMP" | openssl dgst -sha256 -hmac "$kSecret" -binary)
kRegion=$(printf "%s" "$REGION" | openssl dgst -sha256 -mac HMAC -macopt key:- -binary <<<"$kDate")
kService=$(printf "%s" "s3" | openssl dgst -sha256 -mac HMAC -macopt key:- -binary <<<"$kRegion")
kSigning=$(printf "%s" "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt key:- -binary <<<"$kService")

# 6. 生成签名
OUR_SIGNATURE=$(printf "%s" "$OUR_STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt key:- | awk '{print $2}')

log_info "=== 最终签名 ==="
echo "我们计算的签名: $OUR_SIGNATURE"

# 7. 构建Authorization header
AUTH_HEADER="AWS4-HMAC-SHA256 Credential=$AWS_ACCESS_KEY/$CREDENTIAL_SCOPE,SignedHeaders=$SIGNED_HEADERS,Signature=$OUR_SIGNATURE"

log_info "=== Authorization Header ==="
echo "$AUTH_HEADER" 