#!/bin/bash

#=================================================
# S3下载工具模块
#=================================================
# 功能: AWS S3文件下载、MD5验证、重试机制
#=================================================

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
    local region="eu-west-1"
    local service="s3"
    local host="$bucket.s3.$region.amazonaws.com"
    
    # 生成负载哈希（GET请求为空）
    local payload_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    
    # 构建Canonical Headers - 确保格式完全正确
    local canonical_headers="host:$host"$'\n'"x-amz-content-sha256:$payload_hash"$'\n'"x-amz-date:$timestamp"$'\n'
    local signed_headers="host;x-amz-content-sha256;x-amz-date"
    
    # 构建Canonical Request - 使用精确的换行符
    local canonical_request="$http_method"$'\n'"$canonical_uri"$'\n'"$canonical_querystring"$'\n'"$canonical_headers"$'\n'"$signed_headers"$'\n'"$payload_hash"
    
    # 计算Canonical Request哈希
    local canonical_request_hash=$(printf "%s" "$canonical_request" | sha256sum | awk '{print $1}')
    
    # 构建String to Sign
    local credential_scope="$date_stamp/$region/$service/aws4_request"
    local string_to_sign="AWS4-HMAC-SHA256"$'\n'"$timestamp"$'\n'"$credential_scope"$'\n'"$canonical_request_hash"
    
    # 生成签名密钥
    local kSecret="AWS4$S3_SECRET_KEY"
    local kDate=$(printf "%s" "$date_stamp" | openssl dgst -sha256 -hmac "$kSecret" -binary)
    local kRegion=$(printf "%s" "$region" | openssl dgst -sha256 -hmac "$kDate" -binary)
    local kService=$(printf "%s" "$service" | openssl dgst -sha256 -hmac "$kRegion" -binary)
    local kSigning=$(printf "%s" "aws4_request" | openssl dgst -sha256 -hmac "$kService" -binary)
    
    # 生成签名
    local signature=$(printf "%s" "$string_to_sign" | openssl dgst -sha256 -hmac "$kSigning" | awk '{print $2}')
    
    # 生成授权头
    local authorization_header="AWS4-HMAC-SHA256 Credential=$S3_ACCESS_KEY/$credential_scope,SignedHeaders=$signed_headers,Signature=$signature"
    
    # 构建完整URL
    local s3_url="https://$host$canonical_uri"
    
    # 使用curl下载（带进度条）
    log_info "开始下载文件..."
    if curl -L -o "$local_path" "$s3_url" \
        -H "Authorization: $authorization_header" \
        -H "x-amz-content-sha256: $payload_hash" \
        -H "x-amz-date: $timestamp" \
        --progress-bar \
        --connect-timeout 30 --max-time "$DOWNLOAD_TIMEOUT"; then
        
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

# 带重试的S3下载
download_from_s3_with_retry() {
    local bucket="$1"
    local key="$2"
    local local_path="$3"
    local max_attempts="${4:-$MAX_RETRY_ATTEMPTS}"
    local delay="${5:-$RETRY_DELAY}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "下载尝试 $attempt/$max_attempts: $key"
        
        if download_from_s3_with_curl "$bucket" "$key" "$local_path"; then
            log_success "下载成功: $key"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "下载失败，${delay}秒后重试..."
            sleep "$delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "下载失败，已尝试 $max_attempts 次: $key"
    return 1
}

# 验证文件MD5
verify_file_md5() {
    local file_path="$1"
    local expected_md5="$2"
    
    if [ ! -f "$file_path" ]; then
        log_error "文件不存在: $file_path"
        return 1
    fi
    
    local actual_md5=$(md5sum "$file_path" | awk '{print $1}')
    
    if [ "$expected_md5" = "$actual_md5" ]; then
        log_success "MD5验证成功: $file_path"
        return 0
    else
        log_error "MD5验证失败: $file_path"
        log_error "期望: $expected_md5"
        log_error "实际: $actual_md5"
        return 1
    fi
} 