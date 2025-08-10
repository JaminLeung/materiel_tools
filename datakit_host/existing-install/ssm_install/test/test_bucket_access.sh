#!/bin/bash

# 简单的S3 bucket访问测试

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

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"
}

# 测试配置
S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
S3_BUCKET="benjamin--test"
S3_REGION="ap-southeast-1"

# 测试1: 检查bucket是否存在
test_bucket_exists() {
    log_info "测试1: 检查bucket是否存在"
    
    local host="$S3_BUCKET.s3.$S3_REGION.amazonaws.com"
    local url="https://$host/"
    
    log_info "请求URL: $url"
    
    # 使用简单的HEAD请求检查bucket
    local response=$(curl -I "$url" \
        --silent --show-error \
        --connect-timeout 30 --max-time 300 2>&1)
    
    log_info "响应: $response"
    
    if echo "$response" | grep -q "200 OK"; then
        log_info "Bucket存在且可访问"
        return 0
    elif echo "$response" | grep -q "403 Forbidden"; then
        log_error "Bucket存在但无权限访问"
        return 1
    elif echo "$response" | grep -q "404 Not Found"; then
        log_error "Bucket不存在"
        return 1
    else
        log_error "未知响应: $response"
        return 1
    fi
}

# 测试2: 列出bucket内容
test_list_bucket() {
    log_info "测试2: 列出bucket内容"
    
    local host="$S3_BUCKET.s3.$S3_REGION.amazonaws.com"
    local url="https://$host/?list-type=2"
    
    log_info "请求URL: $url"
    
    # 使用简单的GET请求列出内容
    local response=$(curl "$url" \
        --silent --show-error \
        --connect-timeout 30 --max-time 300 2>&1)
    
    log_info "响应: $response"
    
    if echo "$response" | grep -q "<?xml"; then
        log_info "成功获取bucket列表"
        return 0
    else
        log_error "获取bucket列表失败"
        return 1
    fi
}

# 测试3: 检查特定文件是否存在
test_file_exists() {
    local test_file="$1"
    log_info "测试3: 检查文件是否存在: $test_file"
    
    local host="$S3_BUCKET.s3.$S3_REGION.amazonaws.com"
    local url="https://$host/$test_file"
    
    log_info "请求URL: $url"
    
    # 使用HEAD请求检查文件
    local response=$(curl -I "$url" \
        --silent --show-error \
        --connect-timeout 30 --max-time 300 2>&1)
    
    log_info "响应: $response"
    
    if echo "$response" | grep -q "200 OK"; then
        log_info "文件存在"
        return 0
    elif echo "$response" | grep -q "404 Not Found"; then
        log_error "文件不存在"
        return 1
    else
        log_error "未知响应: $response"
        return 1
    fi
}

# 主测试函数
main() {
    log_info "开始S3 bucket访问测试..."
    
    # 测试bucket访问
    if test_bucket_exists; then
        log_info "Bucket访问测试通过"
    else
        log_error "Bucket访问测试失败"
        exit 1
    fi
    
    echo "---"
    
    # 测试列出bucket内容
    if test_list_bucket; then
        log_info "Bucket列表测试通过"
    else
        log_error "Bucket列表测试失败"
    fi
    
    echo "---"
    
    # 测试特定文件
    local test_files=(
        "datakit/jq"
        "datakit/datakit_bundle-linux-amd64-1.78.0.tar.gz"
        "datakit/datakit_bundle-linux-amd64-1.78.0.tar.gz.md5"
    )
    
    for test_file in "${test_files[@]}"; do
        if test_file_exists "$test_file"; then
            log_info "文件存在: $test_file"
        else
            log_error "文件不存在: $test_file"
        fi
        echo "---"
    done
}

# 运行主测试
main "$@" 