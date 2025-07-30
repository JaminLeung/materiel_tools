#!/bin/bash

# 精确的规范请求测试

set -e

# 颜色定义
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_debug() {
    echo -e "${YELLOW}[DEBUG] $1${NC}"
}

# 测试配置
S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
S3_BUCKET="benjamin--test"
S3_REGION="ap-southeast-1"

# 测试精确的规范请求
test_exact_canonical() {
    local test_file="datakit/jq"
    
    log_debug "=== 测试精确的规范请求 ==="
    
    # 设置变量
    local http_method="GET"
    local canonical_uri="/$test_file"
    local canonical_querystring=""
    local timestamp="20250729T031800Z"
    local region="$S3_REGION"
    local service="s3"
    local host="$S3_BUCKET.s3.$region.amazonaws.com"
    
    # 生成负载哈希（GET请求为空）
    local payload_hash=$(echo -n "" | sha256sum | cut -d' ' -f1)
    
    # 生成规范头部
    local canonical_headers="host:$host\nx-amz-content-sha256:$payload_hash\nx-amz-date:$timestamp\n"
    local signed_headers="host;x-amz-content-sha256;x-amz-date"
    
    log_debug "HTTP方法: '$http_method'"
    log_debug "规范URI: '$canonical_uri'"
    log_debug "查询字符串: '$canonical_querystring'"
    log_debug "规范头部: '$canonical_headers'"
    log_debug "签名头部: '$signed_headers'"
    log_debug "负载哈希: '$payload_hash'"
    
    # 方法1: 使用printf构建规范请求
    local canonical_request1=$(printf "%s\n%s\n%s\n%s\n\n%s\n%s" \
        "$http_method" \
        "$canonical_uri" \
        "$canonical_querystring" \
        "$canonical_headers" \
        "$signed_headers" \
        "$payload_hash")
    
    log_debug "=== 方法1: printf构建的规范请求 ==="
    echo "$canonical_request1" | hexdump -C
    
    # 计算规范请求哈希
    local canonical_request_hash1=$(echo "$canonical_request1" | sha256sum | cut -d' ' -f1)
    log_debug "方法1哈希: $canonical_request_hash1"
    
    # 方法2: 使用echo -e构建规范请求
    local canonical_request2="$http_method\n$canonical_uri\n$canonical_querystring\n$canonical_headers\n\n$signed_headers\n$payload_hash"
    
    log_debug "=== 方法2: echo -e构建的规范请求 ==="
    echo -e "$canonical_request2" | hexdump -C
    
    # 计算规范请求哈希
    local canonical_request_hash2=$(echo -e "$canonical_request2" | sha256sum | cut -d' ' -f1)
    log_debug "方法2哈希: $canonical_request_hash2"
    
    # AWS期望的哈希
    local aws_expected="0badb03ba2850c8a301f04898ddbfe1b76a0615907f9408e91220688c0f60f68"
    
    log_debug "=== 比较结果 ==="
    log_debug "AWS期望的: $aws_expected"
    log_debug "方法1结果: $canonical_request_hash1"
    log_debug "方法2结果: $canonical_request_hash2"
    
    if [ "$canonical_request_hash1" = "$aws_expected" ]; then
        log_debug "✅ 方法1匹配！"
    else
        log_debug "❌ 方法1不匹配"
    fi
    
    if [ "$canonical_request_hash2" = "$aws_expected" ]; then
        log_debug "✅ 方法2匹配！"
    else
        log_debug "❌ 方法2不匹配"
    fi
}

# 运行测试
test_exact_canonical 