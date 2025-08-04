#!/bin/bash

#=================================================
# 步骤7: 设置定时任务
#=================================================
# 功能: 设置config_update.sh的定时任务，每15分钟执行一次，带锁检查
#=================================================

step_07_setup_cron_jobs() {
    log_info "=== 步骤7: 设置定时任务 ==="
    
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
    
    # 设置脚本执行权限
    chmod +x "$config_update_script"
    
    # 创建日志目录
    mkdir -p /var/log/datakit
    
    # 使用install_utils中的包装脚本
    local wrapper_script="$SCENARIO_PROJECT_ROOT/install/install_utils/config_update_wrapper.sh"
    if [ ! -f "$wrapper_script" ]; then
        log_error "包装脚本不存在: $wrapper_script"
        dataway_log "error" "包装脚本不存在: config_update_wrapper.sh"
        return 1
    fi
    
    # 设置包装脚本权限
    chmod +x "$wrapper_script"
    
    # 备份现有的crontab
    local current_crontab="/tmp/current_crontab_$(date +%Y%m%d%H%M%S)"
    crontab -l 2>/dev/null > "$current_crontab" || true
    
    # 创建新的crontab内容
    local new_crontab="/tmp/new_crontab_$(date +%Y%m%d%H%M%S)"
    cat > "$new_crontab" << EOF
# Datakit定时任务配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# config_update.sh - 每15分钟执行一次，带锁检查
*/15 * * * * $wrapper_script "$config_update_script"

# 保留原有的crontab内容（如果有的话）
EOF
    
    # 如果有原有的crontab，添加到新文件中（排除重复的config_update任务）
    if [ -s "$current_crontab" ]; then
        log_info "保留原有crontab配置"
        grep -v "config_update" "$current_crontab" >> "$new_crontab" || true
    fi
    
    # 安装新的crontab
    if crontab "$new_crontab"; then
        log_success "定时任务设置成功"
        log_info "config_update.sh: 每15分钟执行一次（带锁检查，只保留最新日志）"
        log_info "日志文件: /var/log/datakit/config_update.log"
        log_info "锁文件: /var/run/config_update.lock"
        dataway_log "info" "定时任务设置成功: config_update.sh(15分钟, 带锁检查)"
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