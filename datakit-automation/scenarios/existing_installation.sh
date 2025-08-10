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
source "$SCENARIO_PROJECT_ROOT/core/utils.sh"

# 安装工具模块功能已整合到core/utils.sh中

# 加载安装步骤模块
# source "$SCENARIO_PROJECT_ROOT/install/host_info.sh"
# source "$SCENARIO_PROJECT_ROOT/install/status_check.sh"
source "$SCENARIO_PROJECT_ROOT/install/download.sh"
source "$SCENARIO_PROJECT_ROOT/install/install.sh"
source "$SCENARIO_PROJECT_ROOT/install/configure.sh"
source "$SCENARIO_PROJECT_ROOT/install/setup_cron.sh"
# source "$SCENARIO_PROJECT_ROOT/install/verify.sh"

#=================================================
# 全局状态变量
#=================================================
# 用于跟踪安装过程中的状态信息
declare -A INSTALLATION_STATE
INSTALLATION_STATE["start_time"]=$(date +%s)      # 安装开始时间
INSTALLATION_STATE["current_step"]=""              # 当前执行步骤
INSTALLATION_STATE["failed_step"]=""               # 失败的步骤（如果有）





# 存量安装场景主函数
# 功能: 执行Datakit存量安装的完整流程
# 参数: 无
# 返回: 0-成功, 1-失败
execute_existing_installation() {
    local start_time=$(date +%s)
    
    log_info "=== 开始Datakit存量安装场景 ==="
    log_info "场景描述: 已运行但未安装Datakit的主机"
    log_info "脚本版本: $SCRIPT_VERSION"
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 记录脚本启动到Dataway
    dataway_log "info" "开始Datakit存量安装: 场景=existing_installation"
    
    #=================================================
    # 步骤1: 检查安装状态 (致命错误 - 直接退出程序)
    #=================================================
    INSTALLATION_STATE["current_step"]="status_check"
    log_info "步骤1: 检查安装状态..."
    if ! check_installation_status; then
        dataway_log "error" "不符合安装条件，退出安装"
        handle_error "VALIDATION_ERROR" "不符合安装条件，退出安装" "ERROR" "true"
    fi
    log_success "步骤1: 安装状态检查通过"

    #=================================================
    # 步骤2: 设置资源限制 (致命错误 - 直接退出程序)
    #=================================================
    INSTALLATION_STATE["current_step"]="resource_limit"
    log_info "步骤2: 设置资源限制..."
    if ! set_resource_limits; then
        dataway_log "error" "资源限制设置失败，请检查机器规格"
        handle_error "RESOURCE_ERROR" "资源限制设置失败，请检查机器规格" "ERROR" "true"
    fi
    log_success "步骤2: 资源限制设置完成"

    #=================================================
    # 步骤3: 下载安装包 (致命错误 - 直接退出程序)
    #=================================================
    # INSTALLATION_STATE["current_step"]="download"
    # log_info "步骤3: 下载安装包..."
    # if ! download_packages; then
    #     dataway_log "error" "下载任务失败，退出安装"
    #     handle_error "NETWORK_ERROR" "下载任务失败，退出安装" "ERROR" "true"
    # fi
    # log_success "步骤3: 安装包下载完成"

    #=================================================
    # 步骤4: 获取主机信息 (非致命错误 - 退出函数)
    #=================================================
    INSTALLATION_STATE["current_step"]="host_info"
    log_info "步骤4: 获取主机信息..."
    if ! get_host_info; then
        dataway_log "error" "获取主机信息失败，退出安装"
        handle_error "API_ERROR" "获取主机信息失败，退出安装" "ERROR" "false"
        return 1
    fi
    log_success "步骤4: 主机信息获取完成"

    #=================================================
    # 步骤5: 执行安装 (致命错误 - 直接退出程序)
    #=================================================
    INSTALLATION_STATE["current_step"]="install"
    log_info "步骤5: 执行安装..."
    if ! install_components; then
        dataway_log "error" "安装失败，退出安装"
        handle_error "DEPENDENCY_ERROR" "安装失败，退出安装" "ERROR" "true"
    fi
    log_success "步骤5: 组件安装完成"

    #=================================================
    # 步骤6: 配置和验证 (非致命错误 - 退出函数)
    #=================================================
    INSTALLATION_STATE["current_step"]="configure"
    log_info "步骤6: 配置和验证..."
    if ! configure_and_verify; then
        dataway_log "error" "配置和验证失败，退出安装"
        handle_error "CONFIG_ERROR" "配置和验证失败，退出安装" "ERROR" "false"
        return 1
    fi
    log_success "步骤6: 配置和验证完成"
    
    #=================================================
    # 步骤7: 设置定时任务 (非致命错误 - 退出函数)
    #=================================================
    INSTALLATION_STATE["current_step"]="setup_cron"
    log_info "步骤7: 设置定时任务..."
    if ! setup_cron_jobs; then
        dataway_log "error" "设置定时任务失败，退出安装"
        handle_error "COMMAND_ERROR" "设置定时任务失败，退出安装" "ERROR" "false"
        return 1
    fi
    log_success "步骤7: 定时任务设置完成"
    
    #=================================================
    # 步骤8: 验证安装结果 (非致命错误 - 退出函数)
    #=================================================
    INSTALLATION_STATE["current_step"]="verify"
    log_info "步骤8: 验证安装结果..."
    if ! verify_installation; then
        dataway_log "error" "安装验证失败，退出安装"
        handle_error "VALIDATION_ERROR" "安装验证失败，退出安装" "ERROR" "false"
        return 1
    fi
    log_success "步骤8: 安装验证通过"
    
    #=================================================
    # 安装完成 - 记录成功信息
    #=================================================
    # 计算执行时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "=== Datakit存量安装完成 ==="
    log_info "总执行时间: ${duration}秒"
    log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 记录成功信息到Dataway
    dataway_log "info" "Datakit存量安装完成: 耗时=${duration}秒"
    
    return 0
}

#=================================================
# 脚本入口点
#=================================================
# 如果直接运行此脚本（而不是被其他脚本source），则执行安装流程
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    
    log_info "总执行时间: ${duration}秒"
    log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 初始化错误处理器
    init_error_handler
    
    # 执行存量安装场景
    execute_existing_installation
fi 