#!/bin/bash

#=================================================
# 步骤7: 设置定时任务
#=================================================
# 功能: 设置config_update.sh和健康检测的定时任务
#=================================================


# 设置定时任务
setup_cron_jobs() {
    log_info "设置定时任务..."
    
    # 检查config_update.sh脚本是否存在
    local config_update_script="$SCENARIO_PROJECT_ROOT/scripts/config_update.sh"
    if [ ! -f "$config_update_script" ]; then
        handle_error "FILE_ERROR" "定时任务脚本不存在: $config_update_script" "ERROR" "false"
        dataway_log "error" "定时任务脚本不存在: config_update.sh"
        return 1
    fi
    
    # 检查健康检测脚本是否存在
    local health_check_script="$SCENARIO_PROJECT_ROOT/scripts/datakit_health_check.sh"
    if [ ! -f "$health_check_script" ]; then
        handle_error "FILE_ERROR" "健康检测脚本不存在: $health_check_script" "ERROR" "false"
        dataway_log "error" "健康检测脚本不存在: datakit_health_check.sh"
        return 1
    fi
    
    # 检查app_init.sh脚本是否存在
    local app_init_script="$SCENARIO_PROJECT_ROOT/scripts/app_init.sh"
    if [ ! -f "$app_init_script" ]; then
        handle_error "FILE_ERROR" "业务配置同步脚本不存在: $app_init_script" "ERROR" "false"
        dataway_log "error" "业务配置同步脚本不存在: app_init.sh"
        return 1
    fi
    
    # 设置脚本执行权限
    chmod +x "$config_update_script"
    chmod +x "$health_check_script"
    chmod +x "$app_init_script"
    
    
    # 使用 utils.sh 中的定时任务包装函数
    # 不再需要单独的 cron_wrapper.sh 脚本
    
    # 备份现有的crontab
    local current_crontab="/tmp/current_crontab_$(date +%Y%m%d%H%M%S)"
    crontab -l 2>/dev/null > "$current_crontab" || true
    
    # 创建新的crontab内容
    # TODO 定时任务新增逻辑
    local new_crontab="/tmp/new_crontab_$(date +%Y%m%d%H%M%S)"
    cat > "$new_crontab" << EOF

# config_update.sh - 每15分钟执行一次，带锁检查
*/15 * * * * bash -c 'source "$SCENARIO_PROJECT_ROOT/core/utils.sh" && execute_cron_wrapper "config_update" "$SCENARIO_PROJECT_ROOT/scripts/config_update.sh"'

# datakit_health_check.sh - 每5分钟执行一次，带锁检查
*/5 * * * * bash -c 'source "$SCENARIO_PROJECT_ROOT/core/utils.sh" && execute_cron_wrapper "health_check" "$SCENARIO_PROJECT_ROOT/scripts/datakit_health_check.sh"'

# app_init.sh - 每10分钟执行一次，带锁检查
*/10 * * * * bash -c 'source "$SCENARIO_PROJECT_ROOT/core/utils.sh" && execute_cron_wrapper "app_init" "$SCENARIO_PROJECT_ROOT/scripts/app_init.sh"'

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
        log_info "日志文件: /opt/datakit/config_update.log, /opt/datakit/health_check.log, /opt/datakit/app_init.log"
        log_info "锁文件: /var/run/config_update.lock, /var/run/datakit_health_check.lock, /var/run/app_init.lock"
        log_info "使用 utils.sh 中的 execute_cron_wrapper 函数"
        log_info "定时任务设置成功: config_update.sh(15分钟), health_check.sh(5分钟), app_init.sh(10分钟)"
    else
        handle_error "COMMAND_ERROR" "定时任务设置失败" "ERROR" "false"
        dataway_log "error" "定时任务设置失败"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$current_crontab" "$new_crontab"
    
    # 重新加载cron配置
    systemctl reload crond 2>/dev/null || systemctl reload cron 2>/dev/null || true
    
    log_success "定时任务设置完成"
    log_info "定时任务设置完成"
    return 0
} 