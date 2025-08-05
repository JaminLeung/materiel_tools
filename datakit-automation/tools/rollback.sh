#!/bin/bash

#=================================================
# Datakit 回滚脚本
# 版本: 2.0.0
# 描述: 回滚Datakit配置和数据
#=================================================

# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="$SCRIPT_DIR/../modules"
readonly CONFIG_DIR="$SCRIPT_DIR/../config"

# 配置加载函数
load_tool_config() {
    # 检查是否通过installer.sh调用，如果是则配置已加载
    # 否则尝试加载默认配置或从环境变量获取
    if [[ -z "${DATAKIT_VERSION:-}" ]]; then
        # 尝试从环境变量获取配置文件路径
        local config_file="${DATAKIT_CONFIG_FILE:-}"
        
        if [[ -n "$config_file" ]]; then
            # 加载指定的配置文件
            if [[ -f "$config_file" ]]; then
                source "$config_file"
            elif [[ -f "$CONFIG_DIR/env/$config_file" ]]; then
                source "$CONFIG_DIR/env/$config_file"
            else
                echo "[ERROR] 指定的配置文件不存在: $config_file" >&2
                exit 1
            fi
        else
            # 尝试加载默认配置
            local default_configs=("benjamin.sh" "production.sh" "development.sh")
            local config_loaded=false
            
            for config in "${default_configs[@]}"; do
                if [[ -f "$CONFIG_DIR/env/$config" ]]; then
                    echo "[INFO] 加载默认配置文件: $config"
                    source "$CONFIG_DIR/env/$config"
                    config_loaded=true
                    break
                fi
            done
            
            if [[ "$config_loaded" == "false" ]]; then
                echo "[ERROR] 未找到可用的配置文件，请设置 DATAKIT_CONFIG_FILE 环境变量" >&2
                exit 1
            fi
        fi
    fi
}

# 加载配置
load_tool_config

# 加载模块
source "$MODULES_DIR/core/logging.sh"
source "$MODULES_DIR/core/utils.sh"

# 回滚到备份
rollback_to_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        log_error "请指定备份文件路径"
        return 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    log_info "开始回滚到备份: $backup_file"
    
    # 停止Datakit服务
    log_info "停止Datakit服务..."
    systemctl stop datakit 2>/dev/null || true
    
    # 创建临时目录
    local temp_dir="/tmp/datakit_rollback_$$"
    mkdir -p "$temp_dir"
    
    # 解压备份文件
    log_info "解压备份文件..."
    cd "$temp_dir"
    tar -xzf "$backup_file"
    
    # 查找备份目录
    local backup_dir=$(find . -maxdepth 1 -type d -name "datakit_backup_*" | head -n 1)
    if [ -z "$backup_dir" ]; then
        log_error "无法找到备份目录"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 恢复配置文件
    if [ -d "$backup_dir/conf.d" ]; then
        log_info "恢复配置文件..."
        cp -r "$backup_dir/conf.d"/* /usr/local/datakit/conf.d/ 2>/dev/null || true
    fi
    
    # 恢复主配置文件
    if [ -f "$backup_dir/datakit.conf" ]; then
        log_info "恢复主配置文件..."
        cp "$backup_dir/datakit.conf" /usr/local/datakit/conf.d/ 2>/dev/null || true
    fi
    
    # 恢复数据目录
    if [ -d "$backup_dir/data" ]; then
        log_info "恢复数据目录..."
        cp -r "$backup_dir/data"/* /usr/local/datakit/data/ 2>/dev/null || true
    fi
    
    # 恢复日志目录
    if [ -d "$backup_dir/datakit" ]; then
        log_info "恢复日志目录..."
        cp -r "$backup_dir/datakit"/* /var/log/datakit/ 2>/dev/null || true
    fi
    
    # 设置权限
    log_info "设置文件权限..."
    chown -R root:root /usr/local/datakit 2>/dev/null || true
    chmod 644 /usr/local/datakit/conf.d/*.conf 2>/dev/null || true
    chmod 755 /usr/local/bin/datakit 2>/dev/null || true
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    # 重启Datakit服务
    log_info "重启Datakit服务..."
    systemctl daemon-reload
    systemctl start datakit
    
    # 检查服务状态
    if systemctl is-active --quiet datakit; then
        log_success "回滚完成，Datakit服务已启动"
        return 0
    else
        log_error "回滚完成，但Datakit服务启动失败"
        return 1
    fi
}

# 列出可用备份
list_available_backups() {
    log_info "可用的备份文件:"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_warning "备份目录不存在: $BACKUP_DIR"
        return 1
    fi
    
    local backup_files=$(find "$BACKUP_DIR" -name "datakit_backup_*.tar.gz" -type f | sort -r)
    
    if [ -z "$backup_files" ]; then
        log_warning "没有找到备份文件"
        return 1
    fi
    
    local count=1
    echo "$backup_files" | while read -r backup_file; do
        local file_size=$(du -h "$backup_file" | cut -f1)
        local file_date=$(stat -c %y "$backup_file" | cut -d' ' -f1)
        echo "$count. $backup_file ($file_size, $file_date)"
        count=$((count + 1))
    done
    
    return 0
}

# 显示帮助信息
show_help() {
    cat << EOF
Datakit 回滚脚本

用法: $0 [选项] [备份文件]

选项:
    -l, --list            列出可用备份
    -h, --help            显示此帮助信息

示例:
    $0 -l                          # 列出可用备份
    $0 /opt/datakit_backups/datakit_backup_20231201_120000.tar.gz  # 回滚到指定备份

EOF
}

# 主函数
main() {
    local backup_file=""
    local list_backups=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--list)
                list_backups=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                backup_file="$1"
                shift
                ;;
        esac
    done
    
    log_info "=== Datakit 回滚脚本启动 ==="
    
    # 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 列出备份
    if [ "$list_backups" = true ]; then
        list_available_backups
        exit 0
    fi
    
    # 执行回滚
    if [ -n "$backup_file" ]; then
        if rollback_to_backup "$backup_file"; then
            log_success "回滚操作完成"
            exit 0
        else
            log_error "回滚操作失败"
            exit 1
        fi
    else
        log_error "请指定备份文件或使用 -l 选项列出可用备份"
        show_help
        exit 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 