#!/bin/bash

#=================================================
# Datakit 存量安装场景脚本
#=================================================


# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="$SCRIPT_DIR/../modules"
readonly CONFIG_DIR="$SCRIPT_DIR/../config"

# 加载配置和模块
source "$CONFIG_DIR/production_config.sh"
source "$MODULES_DIR/core/logging.sh"
source "$MODULES_DIR/core/utils.sh"

# 存量安装场景
execute_existing_installation() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行存量安装场景 ==="
        log_info "场景描述: 已运行但未安装的主机"
    else
        echo "[INFO] === 执行存量安装场景 ==="
        echo "[INFO] 场景描述: 已运行但未安装的主机"
    fi
    
    # 步骤1: 验证环境
    validate_environment
    
    # 步骤2: 创建备份
    create_backup_if_needed
    
    # 步骤3: 停止现有服务
    stop_datakit_service
    
    # 步骤4: 下载安装包
    download_datakit_packages
    
    # 步骤5: 安装Datakit
    install_datakit
    
    # 步骤6: 配置Datakit
    configure_datakit
    
    # 步骤7: 启动服务
    start_datakit_service
    
    # 步骤8: 验证安装
    verify_installation
    
    # 步骤9: 健康检查
    perform_health_check
    
    if command -v log_success >/dev/null 2>&1; then
        log_success "存量安装完成"
    else
        echo "[SUCCESS] 存量安装完成"
    fi
}

# 服务管理函数
stop_datakit_service() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "停止Datakit服务..."
    else
        echo "[INFO] 停止Datakit服务..."
    fi
    
    if systemctl is-active --quiet datakit 2>/dev/null; then
        systemctl stop datakit
        sleep 2
    fi
}

start_datakit_service() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "启动Datakit服务..."
    else
        echo "[INFO] 启动Datakit服务..."
    fi
    
    systemctl start datakit
    sleep 3
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_existing_installation
fi 