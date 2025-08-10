#!/bin/bash

#=================================================
# 执行安装
#=================================================
# 功能: 解压安装包、安装Node Exporter和Datakit
#=================================================

install_components() {
    log_info "执行安装 ==="
    
    # 解压bundle文件
    if ! extract_bundle_file; then
        handle_error "FILE_ERROR" "解压bundle文件任务失败" "ERROR" "false"
        dataway_log "error" "解压bundle文件任务失败"
        return 1
    fi
    
    # 安装Node Exporter
    if ! install_node_exporter; then
        handle_error "DEPENDENCY_ERROR" "Node Exporter安装任务失败" "ERROR" "false"
        dataway_log "error" "Node Exporter安装任务失败"
    fi
    
    # 安装Datakit
    if ! install_datakit; then
        handle_error "DEPENDENCY_ERROR" "Datakit安装任务失败" "ERROR" "false"
        dataway_log "error" "Datakit安装任务失败"
        return 1
    fi
    
    log_success "组件安装完成"
    log_info "组件安装完成"
    return 0
}

# 解压bundle文件
extract_bundle_file() {
    log_info "解压bundle文件..."
    
    cd "$DATAKIT_INSTALL_DIR"
    
    local bundle_name="datakit_bundle-linux-amd64-$DATAKIT_VERSION.tar.gz"
    
    # 解压bundle文件
    if ! extract_package "$bundle_name" "."; then
        handle_error "FILE_ERROR" "解压bundle文件失败" "ERROR" "false"
        return 1
    fi
    
    # 检查解压后的文件
    local required_files=(
        "./installer-linux-amd64-$DATAKIT_VERSION"
        "./datakit-linux-amd64-$DATAKIT_VERSION.tar.gz"
        "./dk_upgrader-linux-amd64.tar.gz"
        "./data.tar.gz"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            handle_error "FILE_ERROR" "Bundle文件解压后缺少必要文件: $file" "ERROR" "false"
            return 1
        fi
    done
    
    log_success "Bundle文件解压完成，所有文件准备就绪"
    return 0
}

# 安装Node Exporter
install_node_exporter() {
    log_info "安装Node Exporter..."
    
    # 检查Node Exporter是否已安装
    if pgrep -x "node_exporter" >/dev/null; then
        log_info "Node Exporter进程已存在"
        return 0
    fi
    
    # 检查端口9100是否被占用
    if netstat -tlnp 2>/dev/null | grep -q ":9100 " || \
       ss -tlnp 2>/dev/null | grep -q ":9100 "; then
        record_error "SERVICE_ERROR" "端口9100已被占用，跳过Node Exporter安装" "WARNING"
        log_info "端口9100已被占用，跳过Node Exporter安装"
        return 0
    fi
    
    # 进入DATAKIT_INSTALL_DIR
    cd "$DATAKIT_INSTALL_DIR"
    
    # 检查Node Exporter安装包
    if [ ! -f "node_exporter-1.8.2.linux-amd64.tar.gz" ]; then
        record_error "FILE_ERROR" "Node Exporter安装包不存在，跳过安装" "WARNING"
        log_info "Node Exporter安装包不存在，跳过安装"
        return 0
    fi
    
    # 解压并安装
    if ! tar -xzf node_exporter-1.8.2.linux-amd64.tar.gz; then
        handle_error "FILE_ERROR" "解压Node Exporter失败" "ERROR" "false"
        return 1
    fi
    
    if ! cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/; then
        handle_error "FILE_ERROR" "复制Node Exporter失败" "ERROR" "false"
        return 1
    fi
    
    chmod +x /usr/local/bin/node_exporter
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl enable node_exporter
    
    if ! systemctl start node_exporter; then
        handle_error "SERVICE_ERROR" "启动Node Exporter服务失败" "ERROR" "false"
        return 1
    fi
    
    # 检查服务状态
    local check_count=0
    local max_checks=5
    
    while [ $check_count -lt $max_checks ]; do
        if systemctl is-active --quiet node_exporter; then
            log_success "Node Exporter安装成功"
            log_info "Node Exporter安装成功"
            return 0
        else
            check_count=$((check_count + 1))
            log_info "等待Node Exporter启动... ($check_count/$max_checks)"
            sleep 2
        fi
    done
    
    handle_error "SERVICE_ERROR" "Node Exporter启动失败" "ERROR" "false"
    dataway_log "error" "Node Exporter启动失败"
    return 1
}

# 安装Datakit
install_datakit() {
    log_info "安装Datakit..."
    
    # 判断DATAKIT_INSTALL_DIR是否存在
    if [ ! -d "$DATAKIT_INSTALL_DIR" ]; then
        handle_error "FILE_ERROR" "DATAKIT_INSTALL_DIR不存在" "ERROR" "false"
        dataway_log "error" "DATAKIT_INSTALL_DIR不存在"
        return 1
    fi
    
    cd "$DATAKIT_INSTALL_DIR"
    
    # 设置安装器权限
    chmod +x "./installer-linux-amd64-$DATAKIT_VERSION"
    
    # 获取Dataway地址
    local dataway_url=$(get_global_state 'DATAWAY_FULL_URL')
    if [ -z "$dataway_url" ]; then
        handle_error "CONFIG_ERROR" "Dataway地址未设置" "ERROR" "false"
        return 1
    fi
    
    # 执行离线安装
    log_info "执行Datakit离线安装..."
    log_info "执行Datakit离线安装..."
    
    if ! ./installer-linux-amd64-$DATAKIT_VERSION --offline --dataway "$dataway_url" --srcs "datakit-linux-amd64-$DATAKIT_VERSION.tar.gz,dk_upgrader-linux-amd64.tar.gz,data.tar.gz"; then
        handle_error "DEPENDENCY_ERROR" "Datakit安装失败" "ERROR" "false"
        dataway_log "error" "Datakit安装失败"
        return 1
    fi
    
    # 启动Datakit
    systemctl daemon-reload
    systemctl enable datakit
    
    if ! systemctl start datakit; then
        handle_error "SERVICE_ERROR" "启动Datakit服务失败" "ERROR" "false"
        return 1
    fi
    
    # 检查Datakit是否启动成功
    local check_count=0
    local max_checks=10
    
    while [ $check_count -lt $max_checks ]; do
        if systemctl is-active --quiet datakit; then
            log_success "Datakit启动成功"
            log_info "Datakit启动成功"
            return 0
        fi
        
        check_count=$((check_count + 1))
        log_info "等待Datakit启动... ($check_count/$max_checks)"
        sleep 5
    done
    
    handle_error "SERVICE_ERROR" "Datakit启动超时" "ERROR" "false"
    dataway_log "error" "Datakit启动超时"
    return 1
} 