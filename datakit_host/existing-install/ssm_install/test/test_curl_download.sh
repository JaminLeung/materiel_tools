#!/bin/bash

# 测试curl下载S3文件功能

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

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"
}

# 测试配置
S3_ENDPOINT="https://s3.ap-southeast-1.amazonaws.com"
S3_BUCKET="benjamin--test"
S3_DATAKIT_DIR="datakit"
DATAKIT_VERSION="1.78.0"
S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"

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
    
    # 生成签名密钥
    local k_date=$(echo -n "$date_stamp" | openssl dgst -sha256 -hmac "AWS4$secret_key" -binary)
    local k_region=$(echo -n "$region" | openssl dgst -sha256 -hmac "$k_date" -binary)
    local k_service=$(echo -n "$service" | openssl dgst -sha256 -hmac "$k_region" -binary)
    local k_signing=$(echo -n "aws4_request" | openssl dgst -sha256 -hmac "$k_service" -binary)
    
    # 生成签名
    local signature=$(echo -e "$string_to_sign" | openssl dgst -sha256 -hmac "$k_signing" | cut -d' ' -f2)
    
    echo "$signature"
}

# 使用curl下载私有S3文件（AWS签名v4）
download_from_s3_with_curl() {
    local bucket="$1"
    local key="$2"
    local local_path="$3"
    
    log_info "使用curl从私有S3下载: $key"
    
    # 检查AWS凭证
    if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
        log_error "缺少AWS凭证，无法访问私有S3 bucket"
        return 1
    fi
    
    # 设置变量
    local http_method="GET"
    local canonical_uri="/$key"
    local canonical_querystring=""
    local timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    local date_stamp=$(date -u +%Y%m%d)
    local region="ap-southeast-1"
    local service="s3"
    local host="$bucket.s3.ap-southeast-1.amazonaws.com"
    
    # 生成负载哈希（GET请求为空）
    local payload_hash=$(echo -n "" | sha256sum | cut -d' ' -f1)
    
    # 生成规范头部（包含x-amz-content-sha256）
    local canonical_headers=$(printf "host:%s\nx-amz-content-sha256:%s\nx-amz-date:%s\n" \
        "$host" \
        "$payload_hash" \
        "$timestamp")
    local signed_headers="host;x-amz-content-sha256;x-amz-date"
    
    # 生成签名
    local signature=$(generate_aws_signature_v4 "$http_method" "$canonical_uri" "$canonical_querystring" "$canonical_headers" "$signed_headers" "$payload_hash" "$timestamp" "$region" "$service" "$S3_ACCESS_KEY" "$S3_SECRET_KEY")
    
    # 生成授权头
    local authorization_header="AWS4-HMAC-SHA256 Credential=$S3_ACCESS_KEY/$date_stamp/$region/$service/aws4_request,SignedHeaders=$signed_headers,Signature=$signature"
    
    # 构建完整URL
    local s3_url="https://$host$canonical_uri"
    
    log_info "下载URL: $s3_url"
    
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
            log_success "文件下载成功: $local_path (${file_size} bytes)"
            return 0
        else
            log_error "下载的文件为空: $key"
            return 1
        fi
    else
        log_error "下载失败: $key"
        return 1
    fi
}

# 测试下载功能
test_download() {
    local test_file="$1"
    local test_key="$S3_DATAKIT_DIR/$test_file"
    local local_path="/tmp/test_$test_file"
    
    log_info "开始测试下载: $test_file"
    
    if download_from_s3_with_curl "$S3_BUCKET" "$test_key" "$local_path"; then
        log_success "测试成功: $test_file"
        # 显示文件信息
        ls -la "$local_path"
        # 清理测试文件
        rm -f "$local_path"
        return 0
    else
        log_error "测试失败: $test_file"
        return 1
    fi
}

# 主测试函数
main() {
    log_info "开始测试curl下载S3文件功能..."
    
    # 创建测试目录
    local test_dir="/tmp/curl_download_test_$$"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    log_info "测试目录: $test_dir"
    
    # 测试文件列表
    local test_files=(
        "jq"
        "yj"
        "datakit_bundle-linux-amd64-$DATAKIT_VERSION.tar.gz"
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
        log_success "所有测试通过！"
    else
        log_warning "部分测试失败，请检查S3配置和网络连接"
    fi
    
    # 清理测试目录
    cd /
    rm -rf "$test_dir"
}

# 显示使用说明
show_usage() {
    echo "curl下载S3文件测试脚本"
    echo ""
    echo "用法: $0"
    echo ""
    echo "此脚本测试使用curl从私有S3下载文件的功能"
    echo "使用AWS签名v4认证访问私有S3 bucket"
    echo ""
    echo "测试文件:"
    echo "  - jq"
    echo "  - yj"
    echo "  - datakit_bundle-*.tar.gz"
    echo "  - datakit_bundle-*.tar.gz.md5"
    echo ""
    echo "注意: 需要配置正确的AWS凭证"
}

# 检查命令行参数
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# 运行主测试
main "$@" 