#!/bin/bash

#=================================================
# Datakit 安装器主入口脚本
#=================================================

set -euo pipefail

# 脚本元信息
readonly INSTALLER_SCRIPT_NAME="$(basename "$0")"
readonly DATAKIT_VERSION="2.4.0"
readonly INSTALLER_SCRIPT_VERSION="1.0.15_2.4.0"
readonly INSTALLER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 声明全局状态变量

declare -A GLOBAL_STATE




# 设置全局状态
set_global_state() {
    local key="$1"
    local value="$2"
    GLOBAL_STATE["$key"]="$value"
}

# 获取全局状态
get_global_state() {
    local key="$1"
    echo "${GLOBAL_STATE[$key]:-}"
}

# TODO[done] 定时任务修改 ENV 
DATAKIT_ENV="${DATAKIT_ENV:-dev}"




# 加载模块
# TODO[DONE] 所有的 source 改成 load_module
load_module() {
    local module_name="$1"
    local module_file="$2"
    
    if [[ -f "$module_file" ]]; then
        source "$module_file"
        echo "INFO: 加载模块: $module_name"
    else
        echo "[ERROR] 模块文件不存在: $module_file" >&2
        exit 1
    fi
}
load_module "loader" "$INSTALLER_SCRIPT_DIR/config/loader.sh"

# 初始化安装器
initialize_installer() {
    echo "INFO: === Datakit 安装器初始化 ==="
        
    # 加载核心模块
    load_module "logging" "$INSTALLER_SCRIPT_DIR/core/logging.sh"
    load_module "error_handler" "$INSTALLER_SCRIPT_DIR/core/error_handler.sh"
    load_module "validation" "$INSTALLER_SCRIPT_DIR/core/validation.sh"
    load_module "utils" "$INSTALLER_SCRIPT_DIR/core/utils.sh"
    load_module "initialize" "$INSTALLER_SCRIPT_DIR/core/initialize.sh"
    # 安装模块已由scenarios脚本处理，此处不再加载旧模块
    # 初始化运行时环境（仅创建基础目录，不创建版本目录）
    if command -v init_runtime_environment >/dev/null 2>&1; then
        init_runtime_environment
    else
        # 兼容性处理：如果新函数不可用，使用旧函数
        if command -v init_runtime_dirs >/dev/null 2>&1; then
            init_runtime_dirs
        else
            echo "INFO: 初始化运行时目录"
            # 如果函数不可用，手动创建基本目录
            mkdir -p "$RUNTIME_DIR" "$RUNTIME_LOG_DIR" 2>/dev/null || true
        fi
    fi
    
    # 同步命令工具
    # 如果是root用户，则同步命令工具
    log_info "当前用户: $(whoami)"
    if [ "$(whoami)" == "root" ]; then
        log_info "当前用户是root用户，同步命令工具"
        sync_command_tool
        # init_datakit_runtime_environment
    else
        log_info "当前用户不是root用户"
    fi

    # 执行初始化脚本
    initialize_script




    log_info "安装器初始化完成"
}

# 显示帮助信息
show_help() {
    cat << EOF
Datakit 安装器 v$INSTALLER_SCRIPT_VERSION
Datakit 版本 v$DATAKIT_VERSION

用法: $INSTALLER_SCRIPT_NAME [选项] <命令>

选项:
    -v, --verbose         详细输出
    -d, --debug           调试模式
    -h, --help            显示此帮助信息
    --version             查看版本 - 查看Datakit安装器版本、Datakit版本
    --type <TYPE>         重装类型 (仅用于reinstall命令):
                          full - 完全重装，清理所有配置 (默认)
                          preserve - 保留配置重装，保留现有配置文件

命令:
    existing-install      存量安装 - 已运行但未安装的主机
    incremental-install   增量安装 - 初始化创建镜像的主机
    version-upgrade       版本更新 - 升级Datakit版本
    reinstall             重装 - 完全重新安装
    setup-cron            设置定时任务 - 配置Datakit相关定时任务
    app-init              应用初始化 - 从运维平台同步业务配置
    config-update           配置同步 - Datakit服务控制和配置管理
    health-check          健康检查 - 检查Datakit健康状态并自动重启
    version               查看版本 - 查看Datakit安装器版本、Datakit版本
    clean-install         清理安装环境 - 清理Datakit安装环境

配置方式:
    1. 环境变量 (推荐):
       export DATAKIT_ENV=dev

    2. 环境配置文件:
       复制 $INSTALLER_SCRIPT_DIR/config/env_config_example.sh 为 env_config.sh 并编辑

必需环境变量:
    DATAKIT_ENV=dev          # 环境标识 (dev, test, prod等)
    其他配置需定义在配置文件里

示例:
    # 使用环境变量 (推荐)
    export DATAKIT_VERSION=2.4.0

    $INSTALLER_SCRIPT_NAME existing-install

    # 指定版本升级
    DATAKIT_VERSION=v1.5.0 $INSTALLER_SCRIPT_NAME version-upgrade

    # 重装相关示例
    $INSTALLER_SCRIPT_NAME reinstall                   # 完全重装 (默认)
    $INSTALLER_SCRIPT_NAME --type full reinstall       # 完全重装，清理所有配置
    $INSTALLER_SCRIPT_NAME --type preserve reinstall   # 保留配置重装

    # 维护相关示例
    $INSTALLER_SCRIPT_NAME version-upgrade             # 版本升级
    $INSTALLER_SCRIPT_NAME config-update               # 配置同步
    $INSTALLER_SCRIPT_NAME health-check                # 健康检查

    # 配置相关示例
    $INSTALLER_SCRIPT_NAME setup-cron                  # 设置定时任务
    $INSTALLER_SCRIPT_NAME app-init                    # 应用初始化

    # 信息查看
    $INSTALLER_SCRIPT_NAME version                     # 查看版本信息

    配置工具:
    配置测试: $INSTALLER_SCRIPT_DIR/config/tests/test_config.sh
    配置查看: $INSTALLER_SCRIPT_DIR/config/loader.sh --show

EOF
}

# 主函数
main() {    
    local env_config_file=""
    local command=""
    local reinstall_type="full"  # 默认为完全重装
    local IS_OLD_VERSION=${IS_OLD_VERSION:-"false"}
    
    set_global_state "RELEASE_ID" "datakit_auto_installer_$(date +%Y%m%d_%H%M%S)"



    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                if [[ -z "$2" || "$2" =~ ^- ]]; then
                    echo "[ERROR] --config 参数需要一个值" >&2
                    show_help
                    exit 1
                fi
                env_config_file="$2"
                shift 2
                ;;
            --type)
                if [[ -z "$2" || "$2" =~ ^- ]]; then
                    echo "[ERROR] --type 参数需要一个值" >&2
                    show_help
                    exit 1
                fi
                if [[ "$2" != "full" && "$2" != "preserve" ]]; then
                    echo "[ERROR] --type 参数值必须是 'full' 或 'preserve'" >&2
                    show_help
                    exit 1
                fi
                reinstall_type="$2"
                shift 2
                ;;
            -v|--verbose)
                export LOG_LEVEL=0
                shift
                ;;
            -d|--debug)
                export ENABLE_DEBUG_MODE=true
                export LOG_LEVEL=0
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                echo "Datakit安装器版本: $INSTALLER_SCRIPT_VERSION"
                echo "Datakit版本: $DATAKIT_VERSION"
                exit 0
                ;;
            existing-install|incremental-install|version-upgrade|config-update|reinstall|auto-install|setup-cron|app-init|health-check|clean-install)
                command="$1"
                shift
                ;;
            *)
                echo "[ERROR] 未知参数: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done



    # 检查命令
    if [[ -z "$command" ]]; then
        show_help
        exit 0
    fi
    set_global_state "command" "$command"
    set_global_state "REINSTALL_TYPE" "$reinstall_type"

    load_module "loader" "$INSTALLER_SCRIPT_DIR/config/loader.sh"
    # 加载配置（自动检测环境变量或配置文件）
    load_all_configs "$DATAKIT_ENV"
    # echo "env_config_file: $env_config_file"
    # load_config "$env_config_file"
    



    # 判断是否是旧版本
    if [ "$IS_OLD_VERSION" == "true" ]; then
        log_info "执行旧版本重新部署方式"
        wget -qO- https://static-api.pre-guance.houtai.io/guance/datakit/datakit_install.sh | sudo bash
        exit 0
    fi

    # 初始化安装器
    initialize_installer

    # 初始化错误处理器
    init_error_handler


    # 执行预检：评估安装条件
    if ! evaluate_datakit_installation; then
        return 1
    fi


    # 检查是否已有实例运行
    if [ "$(id -u)" -ne 0 ]; then
        log_info "当前不是 root 用户，执行check_running_instance。"
        check_running_instance
        # 检查cron_acl 和 cron_limits 定时任务是否存在，如果存在则输出对应的定时任务内容，如果不存在则退出
    else
        log_info "当前是 root 用户，不执行check_running_instance。"

        if crontab -l | grep "datakit_acl_update.sh" >/dev/null 2>&1; then
            log_info "cron_acl 定时任务存在，输出定时任务内容"
            log_info "cron_acl 定时任务内容: $(crontab -l | grep "datakit_acl_update.sh")"
        else
            log_info "cron_acl 定时任务不存在，退出"
            handle_error "CRON_ERROR" "cron_acl 定时任务不存在，退出" "CRITICAL" "true"
        fi
        if crontab -l | grep "set_datakit_resource_limits.sh" >/dev/null 2>&1; then
            log_info "cron_limits 定时任务存在，输出定时任务内容"
            log_info "cron_limits 定时任务内容: $(crontab -l | grep "set_datakit_resource_limits.sh")"
        else
            log_info "cron_limits 定时任务不存在，退出"
            handle_error "CRON_ERROR" "cron_limits 定时任务不存在，退出" "CRITICAL" "true"
        fi
    fi
    

    # 检查是否存在 datakit 用户，如果不存在则退出
    if ! id -u datakit >/dev/null 2>&1; then
        log_info "datakit 用户不存在，退出"
        handle_error "USER_ERROR" "datakit 用户不存在，退出" "CRITICAL" "true"
    fi

    # 设置当前时间在GLOBAL_STATE中
    # set_global_state "RELEASE_ID" "$(date +%Y%m%d_%H%M%S)"
    # 执行命令
    # 添加定时任务场景命令
    case "$command" in
        existing-install)
            execute_existing_installation
            ;;
        incremental-install)
            execute_incremental_installation
            ;;
        version-upgrade)
            execute_version_upgrade
            
            ;;
        config-update)
            execute_config_update
            
            ;;
        reinstall)
            execute_reinstall
            
            ;;
        setup-cron)
            execute_setup_cron
            
            ;;
        app-init)
            execute_app_init

            ;;
        health-check)
            execute_health_check
            ;;
        clean-install)
            restore_installation_env "new" "full"
            ;;
        *)
            echo "[ERROR] 未知命令: $command" >&2
            handle_error "COMMAND_ERROR" "未知命令: $command" "CRITICAL" "true"
            ;;
    esac
}


# 存量安装场景
execute_existing_installation() {
    log_info "=== 执行存量安装场景 ==="
    log_info "场景描述: 已运行但未安装的主机"
    
    # 调用scenarios目录下的存量安装脚本
    local scenario_script="$INSTALLER_SCRIPT_DIR/scenarios/existing_installation.sh"
    
    if [[ -f "$scenario_script" ]]; then
        log_info "调用存量安装场景脚本: $scenario_script"
        
        # TODO[DONE] 统一从配置文件里获取
        # 传递配置信息给场景脚本
        
        # 执行场景脚本
        source "$scenario_script"

        execute_existing_installation
    else
        handle_error "FILE_ERROR" "存量安装场景脚本不存在: $scenario_script" "CRITICAL" "true"
    fi
}


# 重装场景
execute_reinstall() {
    log_info "=== 执行重装场景 ==="
    log_info "场景描述: 重新安装Datakit, 支持新旧版本，支持完全重装和保留配置重装"
    
    # 调用scenarios目录下的保留配置重装脚本
    local scenario_script="$INSTALLER_SCRIPT_DIR/scenarios/reinstall.sh"
    
    if [[ -f "$scenario_script" ]]; then
        log_info "调用重装场景脚本: $scenario_script"
        
        # TODO[DONE] 统一从配置文件里获取
        # 传递配置信息给场景脚本
        
        # 执行场景脚本
        source "$scenario_script"

        execute_reinstall
    else
        handle_error "FILE_ERROR" "保留配置重装场景脚本不存在: $scenario_script" "CRITICAL" "true"
    fi
}


# 保存配置重装场景
execute_keep_config_installation() {
    log_info "=== 执行保存配置重装场景 ==="
    log_info "场景描述: 已运行安装Datakit的主机，保存配置安装"
    
    # 调用scenarios目录下的保存配置安装脚本
    local scenario_script="$INSTALLER_SCRIPT_DIR/scenarios/existing_installation.sh"
    
    if [[ -f "$scenario_script" ]]; then
        log_info "调用保存配置重装场景脚本: $scenario_script"   
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        
        # 执行场景脚本
        source "$scenario_script"

        execute_keep_config_installation
    else
        handle_error "FILE_ERROR" "保存配置重装场景脚本不存在: $scenario_script" "CRITICAL" "true"
    fi
}



# 增量安装场景
execute_incremental_installation() {
    log_info "=== 执行增量安装场景 ==="
    log_info "场景描述: 初始化创建镜像的主机"
    
    # 调用scenarios目录下的增量安装脚本
    local scenario_script="$INSTALLER_SCRIPT_DIR/scenarios/incremental_installation.sh"
    
    if [[ -f "$scenario_script" ]]; then
        log_info "调用增量安装场景脚本: $scenario_script"
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        
        # 执行场景脚本
        source "$scenario_script"
    else
        handle_error "FILE_ERROR" "增量安装场景脚本不存在: $scenario_script" "CRITICAL" "true"
    fi
}

# 版本更新场景
execute_version_upgrade() {
    log_info "=== 执行版本更新场景 ==="
    log_info "场景描述: 升级Datakit版本"
    
    # 调用scenarios目录下的版本更新脚本
    local scenario_script="$INSTALLER_SCRIPT_DIR/scenarios/version_upgrade.sh"
    
    if [[ -f "$scenario_script" ]]; then
        log_info "调用版本更新场景脚本: $scenario_script"
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        
        # 执行场景脚本
        source "$scenario_script"
    else
        handle_error "FILE_ERROR" "版本更新场景脚本不存在: $scenario_script" "CRITICAL" "true"
    fi
}




# 设置定时任务场景
execute_setup_cron() {
    log_info "=== 执行设置定时任务场景 ==="
    log_info "场景描述: 配置Datakit相关定时任务"
    
    # 调用install目录下的定时任务设置脚本
    local setup_cron_script="$INSTALLER_SCRIPT_DIR/install/setup_cron.sh"
    
    if [[ -f "$setup_cron_script" ]]; then
        log_info "调用定时任务设置脚本: $setup_cron_script"
        
        # 传递配置信息给脚本
        
        # 执行定时任务设置脚本
        source "$setup_cron_script"
    else
        handle_error "FILE_ERROR" "定时任务设置脚本不存在: $setup_cron_script" "CRITICAL" "true"
    fi
}


# 应用初始化场景
execute_app_init() {
    log_info "=== 执行应用初始化场景 ==="
    log_info "场景描述: 从运维平台同步业务配置到Datakit采集器"
    
    # 调用scripts目录下的应用初始化脚本
    local app_init_script="$INSTALLER_SCRIPT_DIR/scripts/app_init.sh"
    
    if [[ -f "$app_init_script" ]]; then
        log_info "调用应用初始化脚本: $app_init_script"
        
        # 传递配置信息给脚本
        # 执行应用初始化脚本
        source "$app_init_script"
    else
        handle_error "FILE_ERROR" "应用初始化脚本不存在: $app_init_script" "CRITICAL" "true"
    fi
}

# 配置同步场景
execute_config_update() {
    log_info "=== 执行配置同步场景 ==="
    log_info "场景描述: Datakit服务控制、全局配置修改、采集器配置管理"
    
    # 调用scripts目录下的配置更新脚本
    local config_update_script="$INSTALLER_SCRIPT_DIR/scripts/config_update.sh"
    
    if [[ -f "$config_update_script" ]]; then
        log_info "调用配置同步脚本: $config_update_script"
        
        # 执行配置同步脚本
        source "$config_update_script"
    else
        handle_error "FILE_ERROR" "配置同步脚本不存在: $config_update_script" "CRITICAL" "true"
    fi
}

# 健康检查场景
execute_health_check() {
    log_info "=== 执行健康检查场景 ==="
    log_info "场景描述: 检查Datakit健康状态，异常时自动重启"
    
    # 调用scripts目录下的健康检查脚本
    local health_check_script="$INSTALLER_SCRIPT_DIR/scripts/datakit_health_check.sh"
    
    if [[ -f "$health_check_script" ]]; then
        log_info "调用健康检查脚本: $health_check_script"
        
        # 传递配置信息给脚本
        
        # 执行健康检查脚本
        source "$health_check_script"
    else
        handle_error "FILE_ERROR" "健康检查脚本不存在: $health_check_script" "CRITICAL" "true"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
