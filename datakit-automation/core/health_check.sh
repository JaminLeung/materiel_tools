#!/bin/bash

# 健康检查服务控制相关函数

control_health_check_service() {
    local action="$1"
    
    # 检查健康检查脚本是否存在
    if [ ! -f "$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT" ]; then
        log_warning "健康检查脚本不存在: $CONFIG_UPDATE_HEALTH_CHECK_SCRIPT"
        return 1
    fi
    if [ ! -x "$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT" ]; then
        log_warning "健康检查脚本无执行权限: $CONFIG_UPDATE_HEALTH_CHECK_SCRIPT"
        return 1
    fi
    
    case "$action" in
        start)
            log_info "安装Datakit健康检查定时任务"
            "$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT" install-cron
            ;;
        stop)
            log_info "卸载Datakit健康检查定时任务"
            "$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT" uninstall-cron
            ;;
        restart)
            log_info "重启Datakit健康检查定时任务"
            "$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT" uninstall-cron
            sleep 2
            "$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT" install-cron
            ;;
        status)
            log_info "检查Datakit健康检查定时任务状态"
            "$CONFIG_UPDATE_HEALTH_CHECK_SCRIPT" status
            ;;
        *)
            log_error "未知的健康检查服务操作: $action"
            return 1
            ;;
    esac
} 