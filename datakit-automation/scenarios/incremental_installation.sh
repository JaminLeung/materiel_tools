#!/bin/bash

#=================================================
# Datakit 增量安装场景脚本
# 版本: 2.0.0
# 描述: 初始化创建镜像的主机安装场景
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

# 增量安装场景
execute_incremental_installation() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行增量安装场景 ==="
        log_info "场景描述: 初始化创建镜像的主机"
    else
        echo "[INFO] === 执行增量安装场景 ==="
        echo "[INFO] 场景描述: 初始化创建镜像的主机"
    fi
    
    # 步骤1: 验证环境
    validate_environment
    
    # 步骤2: 创建备份
    create_backup_if_needed
    
    # 步骤3: 更新配置
    update_datakit_config
    
    # 步骤4: 重启服务
    restart_datakit_service
    
    # 步骤5: 验证配置
    verify_configuration
    
    # 步骤6: 健康检查
    perform_health_check
    
    if command -v log_success >/dev/null 2>&1; then
        log_success "增量安装完成"
    else
        echo "[SUCCESS] 增量安装完成"
    fi
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

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_incremental_installation
fi 