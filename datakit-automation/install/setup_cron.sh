#!/bin/bash

#=================================================
# 设置定时任务
#=================================================
# 功能: 设置config_update.sh和健康检测的定时任务
#=================================================


# 设置定时任务
setup_cron_jobs() {
    log_info "设置定时任务..."
    
    # 检查installer.sh脚本是否存在
    local installer_script="$SCENARIO_PROJECT_ROOT/installer.sh"
    if [ ! -f "$installer_script" ]; then
        handle_error "FILE_ERROR" "installer.sh脚本不存在: $installer_script" "ERROR" "false"
        return 1
    fi
    
    # 设置脚本执行权限
    chmod +x "$installer_script"
    
    
    # 使用 utils.sh 中的定时任务包装函数
    # 不再需要单独的 cron_wrapper.sh 脚本
    
    # 备份现有的crontab
    local current_crontab="/tmp/current_crontab_$(date +%Y%m%d%H%M%S)"
    crontab -l 2>/dev/null > "$current_crontab" || true
    
    # 创建新的crontab内容
    local new_crontab="/tmp/new_crontab_$(date +%Y%m%d%H%M%S)"
    cat > "$new_crontab" << EOF

# config-sync - 每15分钟执行一次
*/15 * * * * bash -c "$SCENARIO_PROJECT_ROOT/installer.sh config-update"

# health-check - 每5分钟执行一次
*/5 * * * * bash -c "$SCENARIO_PROJECT_ROOT/installer.sh health-check"

# app-init - 每10分钟执行一次
*/10 * * * * bash -c "$SCENARIO_PROJECT_ROOT/installer.sh app-init"

EOF
    
    # 如果有原有的crontab，添加到新文件中（排除重复的任务）
    if [ -s "$current_crontab" ]; then
        log_info "保留原有crontab配置"
        grep -v "config-sync\|health-check\|app-init" "$current_crontab" >> "$new_crontab" || true
    fi
    
    # 安装新的crontab
    if crontab "$new_crontab"; then
        log_info "定时任务设置成功"
        log_info "config-sync: 每15分钟执行一次"
        log_info "health-check: 每5分钟执行一次"
        log_info "app-init: 每10分钟执行一次"
        log_info "定时任务设置成功: config-sync(15分钟), health-check(5分钟), app-init(10分钟)"
    else
        handle_error "COMMAND_ERROR" "定时任务设置失败" "ERROR" "false"
        
        return 1
    fi
    
    # 清理临时文件
    # TODO 所有脚本禁用 rm -f  luke
    rm -f "$current_crontab" "$new_crontab"
    
    # 重新加载cron配置
    systemctl reload crond 2>/dev/null || systemctl reload cron 2>/dev/null || true
    
    log_info "定时任务设置完成"
    return 0
}

# 主函数
main() {
    # 设置项目根目录
    export SCENARIO_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # 加载核心模块
    source "$SCENARIO_PROJECT_ROOT/core/logging.sh" 2>/dev/null || echo "警告: 无法加载logging.sh" >&2
    source "$SCENARIO_PROJECT_ROOT/core/utils.sh" 2>/dev/null || echo "警告: 无法加载utils.sh" >&2
    
    # 初始化日志系统
    init_logging 2>/dev/null || echo "警告: 无法初始化日志系统" >&2
    
    # 执行定时任务设置
    setup_cron_jobs
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 