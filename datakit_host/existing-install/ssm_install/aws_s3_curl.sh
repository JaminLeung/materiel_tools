#!/bin/bash

# AWS S3 curl下载工具
# 使用AWS签名v4通过curl访问私有S3 bucket

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

log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"
}

# 默认配置
S3_ENDPOINT="https://s3.ap-southeast-1.amazonaws.com"
S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
S3_BUCKET="benjamin--test"
S3_REGION="ap-southeast-1"

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
    
    # 生成签名密钥 - 修复HMAC密钥传递方式
    local k_date=$(echo -n "$date_stamp" | openssl dgst -sha256 -hmac "AWS4$secret_key" -binary)
    local k_region=$(echo -n "$region" | openssl dgst -sha256 -hmac "$k_date" -binary)
    local k_service=$(echo -n "$service" | openssl dgst -sha256 -hmac "$k_region" -binary)
    local k_signing=$(echo -n "aws4_request" | openssl dgst -sha256 -hmac "$k_service" -binary)
    
    # 生成签名
    local signature=$(echo -e "$string_to_sign" | openssl dgst -sha256 -hmac "$k_signing" | cut -d' ' -f2)
    
    echo "$signature"
}

# 下载S3文件（不校验MD5）
# 参数: <bucket> <key> <local_path>
download_s3_file() {
    local bucket="$1"
    local key="$2"
    local local_path="$3"
    
    log_info "下载S3文件: s3://$bucket/$key -> $local_path"
    
    # 检查AWS凭证
    if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
        log_error "缺少AWS凭证，请设置S3_ACCESS_KEY和S3_SECRET_KEY"
        return 1
    fi
    
    # 设置变量
    local http_method="GET"
    local canonical_uri="/$key"
    local canonical_querystring=""
    local timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    local date_stamp=$(date -u +%Y%m%d)
    local region="$S3_REGION"
    local service="s3"
    local host="$bucket.s3.$region.amazonaws.com"
    
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
            log_info "文件下载成功: $local_path (${file_size} bytes)"
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

# 下载文件（不校验MD5）
download_and_verify_md5() {
    local bucket="$1"
    local key="$2"
    local local_path="$3"
    
    log_info "开始下载文件: s3://$bucket/$key"
    
    # 直接下载主文件，不进行MD5校验
    if download_s3_file "$bucket" "$key" "$local_path"; then
        log_info "文件下载完成: $local_path"
        return 0
    else
        log_error "文件下载失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo "AWS S3 curl下载工具"
    echo ""
    echo "用法: $0 [选项] download <bucket> <key> <local_path>"
    echo ""
    echo "功能:"
    echo "  下载指定的S3文件到本地"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -a, --access-key    AWS_ACCESS_KEY_ID_PLACEHOLDER Access Key"
    echo "  -s, --secret-key    AWS_SECRET_ACCESS_KEY_PLACEHOLDER Secret Key"
    echo "  -r, --region        设置AWS区域 (默认: ap-southeast-1)"
    echo ""
    echo "环境变量:"
    echo "  S3_ACCESS_KEY       AWS Access Key"
    echo "  S3_SECRET_KEY       AWS Secret Key"
    echo "  S3_REGION           AWS区域"
    echo ""
    echo "示例:"
    echo "  $0 download my-bucket path/to/file.txt /tmp/file.txt"
    echo "  S3_ACCESS_KEY=xxx S3_SECRET_KEY=yyy $0 download my-bucket file.txt /tmp/file.txt"
}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -a|--access-key)
                S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
                shift 2
                ;;
            -s|--secret-key)
                S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
                shift 2
                ;;
            -r|--region)
                S3_REGION="$2"
                shift 2
                ;;
            download)
                if [ $# -lt 4 ]; then
                    log_error "download命令需要3个参数: <bucket> <key> <local_path>"
                    exit 1
                fi
                download_and_verify_md5 "$2" "$3" "$4"
                exit $?
                ;;
            *)
                log_error "未知命令: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 如果没有命令，显示帮助
    show_usage
    exit 1
}

# 运行主函数
main "$@" 