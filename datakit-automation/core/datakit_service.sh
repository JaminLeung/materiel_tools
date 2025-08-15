#!/bin/bash

# Datakit服务控制相关函数

check_datakit_status() {
    process_running "datakit" || port_listening "9529" || {
        command_exists systemctl && systemctl is-active --quiet datakit 2>/dev/null
    }
}

# TODO exit 相关逻辑需要统一
check_installation_status() {
    log_info "=== 检查安装状态 ==="
    
    # 检查Datakit进程
    if check_datakit_process; then
        log_info "Datakit进程已存在，跳过安装"
        handle_error "SERVICE_ERROR" "Datakit进程已存在，跳过安装" "ERROR" "true"

    fi
    
    # 检查Datakit端口
    if check_datakit_port; then
        log_info "Datakit端口9529已被占用，跳过安装"
        handle_error "SERVICE_ERROR" "Datakit端口9529已被占用，跳过安装" "ERROR" "true"
    fi
    
    # 检查Datakit配置文件
    # TODO 配置文件路径需要确认
    if check_datakit_config; then
        log_info "Datakit配置文件已存在，跳过安装"
        handle_error "SERVICE_ERROR" "Datakit配置文件已存在，跳过安装" "ERROR" "true"
    fi
        
    log_info "Datakit未安装，可以继续安装"
    return 0
}

# 检查Datakit进程
check_datakit_process() {
    if pgrep -x "datakit" >/dev/null; then
        record_error "SERVICE_ERROR" "Datakit进程已存在" "WARNING"
        return 0
    fi
    return 1
}

# 检查Datakit端口
check_datakit_port() {
    if netstat -tlnp 2>/dev/null | grep -q ":9529 " || \
       ss -tlnp 2>/dev/null | grep -q ":9529 "; then
        record_error "SERVICE_ERROR" "Datakit端口9529已被占用" "WARNING"
        return 0
    fi
    return 1
}

# 检查Datakit配置文件
check_datakit_config() {
    if [ -d "/usr/local/datakit" ] && [ -f "/usr/local/datakit/conf.d/datakit.conf" ]; then
        record_error "SERVICE_ERROR" "Datakit配置文件已存在" "WARNING"
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
        record_error "SERVICE_ERROR" "端口9100已被占用，可能需要重新配置Node Exporter" "WARNING"
        return 0
    fi
    
    log_info "Node Exporter未安装"
    return 1
} 

start_datakit() {
    log_info "启动Datakit"
    local start_success=false
    
    if command_exists systemctl && systemctl start datakit 2>/dev/null; then
        start_success=true
    elif command_exists datakit && datakit service -S >/dev/null 2>&1; then
        start_success=true
    else
        handle_error "SERVICE_ERROR" "Datakit启动失败" "ERROR" "false"
        return 1
    fi
    
    if [ "$start_success" = true ]; then
        # 检查Datakit进程和端口是否正常运行
        log_info "检查Datakit进程和端口状态..."
        local check_count=0
        local max_checks=15
        local check_interval=5
        
        while [ $check_count -lt $max_checks ]; do
            check_count=$((check_count + 1))
            
            # 检查进程和端口
            if pgrep -x "datakit" >/dev/null && \
               (netstat -tlnp 2>/dev/null | grep -q ":9529 " || \
                ss -tlnp 2>/dev/null | grep -q ":9529 "); then
                log_info "Datakit启动成功 (检查 $check_count/$max_checks)"
                return 0
            else
                if [ $check_count -lt $max_checks ]; then
                    log_info "等待Datakit启动... (检查 $check_count/$max_checks)"
                    sleep $check_interval
                fi
            fi
        done
        
        # 超过最大检查次数，认为启动失败
        if [ $check_count -ge 10 ]; then
            handle_error "SERVICE_ERROR" "Datakit启动失败: 超过10次检查仍未正常运行" "ERROR" "false"
            return 1
        else
            record_error "SERVICE_ERROR" "Datakit启动可能不完整，但继续执行" "WARNING"
            return 0
        fi
    fi
}

stop_datakit() {
    log_info "停止Datakit"
    if command_exists systemctl && systemctl stop datakit 2>/dev/null; then
        log_info "Datakit停止成功"
        return 0
    fi
    if command_exists datakit && datakit service -T >/dev/null 2>&1; then
        log_info "Datakit停止成功"
        return 0
    fi
    pkill -f datakit 2>/dev/null && log_info "Datakit强制停止成功" || {
        handle_error "SERVICE_ERROR" "Datakit停止失败" "ERROR" "false"
        return 1
    }
}

restart_datakit() {
    log_info "重启Datakit"
    local restart_success=false
    
    if command_exists systemctl && systemctl restart datakit 2>/dev/null; then
        restart_success=true
    elif command_exists datakit && datakit service -R >/dev/null 2>&1; then
        restart_success=true
    else
        # 手动重启
        if stop_datakit && start_datakit; then
            restart_success=true
        else
            handle_error "SERVICE_ERROR" "Datakit重启失败" "ERROR" "false"
            return 1
        fi
    fi
    
    if [ "$restart_success" = true ]; then
        # 检查Datakit进程和端口是否正常运行
        log_info "检查Datakit进程和端口状态..."
        local check_count=0
        local max_checks=15
        local check_interval=5
        
        while [ $check_count -lt $max_checks ]; do
            check_count=$((check_count + 1))
            
            # 检查进程和端口
            if pgrep -x "datakit" >/dev/null && \
               (netstat -tlnp 2>/dev/null | grep -q ":9529 " || \
                ss -tlnp 2>/dev/null | grep -q ":9529 "); then
                log_info "Datakit重启成功 (检查 $check_count/$max_checks)"
                return 0
            else
                if [ $check_count -lt $max_checks ]; then
                    log_info "等待Datakit重启... (检查 $check_count/$max_checks)"
                    sleep $check_interval
                fi
            fi
        done
        
        # 超过最大检查次数，认为重启失败
        if [ $check_count -ge 10 ]; then
            handle_error "SERVICE_ERROR" "Datakit重启失败: 超过10次检查仍未正常运行" "ERROR" "true"
            return 1
        else
            record_error "SERVICE_ERROR" "Datakit重启可能不完整，但继续执行" "WARNING"
            return 0
        fi
    fi
} 