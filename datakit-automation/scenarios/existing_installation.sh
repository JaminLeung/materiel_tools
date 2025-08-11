#!/bin/bash

#=================================================
# Datakit 存量安装场景脚本
# 描述: 已运行但未安装Datakit的主机安装场景
#=================================================

set -e

# 脚本目录
readonly SCENARIO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCENARIO_PROJECT_ROOT="$(cd "$SCENARIO_SCRIPT_DIR/.." && pwd)"

# TODO 所有环境变量导入使用 loader.sh
# 配置加载函数





source "$SCENARIO_PROJECT_ROOT/core/utils.sh"
source "$SCENARIO_PROJECT_ROOT/core/validation.sh"
source "$SCENARIO_PROJECT_ROOT/core/datakit_service.sh"
# config_api.sh的功能已合并到utils.sh中
source "$SCENARIO_PROJECT_ROOT/core/utils.sh"


source "$SCENARIO_PROJECT_ROOT/config/loader.sh"
load_all_configs $ENV


# 加载安装步骤模块
# source "$SCENARIO_PROJECT_ROOT/install/host_info.sh"
# source "$SCENARIO_PROJECT_ROOT/install/status_check.sh"
source "$SCENARIO_PROJECT_ROOT/install/download.sh"
source "$SCENARIO_PROJECT_ROOT/install/install.sh"
source "$SCENARIO_PROJECT_ROOT/install/configure.sh"
source "$SCENARIO_PROJECT_ROOT/install/setup_cron.sh"
# source "$SCENARIO_PROJECT_ROOT/install/verify.sh"


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
    log_info "开始Datakit存量安装: 场景=existing_installation"
    
    #=================================================
    # 步骤1: 检查安装状态 (致命错误 - 直接退出程序)
    #=================================================
    log_info "步骤1: 检查安装状态..."
    if ! check_installation_status; then
        handle_error "VALIDATION_ERROR" "不符合安装条件，退出安装" "ERROR" "true"
    fi
    log_info "步骤1: 安装状态检查通过"

    #=================================================
    # 步骤2: 设置资源限制 (致命错误 - 直接退出程序)
    #=================================================
    log_info "步骤2: 获取资源限制并设置环境变量"
    if ! get_machine_specs; then
        handle_error "RESOURCE_ERROR" "资源限制设置失败，请检查机器规格" "ERROR" "true"
    fi
    log_info "步骤2: 资源限制获取成功"

    #=================================================
    # 步骤3: 下载安装包 (致命错误 - 直接退出程序)
    #=================================================
    # log_info "步骤3: 下载安装包..."
    # if ! download_packages; then
    #     
    #     handle_error "NETWORK_ERROR" "下载任务失败，退出安装" "ERROR" "true"
    # fi
    # log_info "步骤3: 安装包下载完成"

    #=================================================
    # 步骤4: 获取主机信息 (非致命错误 - 退出函数)
    #=================================================
    log_info "步骤4: 获取主机信息..."
    if ! get_host_info; then
        handle_error "API_ERROR" "获取主机信息失败，使用缺省值继续安装" "ERROR" "false"
        return 1
    fi
    log_info "步骤4: 主机信息获取完成"

    #=================================================
    # 步骤5: 执行安装 (致命错误 - 直接退出程序)
    #=================================================
    log_info "步骤5: 执行安装..."
    if ! install_components; then
        handle_error "DEPENDENCY_ERROR" "安装失败，退出安装" "ERROR" "true"
    fi
    log_info "步骤5: 组件安装完成"

    #=================================================
    # 步骤6: 配置和验证 (非致命错误 - 退出函数)
    #=================================================
    log_info "步骤6: 配置和验证..."
    if ! configure_and_verify; then
        handle_error "CONFIG_ERROR" "配置和验证失败，退出安装" "ERROR" "false"
        return 1
    fi

    log_info "步骤6: 配置和验证完成"
    
    #=================================================
    # 步骤7: 设置定时任务
    #=================================================
    log_info "步骤7: 设置定时任务..."
    if ! setup_cron_jobs; then
        handle_error "COMMAND_ERROR" "设置定时任务失败，退出安装" "ERROR" "false"
        return 1
    fi
    log_info "步骤7: 定时任务设置完成"
    
    #=================================================
    # 步骤8: 验证安装结果 (非致命错误 - 退出函数)
    #=================================================
    log_info "步骤8: 验证安装结果..."
    if ! verify_installation; then
        handle_error "VALIDATION_ERROR" "安装验证失败，退出安装" "ERROR" "false"
        return 1
    fi
    log_info "步骤8: 安装验证通过"
    
    #=================================================
    # 安装完成 - 记录成功信息
    #=================================================
    # 计算执行时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "=== Datakit存量安装完成 ==="
    log_info "总执行时间: ${duration}秒"
    log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 记录成功信息到Dataway
    log_info "Datakit存量安装完成: 耗时=${duration}秒"
    
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