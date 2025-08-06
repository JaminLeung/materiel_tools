#!/bin/bash

#=================================================
# Datakit 存量安装场景脚本
# 版本: 2.0.0
# 描述: 已运行但未安装Datakit的主机安装场景
#=================================================

set -e

# 脚本目录
readonly SCENARIO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCENARIO_PROJECT_ROOT="$(cd "$SCENARIO_SCRIPT_DIR/.." && pwd)"

# 配置加载函数
load_scenario_config() {
    # 检查是否通过installer.sh调用，如果是则配置已加载
    # 否则尝试加载默认配置或从环境变量获取
    if [[ -z "${DATAKIT_VERSION:-}" ]]; then
        echo "[INFO] 配置未加载，尝试加载默认配置..."
        
        # 尝试从环境变量获取配置文件路径
        local config_file="${DATAKIT_CONFIG_FILE:-}"
        
        if [[ -n "$config_file" ]]; then
            # 加载指定的配置文件
            if [[ -f "$config_file" ]]; then
                source "$config_file"
            elif [[ -f "$SCENARIO_PROJECT_ROOT/config/env/$config_file" ]]; then
                source "$SCENARIO_PROJECT_ROOT/config/env/$config_file"
            else
                echo "[ERROR] 指定的配置文件不存在: $config_file" >&2
                exit 1
            fi
        else
            # 尝试加载默认配置
            local default_configs=("benjamin.sh" "production.sh" "development.sh")
            local config_loaded=false
            
            for config in "${default_configs[@]}"; do
                if [[ -f "$SCENARIO_PROJECT_ROOT/config/env/$config" ]]; then
                    echo "[INFO] 加载默认配置文件: $config"
                    source "$SCENARIO_PROJECT_ROOT/config/env/$config"
                    config_loaded=true
                    break
                fi
            done
            
            if [[ "$config_loaded" == "false" ]]; then
                echo "[ERROR] 未找到可用的配置文件，请设置 DATAKIT_CONFIG_FILE 环境变量" >&2
                exit 1
            fi
        fi
    else
        echo "[INFO] 配置已加载，跳过重新加载"
    fi
}

# 加载配置（仅在需要时）
load_scenario_config

source "$SCENARIO_PROJECT_ROOT/core/utils.sh"
source "$SCENARIO_PROJECT_ROOT/core/validation.sh"
source "$SCENARIO_PROJECT_ROOT/core/datakit_service.sh"
# config_api.sh的功能已合并到utils.sh中
source "$SCENARIO_PROJECT_ROOT/core/config_file.sh"

# 安装工具模块功能已整合到core/utils.sh中

# 加载安装步骤模块
source "$SCENARIO_PROJECT_ROOT/install/host_info.sh"
source "$SCENARIO_PROJECT_ROOT/install/status_check.sh"
source "$SCENARIO_PROJECT_ROOT/install/resource_limit.sh"
source "$SCENARIO_PROJECT_ROOT/install/download.sh"
source "$SCENARIO_PROJECT_ROOT/install/install.sh"
source "$SCENARIO_PROJECT_ROOT/install/configure.sh"
source "$SCENARIO_PROJECT_ROOT/install/setup_cron.sh"
source "$SCENARIO_PROJECT_ROOT/install/verify.sh"

# 全局变量
declare -A INSTALLATION_STATE
INSTALLATION_STATE["start_time"]=$(date +%s)
INSTALLATION_STATE["current_step"]=""
INSTALLATION_STATE["failed_step"]=""

# 错误处理函数
handle_error() {
    local exit_code=$?
    local failed_step="${INSTALLATION_STATE["failed_step"]}"
    
    log_error "安装失败，退出码: $exit_code"
    log_error "失败步骤: $failed_step"
    
    # 记录失败状态
    dataway_log "error" "安装失败: 步骤=$failed_step, 退出码=$exit_code"
    
    # 清理临时文件
    cleanup_temp_files "$DATAKIT_INSTALL_DIR"
    
    # 如果失败在安装过程中，尝试回滚
    if [[ "$failed_step" == "install" ]]; then
        log_warning "尝试回滚安装..."
        rollback_installation
    fi
    
    exit $exit_code
}

# 设置错误处理
trap handle_error ERR

# 清理函数
cleanup_temp_files() {
    local temp_dir="$1"
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        log_info "清理临时安装目录: $temp_dir"
        rm -rf "$temp_dir"
    fi
}

# 回滚函数
rollback_installation() {
    log_warning "执行安装回滚..."
    
    # 停止Datakit服务
    if systemctl is-active --quiet datakit 2>/dev/null; then
        systemctl stop datakit
        log_info "已停止Datakit服务"
    fi
    
    # 恢复备份（如果有）
    if [[ -f "/usr/local/datakit/conf.d/datakit.conf.backup" ]]; then
        mv "/usr/local/datakit/conf.d/datakit.conf.backup" "/usr/local/datakit/conf.d/datakit.conf"
        log_info "已恢复配置文件备份"
    fi
    
    dataway_log "warning" "安装回滚完成"
}

# 存量安装场景主函数
execute_existing_installation() {
    local start_time=$(date +%s)
    
    log_info "=== 开始Datakit存量安装场景 ==="
    log_info "场景描述: 已运行但未安装Datakit的主机"
    log_info "脚本版本: $SCRIPT_VERSION"
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 记录脚本启动
    dataway_log "info" "开始Datakit存量安装: 场景=existing_installation"
    
    # 初始化日志文件
    touch "$LOG_FILE"
    
    # 执行安装步骤
    # 步骤1: 获取主机信息
    INSTALLATION_STATE["current_step"]="host_info"
    get_host_info
    
    # 步骤2: 检查安装状态
    INSTALLATION_STATE["current_step"]="status_check"
    check_installation_status
    
    # 步骤3: 设置资源限制
    INSTALLATION_STATE["current_step"]="resource_limit"
    set_resource_limits
    
    # 步骤4: 下载安装包
    INSTALLATION_STATE["current_step"]="download"
    # download_packages
    
    # 步骤5: 执行安装
    INSTALLATION_STATE["current_step"]="install"
    install_components
    
    # 步骤6: 配置和验证
    INSTALLATION_STATE["current_step"]="configure"
    configure_and_verify
    
    # 步骤7: 设置定时任务
    INSTALLATION_STATE["current_step"]="setup_cron"
    setup_cron_jobs
    
    # 步骤8: 验证安装结果
    INSTALLATION_STATE["current_step"]="verify"
    verify_installation
    
    # 计算执行时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "=== Datakit存量安装完成 ==="
    log_info "总执行时间: ${duration}秒"
    log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    dataway_log "info" "Datakit存量安装完成: 耗时=${duration}秒"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_existing_installation
fi 