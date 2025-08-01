#!/bin/bash

#=================================================
# Datakit 增量安装场景脚本
#=================================================
# 功能: 处理初始化创建镜像的主机
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