#!/bin/bash

#=================================================
# Datakit 备份脚本
#=================================================
# 功能: 创建Datakit配置和数据的备份
#=================================================

# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="$SCRIPT_DIR/../modules"
readonly CONFIG_DIR="$SCRIPT_DIR/../config"

# 加载配置和模块
source "$CONFIG_DIR/production_config.sh"
source "$MODULES_DIR/core/logging.sh"
source "$MODULES_DIR/core/utils.sh"

# 创建备份
create_datakit_backup() {
    local backup_name="datakit_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log_info "开始创建Datakit备份: $backup_path"
    
    # 创建备份目录
    mkdir -p "$backup_path"
    
    # 备份配置文件
    if [ -d "/usr/local/datakit/conf.d" ]; then
        log_info "备份配置文件..."
        cp -r /usr/local/datakit/conf.d "$backup_path/"
    fi
    
    # 备份主配置文件
    if [ -f "/usr/local/datakit/conf.d/datakit.conf" ]; then
        log_info "备份主配置文件..."
        cp /usr/local/datakit/conf.d/datakit.conf "$backup_path/"
    fi
    
    # 备份数据目录
    if [ -d "/usr/local/datakit/data" ]; then
        log_info "备份数据目录..."
        cp -r /usr/local/datakit/data "$backup_path/"
    fi
    
    # 备份日志目录
    if [ -d "/var/log/datakit" ]; then
        log_info "备份日志目录..."
        cp -r /var/log/datakit "$backup_path/"
    fi
    
    # 创建备份信息文件
    cat > "$backup_path/backup_info.txt" << EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份类型: Datakit完整备份
备份内容: 配置文件、数据文件、日志文件
系统信息: $(uname -a)
Datakit版本: $(/usr/local/bin/datakit --version 2>/dev/null || echo "未知")
EOF
    
    # 压缩备份
    log_info "压缩备份文件..."
    cd "$BACKUP_DIR"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    rm -rf "$backup_name"
    
    log_success "备份创建完成: ${backup_name}.tar.gz"
    
    # 清理旧备份
    cleanup_old_backups "datakit_backup"
    
    return 0
}

# 主函数
main() {
    log_info "=== Datakit 备份脚本启动 ==="
    
    # 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 创建备份
    if create_datakit_backup; then
        log_success "备份操作完成"
        exit 0
    else
        log_error "备份操作失败"
        exit 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 