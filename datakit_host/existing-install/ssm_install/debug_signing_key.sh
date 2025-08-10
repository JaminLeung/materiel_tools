#!/bin/bash

# 调试签名密钥生成过程

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
DATE_STAMP="20250729"
REGION="ap-southeast-1"
SERVICE="s3"

# AWS期望的签名
AWS_EXPECTED_SIGNATURE="5cf2744b292fdebd2726fa5c3dc75ac8861de762f8a2e2e736bcf31cfe6614b4"

log_info "=== 签名密钥生成调试 ==="

# 1. 生成kSecret
kSecret="AWS4$AWS_SECRET_KEY"
log_info "kSecret: $kSecret"

# 2. 生成kDate
log_info "生成kDate..."
echo "输入: $DATE_STAMP"
kDate=$(printf "%s" "$DATE_STAMP" | openssl dgst -sha256 -hmac "$kSecret" -binary)
echo "kDate (hex): $(echo -n "$kDate" | hexdump -C)"

# 3. 生成kRegion
log_info "生成kRegion..."
echo "输入: $REGION"
echo "密钥: kDate"
kRegion=$(printf "%s" "$REGION" | openssl dgst -sha256 -mac HMAC -macopt key:- -binary <<<"$kDate")
echo "kRegion (hex): $(echo -n "$kRegion" | hexdump -C)"

# 4. 生成kService
log_info "生成kService..."
echo "输入: $SERVICE"
echo "密钥: kRegion"
kService=$(printf "%s" "$SERVICE" | openssl dgst -sha256 -mac HMAC -macopt key:- -binary <<<"$kRegion")
echo "kService (hex): $(echo -n "$kService" | hexdump -C)"

# 5. 生成kSigning
log_info "生成kSigning..."
echo "输入: aws4_request"
echo "密钥: kService"
kSigning=$(printf "%s" "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt key:- -binary <<<"$kService")
echo "kSigning (hex): $(echo -n "$kSigning" | hexdump -C)"

# 6. 测试String to Sign
STRING_TO_SIGN="AWS4-HMAC-SHA256
20250729T041833Z
20250729/ap-southeast-1/s3/aws4_request
4bc821ffd15acddc5455ece53b3afe153faf639aad67d7395cc39fe94ace9929"

log_info "String to Sign:"
echo "$STRING_TO_SIGN"

# 7. 生成最终签名
log_info "生成最终签名..."
OUR_SIGNATURE=$(printf "%s" "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt key:- | awk '{print $2}')

log_info "=== 签名对比 ==="
echo "AWS期望的签名: $AWS_EXPECTED_SIGNATURE"
echo "我们计算的签名: $OUR_SIGNATURE"

if [ "$AWS_EXPECTED_SIGNATURE" = "$OUR_SIGNATURE" ]; then
    log_info "✅ 签名匹配！"
else
    log_error "❌ 签名不匹配！"
    
    # 尝试不同的方法
    log_info "=== 尝试不同的签名方法 ==="
    
    # 方法1: 使用echo -e
    echo "方法1: 使用echo -e"
    SIG1=$(echo -e "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt key:- | awk '{print $2}')
    echo "结果: $SIG1"
    
    # 方法2: 使用printf
    echo "方法2: 使用printf"
    SIG2=$(printf "%s" "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt key:- | awk '{print $2}')
    echo "结果: $SIG2"
    
    # 方法3: 使用echo -n
    echo "方法3: 使用echo -n"
    SIG3=$(echo -n "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt key:- | awk '{print $2}')
    echo "结果: $SIG3"
fi 