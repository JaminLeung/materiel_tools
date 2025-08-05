#!/bin/bash

#=================================================
# Datakit 配置更新场景脚本
# 版本: 2.0.0
# 描述: 仅更新配置文件场景
#=================================================

set -e

# 脚本目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="$SCRIPT_DIR/../core"
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
source "$MODULES_DIR/logging.sh"
source "$MODULES_DIR/utils.sh"

# 配置更新场景
execute_config_update() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行配置更新场景 ==="
        log_info "场景描述: 仅更新配置文件"
    else
        echo "[INFO] === 执行配置更新场景 ==="
        echo "[INFO] 场景描述: 仅更新配置文件"
    fi
    
    # 步骤1: 验证环境
    validate_environment
    
    # 步骤2: 创建配置备份
    create_config_backup
    
    # 步骤3: 更新配置
    update_datakit_config
    
    # 步骤4: 重启服务
    restart_datakit_service
    
    # 步骤5: 验证配置
    verify_configuration
    
    # 步骤6: 健康检查
    perform_health_check
    
    if command -v log_success >/dev/null 2>&1; then
        log_success "配置更新完成"
    else
        echo "[SUCCESS] 配置更新完成"
    fi
}

# 配置管理函数
update_datakit_config() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "更新Datakit配置..."
    else
        echo "[INFO] 更新Datakit配置..."
    fi
    
    # 调用scripts/config_update.sh中的main函数
    local config_update_script="$SCRIPT_DIR/../scripts/config_update.sh"
    if [ -f "$config_update_script" ]; then
        bash "$config_update_script"
    else
        echo "[ERROR] 配置更新脚本不存在: $config_update_script" >&2
        return 1
    fi
}
# 创建配置文件配备份
create_config_backup() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "创建配置备份..."
    else
        echo "[INFO] 创建配置备份..."
    fi
    
    local backup_dir="${CONFIG[BACKUP_DIR]:-/var/backups/datakit}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local config_backup="$backup_dir/config_backup_$timestamp.tar.gz"
    
    mkdir -p "$backup_dir"
    
    if [[ -d "/usr/local/datakit/conf.d" ]]; then
        tar -czf "$config_backup" -C /usr/local/datakit conf.d/
        echo "[INFO] 配置备份已创建: $config_backup"
    fi
}

# 重启Datakit服务
restart_datakit_service() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "重启Datakit服务..."
    else
        echo "[INFO] 重启Datakit服务..."
    fi
    
    systemctl restart datakit
    sleep 3
}

# 验证函数
verify_configuration() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "验证配置..."
    else
        echo "[INFO] 验证配置..."
    fi
    
    # 检查配置文件语法
    if [[ -f "/usr/local/datakit/datakit" ]]; then
        /usr/local/datakit/datakit check --config /usr/local/datakit/conf.d/ 2>/dev/null || {
            echo "[ERROR] 配置文件验证失败" >&2
            return 1
        }
    fi
}

