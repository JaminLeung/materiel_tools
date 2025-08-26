#!/bin/bash

#=================================================
# Datakit 版本更新场景脚本
# 描述: 升级Datakit版本场景
#=================================================

set -e

# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="$SCRIPT_DIR/../modules"
readonly CONFIG_DIR="$SCRIPT_DIR/../config"

# 配置加载函数
load_scenario_config() {
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
load_scenario_config

# 加载模块
source "$MODULES_DIR/core/logging.sh"
source "$MODULES_DIR/core/utils.sh"

# 版本更新场景
execute_version_upgrade() {
    log_info "=== 执行版本更新场景 ==="
    log_info "场景描述: 升级Datakit版本"
    
    local current_version=$(get_datakit_version)
    local target_version="${CONFIG[DATAKIT_VERSION]:-}"
    
    log_info "当前版本: $current_version"
    log_info "目标版本: $target_version"
    
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
    
    log_info "版本更新完成"
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
    log_info "停止Datakit服务..."
    
    if systemctl is-active --quiet datakit 2>/dev/null; then
        systemctl stop datakit
        sleep 2
    fi
}

start_datakit_service() {
    log_info "启动Datakit服务..."
    
    systemctl start datakit
    sleep 3
}

# 配置管理函数
update_datakit_config() {
    log_info "更新Datakit配置..."
    
    # 这里调用配置模块的函数
    if command -v configure_datakit >/dev/null 2>&1; then
        configure_datakit
    else
        echo "[WARN] configure_datakit函数未找到，跳过配置更新"
    fi
}

# 升级安装函数
upgrade_datakit() {
    log_info "升级Datakit..."
    
    # # 备份当前版本
    # if [[ -f "/usr/local/datakit/datakit" ]]; then
    #     cp /usr/local/datakit/datakit /usr/local/datakit/datakit.backup
    # fi
    
    # 安装新版本
    if command -v install_datakit >/dev/null 2>&1; then
        install_datakit
    else
        echo "[WARN] install_datakit函数未找到，跳过安装"
    fi
}

# 验证函数
verify_upgrade() {
    log_info "验证升级..."
    
    local new_version=$(get_datakit_version)
    local target_version="${CONFIG[DATAKIT_VERSION]:-}"
    
    if [[ "$new_version" == "$target_version" ]]; then
        log_info "版本升级成功: $new_version"
    else
        echo "[ERROR] 版本升级失败，当前版本: $new_version，目标版本: $target_version" >&2
        return 1
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_version_upgrade
fi 