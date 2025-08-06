#!/bin/bash

#=================================================
# 步骤2: 检查安装状态
#=================================================
# 功能: 检查Datakit安装状态，避免重复安装
#=================================================

check_installation_status() {
    log_info "=== 步骤2: 检查安装状态 ==="
    
    # 检查Datakit进程
    if check_datakit_process; then
        log_warning "Datakit进程已存在，跳过安装"
        dataway_log "info" "Datakit进程已存在，跳过安装"
        exit 0
    fi
    
    # 检查Datakit端口
    if check_datakit_port; then
        log_warning "Datakit端口9529已被占用，跳过安装"
        dataway_log "info" "Datakit端口9529已被占用，跳过安装"
        exit 0
    fi
    
    # 检查Datakit配置文件
    if check_datakit_config; then
        log_warning "Datakit配置文件已存在，跳过安装"
        dataway_log "info" "Datakit配置文件已存在，跳过安装"
        exit 0
    fi
    
    # 检查Node Exporter状态
    check_node_exporter_status
    
    log_success "Datakit未安装，可以继续安装"
    dataway_log "info" "Datakit未安装，可以继续安装"
    return 0
}

# 检查Datakit进程
check_datakit_process() {
    if pgrep -x "datakit" >/dev/null; then
        log_warning "Datakit进程已存在"
        return 0
    fi
    return 1
}

# 检查Datakit端口
check_datakit_port() {
    if netstat -tlnp 2>/dev/null | grep -q ":9529 " || \
       ss -tlnp 2>/dev/null | grep -q ":9529 "; then
        log_warning "Datakit端口9529已被占用"
        return 0
    fi
    return 1
}

# 检查Datakit配置文件
check_datakit_config() {
    if [ -d "/usr/local/datakit" ] && [ -f "/usr/local/datakit/conf.d/datakit.conf" ]; then
        log_warning "Datakit配置文件已存在"
        return 0
    fi
    return 1
}

# 检查Node Exporter状态
check_node_exporter_status() {
    if pgrep -x "node_exporter" >/dev/null; then
        log_info "Node Exporter进程已存在"
        return 0
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":9100 " || \
       ss -tlnp 2>/dev/null | grep -q ":9100 "; then
        log_warning "端口9100已被占用，可能需要重新配置Node Exporter"
        return 0
    fi
    
    log_info "Node Exporter未安装"
    return 1
} 