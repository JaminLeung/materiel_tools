#!/bin/bash

#=================================================
# 步骤7: 设置定时任务
#=================================================
# 功能: 设置config_update.sh和健康检测的定时任务
#=================================================

setup_cron_jobs() {
    log_info "=== 设置定时任务 ==="
    
    # 设置定时任务
    if ! setup_cron_jobs; then
        log_error "设置定时任务失败"
        dataway_log "error" "设置定时任务失败"
        return 1
    fi
    
    log_success "定时任务设置完成"
    dataway_log "info" "定时任务设置完成"
    return 0
}

# 设置定时任务
setup_cron_jobs() {
    log_info "设置定时任务..."
    
    # 检查config_update.sh脚本是否存在
    local config_update_script="$SCENARIO_PROJECT_ROOT/scripts/config_update.sh"
    if [ ! -f "$config_update_script" ]; then
        log_error "定时任务脚本不存在: $config_update_script"
        dataway_log "error" "定时任务脚本不存在: config_update.sh"
        return 1
    fi
    
    # 检查健康检测脚本是否存在
    local health_check_script="$SCENARIO_PROJECT_ROOT/scripts/datakit_health_check.sh"
    if [ ! -f "$health_check_script" ]; then
        log_error "健康检测脚本不存在: $health_check_script"
        dataway_log "error" "健康检测脚本不存在: datakit_health_check.sh"
        return 1
    fi
    
    # 检查app_init.sh脚本是否存在
    local app_init_script="$SCENARIO_PROJECT_ROOT/scripts/app_init.sh"
    if [ ! -f "$app_init_script" ]; then
        log_error "业务配置同步脚本不存在: $app_init_script"
        dataway_log "error" "业务配置同步脚本不存在: app_init.sh"
        return 1
    fi
    
    # 设置脚本执行权限
    chmod +x "$config_update_script"
    chmod +x "$health_check_script"
    chmod +x "$app_init_script"
    
    
    # 使用通用包装脚本
    local wrapper_script="$SCENARIO_PROJECT_ROOT/install/cron_wrapper.sh"
    
    if [ ! -f "$wrapper_script" ]; then
        log_error "通用包装脚本不存在: $wrapper_script"
        dataway_log "error" "通用包装脚本不存在: cron_wrapper.sh"
        return 1
    fi
    
    # 设置包装脚本权限
    chmod +x "$wrapper_script"
    
    # 备份现有的crontab
    local current_crontab="/tmp/current_crontab_$(date +%Y%m%d%H%M%S)"
    crontab -l 2>/dev/null > "$current_crontab" || true
    
    # 创建新的crontab内容
    # TODO 定时任务新增逻辑
    local new_crontab="/tmp/new_crontab_$(date +%Y%m%d%H%M%S)"
    cat > "$new_crontab" << EOF
# Datakit定时任务配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# config_update.sh - 每15分钟执行一次，带锁检查
*/15 * * * * $wrapper_script config_update "$config_update_script"

# datakit_health_check.sh - 每5分钟执行一次，带锁检查
*/5 * * * * $wrapper_script health_check "$health_check_script"

# app_init.sh - 每10分钟执行一次，带锁检查
*/10 * * * * $wrapper_script app_init "$app_init_script"

# 保留原有的crontab内容（如果有的话）
EOF
    
    # 如果有原有的crontab，添加到新文件中（排除重复的任务）
    if [ -s "$current_crontab" ]; then
        log_info "保留原有crontab配置"
        grep -v "config_update\|datakit_health_check\|app_init" "$current_crontab" >> "$new_crontab" || true
    fi
    
    # 安装新的crontab
    if crontab "$new_crontab"; then
        log_success "定时任务设置成功"
        log_info "config_update.sh: 每15分钟执行一次（带锁检查，只保留最新日志）"
        log_info "datakit_health_check.sh: 每5分钟执行一次（带锁检查）"
        log_info "app_init.sh: 每10分钟执行一次（带锁检查，只保留最新日志）"
        log_info "日志文件: /var/log/datakit/config_update.log, /var/log/datakit/health_check.log, /var/log/datakit/app_init.log"
        log_info "锁文件: /var/run/config_update.lock, /var/run/datakit_health_check.lock, /var/run/app_init.lock"
        dataway_log "info" "定时任务设置成功: config_update.sh(15分钟), health_check.sh(5分钟), app_init.sh(10分钟)"
    else
        log_error "定时任务设置失败"
        dataway_log "error" "定时任务设置失败"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$current_crontab" "$new_crontab"
    
    # 重新加载cron配置
    systemctl reload crond 2>/dev/null || systemctl reload cron 2>/dev/null || true
    
    log_success "定时任务设置完成"
    dataway_log "info" "定时任务设置完成"
    return 0
} 