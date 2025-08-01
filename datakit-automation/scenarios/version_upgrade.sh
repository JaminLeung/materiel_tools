#!/bin/bash

#=================================================
# Datakit 版本更新场景脚本
#=================================================
# 功能: 升级Datakit版本
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

# 版本更新场景
execute_version_upgrade() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行版本更新场景 ==="
        log_info "场景描述: 升级Datakit版本"
    else
        echo "[INFO] === 执行版本更新场景 ==="
        echo "[INFO] 场景描述: 升级Datakit版本"
    fi
    
    local current_version=$(get_datakit_version)
    local target_version="${CONFIG[DATAKIT_VERSION]:-}"
    
    if command -v log_info >/dev/null 2>&1; then
        log_info "当前版本: $current_version"
        log_info "目标版本: $target_version"
    else
        echo "[INFO] 当前版本: $current_version"
        echo "[INFO] 目标版本: $target_version"
    fi
    
    # 步骤1: 验证环境
    validate_environment
    
    # 步骤2: 创建备份
    create_backup_if_needed
    
    # 步骤3: 停止服务
    stop_datakit_service
    
    # 步骤4: 下载新版本
    download_datakit_packages
    
    # 步骤5: 升级安装
    upgrade_datakit
    
    # 步骤6: 更新配置
    update_datakit_config
    
    # 步骤7: 启动服务
    start_datakit_service
    
    # 步骤8: 验证升级
    verify_upgrade
    
    # 步骤9: 健康检查
    perform_health_check
    
    if command -v log_success >/dev/null 2>&1; then
        log_success "版本更新完成"
    else
        echo "[SUCCESS] 版本更新完成"
    fi
}

# 获取当前Datakit版本
get_datakit_version() {
    if [[ -f "/usr/local/datakit/datakit" ]]; then
        /usr/local/datakit/datakit version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' | head -1 || echo "unknown"
    else
        echo "unknown"
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

# 配置管理函数
update_datakit_config() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "更新Datakit配置..."
    else
        echo "[INFO] 更新Datakit配置..."
    fi
    
    # 这里调用配置模块的函数
    if command -v configure_datakit >/dev/null 2>&1; then
        configure_datakit
    else
        echo "[WARN] configure_datakit函数未找到，跳过配置更新"
    fi
}

# 升级安装函数
upgrade_datakit() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "升级Datakit..."
    else
        echo "[INFO] 升级Datakit..."
    fi
    
    # 备份当前版本
    if [[ -f "/usr/local/datakit/datakit" ]]; then
        cp /usr/local/datakit/datakit /usr/local/datakit/datakit.backup
    fi
    
    # 安装新版本
    if command -v install_datakit >/dev/null 2>&1; then
        install_datakit
    else
        echo "[WARN] install_datakit函数未找到，跳过安装"
    fi
}

# 验证函数
verify_upgrade() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "验证升级..."
    else
        echo "[INFO] 验证升级..."
    fi
    
    local new_version=$(get_datakit_version)
    local target_version="${CONFIG[DATAKIT_VERSION]:-}"
    
    if [[ "$new_version" == "$target_version" ]]; then
        if command -v log_success >/dev/null 2>&1; then
            log_success "版本升级成功: $new_version"
        else
            echo "[SUCCESS] 版本升级成功: $new_version"
        fi
    else
        echo "[ERROR] 版本升级失败，当前版本: $new_version，目标版本: $target_version" >&2
        return 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_version_upgrade
fi 