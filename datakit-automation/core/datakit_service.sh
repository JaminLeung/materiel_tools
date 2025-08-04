#!/bin/bash

# Datakit服务控制相关函数

check_datakit_status() {
    process_running "datakit" || port_listening "9529" || {
        command_exists systemctl && systemctl is-active --quiet datakit 2>/dev/null
    }
}

start_datakit() {
    log_info "启动Datakit"
    local start_success=false
    
    if command_exists systemctl && systemctl start datakit 2>/dev/null; then
        start_success=true
    elif command_exists datakit && datakit service -S >/dev/null 2>&1; then
        start_success=true
    else
        die "Datakit启动失败"
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
                log_success "Datakit启动成功 (检查 $check_count/$max_checks)"
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
            die "Datakit启动失败: 超过10次检查仍未正常运行"
        else
            log_warning "Datakit启动可能不完整，但继续执行"
            return 0
        fi
    fi
}

stop_datakit() {
    log_info "停止Datakit"
    if command_exists systemctl && systemctl stop datakit 2>/dev/null; then
        log_success "Datakit停止成功"
        return 0
    fi
    if command_exists datakit && datakit service -T >/dev/null 2>&1; then
        log_success "Datakit停止成功"
        return 0
    fi
    pkill -f datakit 2>/dev/null && log_success "Datakit强制停止成功" || die "Datakit停止失败"
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
            die "Datakit重启失败"
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
                log_success "Datakit重启成功 (检查 $check_count/$max_checks)"
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
            die "Datakit重启失败: 超过10次检查仍未正常运行"
        else
            log_warning "Datakit重启可能不完整，但继续执行"
            return 0
        fi
    fi
} 