#!/bin/bash

#=================================================
# Datakit 清理脚本
#=================================================
# 功能: 清理Datakit相关的临时文件、日志文件、备份文件
#=================================================

# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="$SCRIPT_DIR/../modules"
readonly CONFIG_DIR="$SCRIPT_DIR/../config"

# 加载配置和模块
source "$CONFIG_DIR/production_config.sh"
source "$MODULES_DIR/core/logging.sh"
source "$MODULES_DIR/core/utils.sh"

# 清理临时文件
cleanup_temp_files() {
    log_info "清理临时文件..."
    
    # 清理安装目录
    if [ -d "${CONFIG[DATAKIT_INSTALL_DIR]}" ]; then
        log_info "清理安装目录: ${CONFIG[DATAKIT_INSTALL_DIR]}"
        rm -rf "${CONFIG[DATAKIT_INSTALL_DIR]}"
    fi
    
    # 清理AWS凭证
    if [ -d ~/.aws ]; then
        log_info "清理AWS凭证"
        rm -rf ~/.aws
    fi
    
    # 清理临时文件
    local temp_patterns=(
        "/tmp/datakit_*"
        "/tmp/datakit_install_*"
        "/tmp/datakit_backup_*"
        "/tmp/datakit_rollback_*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            log_info "清理临时文件: $pattern"
            rm -rf $pattern
        fi
    done
    
    log_success "临时文件清理完成"
}

# 清理日志文件
cleanup_log_files() {
    log_info "清理日志文件..."
    
    # 清理Datakit日志
    if [ -d "/var/log/datakit" ]; then
        log_info "清理Datakit日志文件..."
        find /var/log/datakit -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
        find /var/log/datakit -name "*.log" -size +100M -delete 2>/dev/null || true
    fi
    
    # 清理安装脚本日志
    if [ -f "${CONFIG[LOG_FILE]}" ]; then
        local log_size=$(stat -c%s "${CONFIG[LOG_FILE]}" 2>/dev/null || echo "0")
        if [ "$log_size" -gt 104857600 ]; then  # 100MB
            log_info "清理安装脚本日志文件..."
            mv "${CONFIG[LOG_FILE]}" "${CONFIG[LOG_FILE]}.old"
            touch "${CONFIG[LOG_FILE]}"
        fi
    fi
    
    # 清理系统日志中的Datakit相关条目
    log_info "清理系统日志中的Datakit条目..."
    journalctl --vacuum-time=7d 2>/dev/null || true
    
    log_success "日志文件清理完成"
}

# 清理备份文件
cleanup_backup_files() {
    log_info "清理备份文件..."
    
    if [ -d "$BACKUP_DIR" ]; then
        # 保留最新的5个备份，删除其他备份
        local backup_count=$(find "$BACKUP_DIR" -name "datakit_backup_*.tar.gz" | wc -l)
        
        if [ "$backup_count" -gt $MAX_BACKUP_COUNT ]; then
            log_info "清理旧备份文件..."
            find "$BACKUP_DIR" -name "datakit_backup_*.tar.gz" -printf '%T@ %p\n' | \
                sort -n | head -n -$MAX_BACKUP_COUNT | awk '{print $2}' | \
                xargs rm -f
        fi
        
        # 清理超过30天的备份
        log_info "清理超过30天的备份文件..."
        find "$BACKUP_DIR" -name "datakit_backup_*.tar.gz" -mtime +30 -delete 2>/dev/null || true
    fi
    
    log_success "备份文件清理完成"
}

# 清理缓存文件
cleanup_cache_files() {
    log_info "清理缓存文件..."
    
    # 清理Datakit缓存
    if [ -d "/usr/local/datakit/cache" ]; then
        log_info "清理Datakit缓存..."
        rm -rf /usr/local/datakit/cache/*
    fi
    
    # 清理系统缓存
    log_info "清理系统缓存..."
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    log_success "缓存文件清理完成"
}

# 完整清理
full_cleanup() {
    log_info "=== 开始完整清理 ==="
    
    # 清理临时文件
    cleanup_temp_files
    
    # 清理日志文件
    cleanup_log_files
    
    # 清理备份文件
    cleanup_backup_files
    
    # 清理缓存文件
    cleanup_cache_files
    
    log_success "完整清理完成"
}

# 显示清理统计
show_cleanup_stats() {
    log_info "=== 清理统计 ==="
    
    # 统计清理的文件
    local temp_files=$(find /tmp -name "datakit_*" 2>/dev/null | wc -l)
    local log_files=$(find /var/log/datakit -name "*.log.*" 2>/dev/null | wc -l)
    local backup_files=$(find "$BACKUP_DIR" -name "datakit_backup_*.tar.gz" 2>/dev/null | wc -l)
    
    log_info "临时文件数量: $temp_files"
    log_info "日志文件数量: $log_files"
    log_info "备份文件数量: $backup_files"
    
    # 统计磁盘使用情况
    local disk_usage=$(df / | awk 'NR==2 {print $5}')
    log_info "根分区使用率: $disk_usage"
}

# 显示帮助信息
show_help() {
    cat << EOF
Datakit 清理脚本

用法: $0 [选项]

选项:
    -t, --temp             仅清理临时文件
    -l, --logs             仅清理日志文件
    -b, --backups          仅清理备份文件
    -c, --cache            仅清理缓存文件
    -a, --all              完整清理（默认）
    -s, --stats            显示清理统计
    -h, --help             显示此帮助信息

示例:
    $0 -a                    # 完整清理
    $0 -t -l                # 清理临时文件和日志文件
    $0 -s                   # 显示清理统计

EOF
}

# 主函数
main() {
    local cleanup_temp=false
    local cleanup_logs=false
    local cleanup_backups=false
    local cleanup_cache=false
    local cleanup_all=true
    local show_stats=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--temp)
                cleanup_temp=true
                cleanup_all=false
                shift
                ;;
            -l|--logs)
                cleanup_logs=true
                cleanup_all=false
                shift
                ;;
            -b|--backups)
                cleanup_backups=true
                cleanup_all=false
                shift
                ;;
            -c|--cache)
                cleanup_cache=true
                cleanup_all=false
                shift
                ;;
            -a|--all)
                cleanup_all=true
                shift
                ;;
            -s|--stats)
                show_stats=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "=== Datakit 清理脚本启动 ==="
    
    # 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 显示清理统计
    if [ "$show_stats" = true ]; then
        show_cleanup_stats
        exit 0
    fi
    
    # 执行清理
    if [ "$cleanup_all" = true ]; then
        full_cleanup
    else
        if [ "$cleanup_temp" = true ]; then
            cleanup_temp_files
        fi
        
        if [ "$cleanup_logs" = true ]; then
            cleanup_log_files
        fi
        
        if [ "$cleanup_backups" = true ]; then
            cleanup_backup_files
        fi
        
        if [ "$cleanup_cache" = true ]; then
            cleanup_cache_files
        fi
    fi
    
    log_success "清理操作完成"
    exit 0
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 