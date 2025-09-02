#!/bin/bash

#=================================================
# Datakit 存量安装场景脚本
# 描述: 已运行但未安装Datakit的主机安装场景
#=================================================

set -e

# 脚本目录
readonly SCENARIO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCENARIO_PROJECT_ROOT="$(cd "$SCENARIO_SCRIPT_DIR/.." && pwd)"

# TODO[DONE] 所有环境变量导入使用 loader.sh
# 配置加载函数
load_module "loader" "$SCENARIO_PROJECT_ROOT/config/loader.sh"

load_module "utils" "$SCENARIO_PROJECT_ROOT/core/utils.sh"
load_module "validation" "$SCENARIO_PROJECT_ROOT/core/validation.sh"
load_module "datakit_service" "$SCENARIO_PROJECT_ROOT/core/datakit_service.sh"
# config_api.sh的功能已合并到utils.sh中

load_module "download" "$SCENARIO_PROJECT_ROOT/install/download.sh"
load_module "install" "$SCENARIO_PROJECT_ROOT/install/install.sh"
load_module "configure" "$SCENARIO_PROJECT_ROOT/install/configure.sh"
load_module "setup_cron" "$SCENARIO_PROJECT_ROOT/install/setup_cron.sh"
# load_module "verify" "$SCENARIO_PROJECT_ROOT/install/verify.sh"


# 存量安装场景主函数
# 功能: 执行Datakit存量安装的完整流程
# 参数: 无
# 返回: 0-成功, 1-失败
# 重装场景

execute_preserve_reinstall() {
    log_info "执行保留配置重装场景"
    execute_incremental_installation
}

execute_full_reinstall() {
    log_info "执行完全重装场景"
    execute_existing_installation
}


execute_reinstall() {
    local reinstall_type=$(get_global_state "REINSTALL_TYPE")
    local DATAKIT_AUTO_INSTALLER_TYPE=${DATAKIT_AUTO_INSTALLER_TYPE:-new}
    
    log_info "=== 执行重装场景 ==="
    log_info "场景描述: 重新安装Datakit, 支持新旧版本，支持完全重装和保留配置重装"
    log_info "安装器类型: $DATAKIT_AUTO_INSTALLER_TYPE"
    log_info "重装类型: $reinstall_type"
    

    case "$DATAKIT_AUTO_INSTALLER_TYPE" in
        new)
            case "$reinstall_type" in
                full)
                    log_info "执行新版本完全重新部署方式，执行完全重装场景"
                                
                    log_info "执行步骤1: 还原安装环境"
                    restore_installation_env "new" "$reinstall_type"            
                    if [ $? -ne 0 ]; then
                        handle_error "RESTORE_ENV_ERROR" "还原安装环境失败" "CRITICAL" "true"
                    fi

                    log_info "执行步骤2: 执行完全重装场景"
                    execute_full_reinstall
                    if [ $? -ne 0 ]; then
                        handle_error "FULL_REINSTALL_ERROR" "执行完全重装场景失败" "CRITICAL" "true"
                    fi

                    log_info "执行步骤3: 触发同步app_init脚本，执行app_init场景"
                    execute_app_init
                    if [ $? -ne 0 ]; then
                        handle_error "APP_INIT_ERROR" "执行app_init场景失败" "CRITICAL" "true"
                    fi

                    log_info "执行步骤4: 重装场景完成"
                    ;;
                preserve)
                    log_info "执行新版本保留配置重新部署方式，执行保留配置重装场景"
                    execute_preserve_reinstall
                    ;;
                *)
                    handle_error "COMMAND_ERROR" "未知重装类型: $reinstall_type" "CRITICAL" "true"
                    ;;
            esac

            ;;
        old)            
            # 旧版本需要4个必需参数
            log_info "执行旧版本重新部署方式"

            # 设置环境变量
            log_info "设置OX环境变量"
            set_global_env 

            log_info "还原安装环境"
            restore_installation_env "legacy" "$reinstall_type"

            log_info "执行旧版本重新部署脚本"
            deploy_legacy
            exit_code=$?
            log_info "旧版本重新部署方式完成"
            ;;
        *)
            handle_error "COMMAND_ERROR" "未知安装器类型: $DATAKIT_AUTO_INSTALLER_TYPE" "CRITICAL" "true"
            ;;
    esac

}


#=================================================
# 脚本入口点
#=================================================
# 如果直接运行此脚本（而不是被其他脚本source），则执行安装流程
# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    
#     log_info "总执行时间: ${duration}秒"
#     log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
#     # 初始化错误处理器
#     init_error_handler
    
#     # 执行存量安装场景
#     execute_existing_installation
# fi 