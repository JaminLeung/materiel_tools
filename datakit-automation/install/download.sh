#!/bin/bash

#=================================================
# 下载模块
#=================================================
# 功能: S3文件下载、文件完整性验证、断点续传、下载进度显示
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
    local region="ap-southeast-1"
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
        --connect-timeout 30 --max-time 600; then
        
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

# 验证文件完整性
verify_file_integrity() {
    local file_path="$1"
    local expected_hash="$2"
    local hash_type="${3:-md5}"
    
    log_info "验证文件完整性: $file_path"
    
    local actual_hash
    case "$hash_type" in
        "md5")
            actual_hash=$(md5sum "$file_path" | awk '{print $1}')
            ;;
        "sha256")
            actual_hash=$(sha256sum "$file_path" | awk '{print $1}')
            ;;
        *)
            log_error "不支持的哈希类型: $hash_type"
            return 1
            ;;
    esac
    
    if [ "$expected_hash" = "$actual_hash" ]; then
        log_success "文件完整性验证通过"
        return 0
    else
        log_error "文件完整性验证失败: 期望=$expected_hash, 实际=$actual_hash"
        return 1
    fi
}

# 下载Datakit安装包
download_datakit_packages() {
    set_current_step "download_packages"
    log_info "=== 步骤1: 下载Datakit安装包 ==="
    
    local download_start_time=$(date +%s)
    
    # 创建备份
    if [ -d "${CONFIG[DATAKIT_INSTALL_DIR]}" ]; then
        log_info "安装目录已存在，创建备份"
        if ! create_backup "${CONFIG[DATAKIT_INSTALL_DIR]}" "datakit_install"; then
            log_warning "备份创建失败，继续执行"
        fi
    fi
    
    # 创建临时目录
    if ! retry_safe_execute "mkdir -p \"${CONFIG[DATAKIT_INSTALL_DIR]}\"" "创建安装目录"; then
        record_error "创建安装目录失败"
        return 1
    fi
    
    cd "${CONFIG[DATAKIT_INSTALL_DIR]}"

    # 下载已打包的bundle文件
    local bundle_name="datakit_bundle-linux-amd64-${CONFIG[DATAKIT_VERSION]}.tar.gz"
    local bundle_key="${CONFIG[S3_DATAKIT_DIR]}/$bundle_name"
    local md5_key="${CONFIG[S3_DATAKIT_DIR]}/$bundle_name.md5"

    log_info "下载bundle文件: $bundle_name"
    
    if [ -f "${CONFIG[DATAKIT_INSTALL_DIR]}/$bundle_name" ]; then
        log_info "bundle文件已存在，跳过下载"
    else
        # 下载bundle文件
        if ! retry_safe_execute "download_from_s3_with_curl \"${CONFIG[S3_BUCKET]}\" \"$bundle_key\" \"./$bundle_name\"" "下载bundle文件"; then
            record_error "下载bundle文件失败"
            return 1
        fi
    fi
    
    # 下载MD5文件
    if ! retry_safe_execute "download_from_s3_with_curl \"${CONFIG[S3_BUCKET]}\" \"$md5_key\" \"./$bundle_name.md5\"" "下载MD5文件"; then
        record_error "下载MD5文件失败"
        return 1
    fi
    
    # 验证MD5
    local expected_md5=$(cat "./$bundle_name.md5")
    if ! verify_file_integrity "$bundle_name" "$expected_md5" "md5"; then
        record_error "Bundle文件MD5验证失败"
        return 1
    fi
    
    # 解压bundle文件
    log_info "解压bundle文件..."
    if ! retry_safe_execute "tar -xzf \"$bundle_name\"" "解压bundle文件"; then
        record_error "解压bundle文件失败"
        return 1
    fi
    
    # 检查解压后的文件
    local required_files=(
        "./installer-linux-amd64-${CONFIG[DATAKIT_VERSION]}"
        "./datakit-linux-amd64-${CONFIG[DATAKIT_VERSION]}.tar.gz"
        "./dk_upgrader-linux-amd64.tar.gz"
        "./data.tar.gz"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            record_error "Bundle文件解压后缺少必要文件: $file"
            return 1
        fi
    done
    
    # 复制工具文件到系统目录
    if [ -f "./jq" ]; then
        if ! retry_safe_execute "cp ./jq /usr/local/bin/ && chmod +x /usr/local/bin/jq" "安装jq工具"; then
            log_warning "jq工具安装失败，但不影响主流程"
        else
            log_info "jq工具安装完成"
        fi
    fi
    
    if [ -f "./yj" ]; then
        if ! retry_safe_execute "cp ./yj /usr/local/bin/ && chmod +x /usr/local/bin/yj" "安装yj工具"; then
            log_warning "yj工具安装失败，但不影响主流程"
        else
            log_info "yj工具安装完成"
        fi
    fi
    
    # 记录下载时间
    local download_end_time=$(date +%s)
    PERFORMANCE_METRICS["DOWNLOAD_TIME"]=$((download_end_time - download_start_time))
    
    log_success "Bundle文件解压完成，所有文件准备就绪"
    dataway_log "info" "Bundle文件下载和解压完成"
    
    # 返回临时目录路径
    log_info "Datakit安装包下载完成，路径: ${CONFIG[DATAKIT_INSTALL_DIR]}"
    dataway_log "info" "Datakit安装包下载完成，路径: ${CONFIG[DATAKIT_INSTALL_DIR]}"
    return 0
}

# 配置AWS凭证
configure_aws_credentials() {
    log_info "配置AWS凭证..."
    
    # 创建AWS配置目录
    mkdir -p ~/.aws
    
    # 配置AWS凭证文件
    cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $S3_ACCESS_KEY
aws_secret_access_key = $S3_SECRET_KEY
EOF
    
    # 配置AWS配置文件
    cat > ~/.aws/config << EOF
[default]
region = ap-southeast-1
output = json
EOF
    
    # 设置权限
    chmod 600 ~/.aws/credentials
    chmod 600 ~/.aws/config
    
    log_success "AWS凭证配置完成"
} 