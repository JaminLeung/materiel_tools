#!/bin/bash

# 测试AWS签名v4修复

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"
}

# 测试配置
S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
S3_BUCKET="benjamin--test"
S3_DATAKIT_DIR="datakit"
DATAKIT_VERSION="1.78.0"

# 生成AWS签名v4
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
    local canonical_request="$http_method\n$canonical_uri\n$canonical_querystring\n$canonical_headers\n\n$signed_headers\n$payload_hash"
    
    # 生成待签名字符串
    local date_stamp=$(echo "$timestamp" | cut -c1-8)
    local credential_scope="$date_stamp/$region/$service/aws4_request"
    local string_to_sign="AWS4-HMAC-SHA256\n$timestamp\n$credential_scope\n$(echo -e "$canonical_request" | sha256sum | cut -d' ' -f1)"
    
    # 生成签名密钥
    local k_date=$(echo -n "$timestamp" | openssl dgst -sha256 -hmac "AWS4$secret_key" -binary)
    local k_region=$(echo -n "$region" | openssl dgst -sha256 -hmac "$k_date" -binary)
    local k_service=$(echo -n "$service" | openssl dgst -sha256 -hmac "$k_region" -binary)
    local k_signing=$(echo -n "aws4_request" | openssl dgst -sha256 -hmac "$k_service" -binary)
    
    # 生成签名
    local signature=$(echo -e "$string_to_sign" | openssl dgst -sha256 -hmac "$k_signing" | cut -d' ' -f2)
    
    echo "$signature"
}

# 测试下载功能
test_download() {
    local test_file="$1"
    local test_key="$S3_DATAKIT_DIR/$test_file"
    local local_path="/tmp/test_$test_file"
    
    log_info "测试下载: $test_file"
    
    # 设置变量
    local http_method="GET"
    local canonical_uri="/$test_key"
    local canonical_querystring=""
    local timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    local date_stamp=$(date -u +%Y%m%d)
    local region="ap-southeast-1"
    local service="s3"
    local host="$S3_BUCKET.s3.$region.amazonaws.com"
    
    # 生成负载哈希（GET请求为空）
    local payload_hash=$(echo -n "" | sha256sum | cut -d' ' -f1)
    
    # 生成规范头部（包含x-amz-content-sha256）
    local canonical_headers="host:$host\nx-amz-content-sha256:$payload_hash\nx-amz-date:$timestamp\n"
    local signed_headers="host;x-amz-content-sha256;x-amz-date"
    
    # 生成签名
    local signature=$(generate_aws_signature_v4 "$http_method" "$canonical_uri" "$canonical_querystring" "$canonical_headers" "$signed_headers" "$payload_hash" "$timestamp" "$region" "$service" "$S3_ACCESS_KEY" "$S3_SECRET_KEY")
    
    # 生成授权头
    local authorization_header="AWS4-HMAC-SHA256 Credential=$S3_ACCESS_KEY/$date_stamp/$region/$service/aws4_request,SignedHeaders=$signed_headers,Signature=$signature"
    
    # 构建完整URL
    local s3_url="https://$host$canonical_uri"
    
    log_info "请求URL: $s3_url"
    
    # 使用curl下载
    if curl -L -o "$local_path" "$s3_url" \
        -H "Authorization: $authorization_header" \
        -H "x-amz-content-sha256: $payload_hash" \
        -H "x-amz-date: $timestamp" \
        --silent --show-error \
        --connect-timeout 30 --max-time 300; then
        
        # 检查文件大小，确保下载成功
        local file_size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path" 2>/dev/null)
        if [ "$file_size" -gt 0 ]; then
            # 检查是否是错误响应
            if head -c 100 "$local_path" | grep -q "<?xml"; then
                log_error "下载失败，收到错误响应:"
                cat "$local_path"
                rm -f "$local_path"
                return 1
            else
                log_success "文件下载成功: $local_path (${file_size} bytes)"
                rm -f "$local_path"
                return 0
            fi
        else
            log_error "下载的文件为空: $test_file"
            rm -f "$local_path"
            return 1
        fi
    else
        log_error "下载失败: $test_file"
        return 1
    fi
}

# 主测试函数
main() {
    log_info "开始测试AWS签名v4修复..."
    
    # 测试文件列表
    local test_files=(
        "jq"
        "datakit_bundle-linux-amd64-$DATAKIT_VERSION.tar.gz.md5"
    )
    
    local success_count=0
    local total_count=${#test_files[@]}
    
    for test_file in "${test_files[@]}"; do
        if test_download "$test_file"; then
            success_count=$((success_count + 1))
        fi
        echo "---"
    done
    
    # 显示测试结果
    log_info "测试完成: $success_count/$total_count 个文件下载成功"
    
    if [ "$success_count" -eq "$total_count" ]; then
        log_success "所有测试通过！AWS签名v4修复成功"
    else
        log_error "部分测试失败，请检查配置"
    fi
}

# 运行主测试
main "$@" 