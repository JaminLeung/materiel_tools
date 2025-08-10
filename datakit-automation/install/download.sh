#!/bin/bash

#=================================================
# 步骤4: 下载安装包
#=================================================
# 功能: 下载Datakit安装包、验证
#=================================================

download_packages() {
    log_info "=== 步骤4: 下载安装包 ==="
    
    # 检查必需的工具
    if ! check_required_tools; then
        handle_error "DEPENDENCY_ERROR" "必需工具检查失败" "ERROR" "false"
        dataway_log "error" "必需工具检查失败"
        return 1
    fi
    
    # 准备安装目录
    if ! prepare_install_directory; then
        handle_error "FILE_ERROR" "准备安装目录失败" "ERROR" "false"
        dataway_log "error" "准备安装目录失败"
        return 1
    fi
    
    # 下载bundle文件
    if ! download_bundle_file; then
        handle_error "NETWORK_ERROR" "下载bundle文件失败" "ERROR" "false"
        dataway_log "error" "下载bundle文件失败"
        return 1
    fi
    
    # 安装工具
    if ! install_tools "$DATAKIT_INSTALL_DIR"; then
        handle_error "DEPENDENCY_ERROR" "安装工具失败" "ERROR" "false"
        dataway_log "error" "安装工具失败"
        return 1
    fi
    
    log_success "安装包下载完成"
    dataway_log "info" "安装包下载完成"
    return 0
}

# 准备安装目录
prepare_install_directory() {
    log_info "准备安装目录..."
    
    # 创建安装目录（如果不存在）
    if ! mkdir -p "$DATAKIT_INSTALL_DIR"; then
        handle_error "FILE_ERROR" "创建安装目录失败: $DATAKIT_INSTALL_DIR" "ERROR" "false"
        return 1
    fi
    
    log_success "安装目录准备完成: $DATAKIT_INSTALL_DIR"
    return 0
}

# 下载bundle文件
download_bundle_file() {
    log_info "下载bundle文件..."
    
    cd "$DATAKIT_INSTALL_DIR"
    
    # 下载已打包的bundle文件
    local bundle_name="datakit_bundle-linux-amd64-$DATAKIT_VERSION.tar.gz"
    local bundle_key="$S3_DATAKIT_DIR/$bundle_name"
    local md5_key="$S3_DATAKIT_DIR/$bundle_name.md5"
    
    log_info "下载bundle文件: $bundle_name"
    
    # 先下载MD5文件
    log_info "下载MD5文件: $bundle_name.md5"
    if ! download_from_s3_with_retry "$S3_BUCKET" "$md5_key" "./$bundle_name.md5"; then
        handle_error "NETWORK_ERROR" "下载bundle MD5文件失败" "ERROR" "false"
        return 1
    fi
    
    # 读取期望的MD5值
    local expected_md5=$(cat "./$bundle_name.md5")
    log_info "期望的MD5值: $expected_md5"
    
    # 检查本地是否已存在同名包且MD5值一致
    if [ -f "./$bundle_name" ]; then
        log_info "本地已存在同名包，进行MD5校验..."
        if verify_file_md5 "$bundle_name" "$expected_md5"; then
            log_success "本地包MD5校验通过，跳过下载"
            return 0
        else
            record_error "VALIDATION_ERROR" "本地包MD5校验失败，将重新下载" "WARNING"
            rm -f "./$bundle_name"
        fi
    fi
    
    # 下载bundle文件
    log_info "开始下载bundle文件..."
    if ! download_from_s3_with_retry "$S3_BUCKET" "$bundle_key" "./$bundle_name"; then
        handle_error "NETWORK_ERROR" "下载bundle文件失败" "ERROR" "false"
        return 1
    fi
    
    # 验证下载文件的MD5
    log_info "验证下载文件的MD5..."
    if ! verify_file_md5 "$bundle_name" "$expected_md5"; then
        handle_error "VALIDATION_ERROR" "Bundle文件MD5验证失败" "ERROR" "false"
        return 1
    fi
    
    log_success "Bundle文件下载和验证完成"
    return 0
} 