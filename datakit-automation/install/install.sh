#!/bin/bash

#=================================================
# 安装模块
#=================================================
# 功能: Datakit安装、Node Exporter安装、服务配置、权限设置
#=================================================

# 安装Node Exporter
install_node_exporter() {
    log_info "=== 步骤2: 安装Node Exporter ==="
    
    # 检查Node Exporter是否已安装
    if process_running "node_exporter"; then
        log_info "Node Exporter进程已存在"
        return 0
    fi
    
    # 检查端口9100是否被占用
    if port_listening "9100"; then
        log_warning "端口9100已被占用，跳过Node Exporter安装"
        dataway_log "info" "端口9100已被占用，跳过Node Exporter安装"
        return 0
    fi
    
    # 进入安装目录
    cd "${CONFIG[DATAKIT_INSTALL_DIR]}"   
    
    # 解压并安装
    if ! safe_execute "tar -xzf node_exporter-1.8.2.linux-amd64.tar.gz" "解压Node Exporter"; then
        return 1
    fi
    
    if ! safe_execute "cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/" "复制Node Exporter二进制文件"; then
        return 1
    fi
    
    if ! safe_execute "chmod +x /usr/local/bin/node_exporter" "设置Node Exporter执行权限"; then
        return 1
    fi
    
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
    if ! safe_execute "systemctl daemon-reload" "重新加载systemd配置"; then
        return 1
    fi
    
    if ! safe_execute "systemctl enable node_exporter" "启用Node Exporter服务"; then
        return 1
    fi
    
    if ! safe_execute "systemctl start node_exporter" "启动Node Exporter服务"; then
        return 1
    fi
    
    # 检查服务状态
    if retry_execute "systemctl is-active --quiet node_exporter" 5 2 "检查Node Exporter服务状态"; then
        log_success "Node Exporter安装成功"
        dataway_log "info" "Node Exporter安装成功"
        return 0
    else
        log_error "Node Exporter启动失败"
        dataway_log "error" "Node Exporter启动失败"
        return 1
    fi
}

# 安装Datakit
install_datakit() {
    log_info "=== 步骤3: 安装Datakit ==="
    
    # 判断安装目录是否存在
    if [ ! -d "${CONFIG[DATAKIT_INSTALL_DIR]}" ]; then
        log_error "安装目录不存在: ${CONFIG[DATAKIT_INSTALL_DIR]}"
        dataway_log "error" "安装目录不存在"
        return 1
    fi
    
    cd "${CONFIG[DATAKIT_INSTALL_DIR]}"
    
    # 设置安装器权限
    if ! safe_execute "chmod +x \"./installer-linux-amd64-${CONFIG[DATAKIT_VERSION]}\"" "设置安装器执行权限"; then
        return 1
    fi
    
    # 执行离线安装
    log_info "执行Datakit离线安装..."
    local dataway_url=$(get_global_state 'DATAWAY_FULL_URL')
    
    if ! safe_execute "./installer-linux-amd64-${CONFIG[DATAKIT_VERSION]} --offline --dataway \"$dataway_url\" --srcs \"datakit-linux-amd64-${CONFIG[DATAKIT_VERSION]}.tar.gz,dk_upgrader-linux-amd64.tar.gz,data.tar.gz\"" "执行Datakit离线安装"; then
        log_error "Datakit安装失败"
        dataway_log "error" "Datakit安装失败"
        return 1    
    fi
    
    # 启动Datakit服务
    if ! safe_execute "systemctl daemon-reload" "重新加载systemd配置"; then
        return 1
    fi
    
    if ! safe_execute "systemctl enable datakit" "启用Datakit服务"; then
        return 1
    fi
    
    if ! safe_execute "systemctl start datakit" "启动Datakit服务"; then
        return 1
    fi
    
    # 检查Datakit是否启动成功
    if retry_execute "systemctl is-active --quiet datakit" 10 5 "检查Datakit服务状态"; then
        log_success "Datakit启动成功"
        dataway_log "info" "Datakit启动成功"
        return 0
    else
        log_error "Datakit启动超时"
        dataway_log "error" "Datakit启动超时"
        return 1
    fi
}

# 重启Datakit并检查状态
restart_datakit() {
    log_info "=== 步骤6: 重启Datakit并检查状态 ==="
    
    # 重启Datakit
    if ! safe_execute "systemctl restart datakit" "重启Datakit服务"; then
        return 1
    fi
    
    # 检查重启状态
    if retry_execute "pgrep -x \"datakit\" >/dev/null && netstat -tlnp 2>/dev/null | grep -q \":9529 \"" 5 10 "检查Datakit重启状态"; then
        log_success "Datakit重启成功"
        dataway_log "info" "Datakit重启成功"
        return 0
    else
        log_error "Datakit重启失败"
        dataway_log "error" "Datakit重启失败"
        return 1
    fi
}

# 设置定时任务
setup_cron_jobs() {
    log_info "=== 步骤7: 设置定时任务 ==="
    
    # 日志删除定时任务
    if ! safe_execute "cat > /etc/cron.d/datakit_cleanup << 'EOF'
# 每天00:00执行日志清理
0 0 * * * root find /var/log/datakit -name \"*.log.*\" -mtime +7 -delete
EOF" "创建日志清理定时任务"; then
        return 1
    fi

    # Datakit健康检查定时任务
    if ! safe_execute "cat > /etc/cron.d/datakit_health_check << 'EOF'
# 每5分钟检查Datakit健康状态
*/5 * * * * root /usr/local/bin/datakit --check-health >/dev/null 2>&1 || systemctl restart datakit
EOF" "创建健康检查定时任务"; then
        return 1
    fi

    # 重新加载cron配置
    if ! safe_execute "systemctl reload crond 2>/dev/null || systemctl reload cron 2>/dev/null || true" "重新加载cron配置"; then
        log_warning "重新加载cron配置失败，但不影响主流程"
    fi
    
    log_success "定时任务设置完成"
    dataway_log "info" "定时任务设置完成"
    return 0
}

# 设置服务权限
set_permissions() {
    log_info "设置服务权限..."
    
    # 设置Datakit目录权限
    if ! safe_execute "chown -R root:root /usr/local/datakit" "设置Datakit目录权限"; then
        log_warning "设置Datakit目录权限失败"
    fi
    
    # 设置配置文件权限
    if ! safe_execute "chmod 644 /usr/local/datakit/conf.d/*.conf" "设置配置文件权限"; then
        log_warning "设置配置文件权限失败"
    fi
    
    # 设置可执行文件权限
    if ! safe_execute "chmod 755 /usr/local/bin/datakit" "设置Datakit可执行权限"; then
        log_warning "设置Datakit可执行权限失败"
    fi
    
    log_success "服务权限设置完成"
}

# 设置服务
setup_services() {
    log_info "设置服务..."
    
    # 设置Datakit服务
    if ! safe_execute "systemctl daemon-reload" "重新加载systemd配置"; then
        return 1
    fi
    
    if ! safe_execute "systemctl enable datakit" "启用Datakit服务"; then
        return 1
    fi
    
    # 设置Node Exporter服务（如果安装了）
    if [ -f "/usr/local/bin/node_exporter" ]; then
        if ! safe_execute "systemctl enable node_exporter" "启用Node Exporter服务"; then
            log_warning "启用Node Exporter服务失败"
        fi
    fi
    
    log_success "服务设置完成"
    return 0
} 