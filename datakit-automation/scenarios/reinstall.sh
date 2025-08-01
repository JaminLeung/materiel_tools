#!/bin/bash

#=================================================
# Datakit 重装场景脚本
#=================================================
# 功能: 完全重新安装Datakit
# 版本: 0.1.1
#=================================================

# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="$SCRIPT_DIR/../modules"
readonly CONFIG_DIR="$SCRIPT_DIR/../config"

# 加载配置和模块
source "$CONFIG_DIR/production_config.sh"
source "$MODULES_DIR/core/logging.sh"
source "$MODULES_DIR/core/utils.sh"

# 重装场景
execute_reinstall() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行重装场景 ==="
        log_info "场景描述: 完全重新安装Datakit"
    else
        echo "[INFO] === 执行重装场景 ==="
        echo "[INFO] 场景描述: 完全重新安装Datakit"
    fi
    
    # 步骤1: 验证环境
    validate_environment
    
    # 步骤2: 创建完整备份
    create_full_backup
    
    # 步骤3: 完全卸载
    uninstall_datakit
    
    # 步骤4: 清理残留文件
    cleanup_datakit_files
    
    # 步骤5: 下载安装包
    download_datakit_packages
    
    # 步骤6: 重新安装
    install_datakit
    
    # 步骤7: 配置Datakit
    configure_datakit
    
    # 步骤8: 验证安装
    verify_installation
    
    # 步骤9: 健康检查
    perform_health_check
    
    if command -v log_success >/dev/null 2>&1; then
        log_success "重装完成"
    else
        echo "[SUCCESS] 重装完成"
    fi
}

# 备份函数
create_full_backup() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "创建完整备份..."
    else
        echo "[INFO] 创建完整备份..."
    fi
    
    if command -v create_backup >/dev/null 2>&1; then
        create_backup "/usr/local/datakit" "datakit_full"
    else
        echo "[WARN] create_backup函数未找到，跳过备份"
    fi
}

# 卸载和清理函数
uninstall_datakit() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "卸载Datakit..."
    else
        echo "[INFO] 卸载Datakit..."
    fi
    
    # 停止服务
    if systemctl is-active --quiet datakit 2>/dev/null; then
        systemctl stop datakit
    fi
    
    # 禁用服务
    if systemctl is-enabled --quiet datakit 2>/dev/null; then
        systemctl disable datakit
    fi
    
    # 删除服务文件
    if [[ -f "/etc/systemd/system/datakit.service" ]]; then
        rm -f /etc/systemd/system/datakit.service
    fi
    
    # 重新加载systemd
    systemctl daemon-reload
}

cleanup_datakit_files() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "清理Datakit文件..."
    else
        echo "[INFO] 清理Datakit文件..."
    fi
    
    # 删除安装目录
    if [[ -d "/usr/local/datakit" ]]; then
        rm -rf /usr/local/datakit
    fi
    
    # 删除日志目录
    if [[ -d "/var/log/datakit" ]]; then
        rm -rf /var/log/datakit
    fi
    
    # 删除数据目录
    if [[ -d "/var/lib/datakit" ]]; then
        rm -rf /var/lib/datakit
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_reinstall
fi 