#!/bin/bash

#=================================================
# Datakit 安装器主入口脚本
# 版本: 0.1.1
#=================================================

set -euo pipefail

# 脚本元信息
readonly INSTALLER_SCRIPT_NAME="$(basename "$0")"
readonly INSTALLER_SCRIPT_VERSION="2.0.0"
readonly INSTALLER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 模块目录
readonly INSTALLER_MODULES_DIR="$INSTALLER_SCRIPT_DIR/modules"
readonly INSTALLER_CONFIG_DIR="$INSTALLER_SCRIPT_DIR/config"
readonly INSTALLER_CORE_DIR="$INSTALLER_SCRIPT_DIR/core"
readonly INSTALLER_INSTALL_DIR="$INSTALLER_SCRIPT_DIR/install"
readonly INSTALLER_MONITOR_DIR="$INSTALLER_SCRIPT_DIR/monitor"
readonly INSTALLER_SCENARIOS_DIR="$INSTALLER_SCRIPT_DIR/scenarios"
readonly INSTALLER_TOOLS_DIR="$INSTALLER_SCRIPT_DIR/tools"

# 简化的信号处理函数
cleanup_on_exit() {
    echo "[INFO] 脚本退出，执行清理..."
    
    # 清理临时文件
    if [[ -d "/tmp/datakit_install_*" ]]; then
        rm -rf /tmp/datakit_install_* 2>/dev/null || true
    fi
    
    # 释放锁文件
    if [[ -f "/tmp/datakit_install.lock" ]]; then
        rm -f /tmp/datakit_install.lock 2>/dev/null || true
    fi
}

handle_signal() {
    echo "[WARN] 收到中断信号，正在退出..." >&2
    exit 1
}

# 信号处理
trap 'cleanup_on_exit' EXIT
trap 'handle_signal' INT TERM

# 加载配置
load_config() {
    local env_config_file="$1"
    
    echo "[INFO] 开始加载配置..."
    
    # 1. 首先加载基础配置（config/base下的脚本）
    local base_config_dir="$INSTALLER_CONFIG_DIR/base"
    if [[ -d "$base_config_dir" ]]; then
        echo "[INFO] 加载基础配置: $base_config_dir"
        
        # 先加载base_config.sh（基础配置）
        local base_config_file="$base_config_dir/base_config.sh"
        if [[ -f "$base_config_file" ]]; then
            echo "[INFO] 加载基础配置文件: base_config.sh"
            source "$base_config_file"
        fi
        
        # 再加载其他配置文件（除了base_config.sh）
        for config_file in "$base_config_dir"/*.sh; do
            if [[ -f "$config_file" && "$(basename "$config_file")" != "base_config.sh" ]]; then
                echo "[INFO] 加载基础配置文件: $(basename "$config_file")"
                source "$config_file"
            fi
        done
    else
        echo "[ERROR] 基础配置目录不存在: $base_config_dir" >&2
        exit 1
    fi
    
    # 2. 如果指定了环境配置文件，则加载它（会覆盖基础配置）
    if [[ -n "$env_config_file" ]]; then
        local full_config_path=""
        
        # 检查是否是绝对路径
        if [[ "$env_config_file" = /* ]]; then
            full_config_path="$env_config_file"
        else
            # 相对路径，尝试在config目录下查找
            # 如果路径已经包含config，则直接使用
            if [[ "$env_config_file" =~ ^config/ ]]; then
                full_config_path="$INSTALLER_SCRIPT_DIR/$env_config_file"
            else
                # 首先尝试在config/env目录下查找
                local env_config_path="$INSTALLER_CONFIG_DIR/env/$env_config_file"
                if [[ -f "$env_config_path" ]]; then
                    full_config_path="$env_config_path"
                else
                    # 如果不在env目录，尝试在config根目录下查找
                    full_config_path="$INSTALLER_CONFIG_DIR/$env_config_file"
                fi
            fi
        fi
        
        if [[ -f "$full_config_path" ]]; then
            echo "[INFO] 加载环境配置文件: $full_config_path"
            source "$full_config_path"
        else
            echo "[ERROR] 指定的配置文件不存在: $full_config_path" >&2
            echo "[INFO] 尝试查找的路径:" >&2
            echo "[INFO]   - $INSTALLER_CONFIG_DIR/env/$env_config_file" >&2
            echo "[INFO]   - $INSTALLER_CONFIG_DIR/$env_config_file" >&2
            exit 1
        fi
    else
        echo "[INFO] 未指定环境配置文件，使用默认配置"
    fi
    
    # 设置默认的DATAKIT_VERSION（如果未设置）
    export DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"
    
    echo "[INFO] 配置加载完成"
}

# 加载模块
load_module() {
    local module_name="$1"
    local module_file="$2"
    
    if [[ -f "$module_file" ]]; then
        source "$module_file"
        echo "[DEBUG] 加载模块: $module_name"
    else
        echo "[ERROR] 模块文件不存在: $module_file" >&2
        exit 1
    fi
}

# 初始化安装器
initialize_installer() {

    echo "[INFO] === Datakit 安装器初始化 ==="
    
    # 检查必需目录
    local required_dirs=("$INSTALLER_CORE_DIR" "$INSTALLER_CONFIG_DIR" "$INSTALLER_INSTALL_DIR" "$INSTALLER_SCENARIOS_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "[ERROR] 必需目录不存在: $dir" >&2
            exit 1
        fi
    done
    
    # 加载核心模块
    load_module "logging" "$INSTALLER_CORE_DIR/logging.sh"
    load_module "validation" "$INSTALLER_CORE_DIR/validation.sh"
    load_module "utils" "$INSTALLER_CORE_DIR/utils.sh"
    load_module "initialize" "$INSTALLER_CORE_DIR/initialize.sh"
    
    # 安装模块已由scenarios脚本处理，此处不再加载旧模块
    # 执行初始化脚本
    initialize_script


    
    if command -v log_success >/dev/null 2>&1; then
        log_success "安装器初始化完成"
    else
        echo "[SUCCESS] 安装器初始化完成"
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
Datakit 安装器 v$INSTALLER_SCRIPT_VERSION

用法: $INSTALLER_SCRIPT_NAME [选项] <命令>

选项:
    -c, --config FILE     指定环境配置文件 (可选)
    -v, --verbose         详细输出
    -d, --debug           调试模式
    -h, --help            显示此帮助信息

命令:
    existing-install      存量安装 - 已运行但未安装的主机
    incremental-install   增量安装 - 初始化创建镜像的主机
    version-upgrade       版本更新 - 升级Datakit版本
    config-update         配置更新 - 仅更新配置文件
    reinstall             重装 - 完全重新安装

配置方式:
    1. 环境变量 (推荐):
       export DATAKIT_VERSION=1.78.0
       export S3_BUCKET=my-bucket
       export S3_ACCESS_KEY=your-key
       export S3_SECRET_KEY=your-secret
       export DATAWAY_URL=https://dataway.example.com
       export OPS_ADDR=http://ops.example.com:5000

    2. 环境配置文件:
       复制 $INSTALLER_CONFIG_DIR/env_config_example.sh 为 env_config.sh 并编辑

必需环境变量:
    DATAKIT_VERSION=v1.x.x     # Datakit版本号
    S3_BUCKET=bucket_name      # S3存储桶名称
    S3_ACCESS_KEY=key          # S3访问密钥
    S3_SECRET_KEY=secret       # S3秘密密钥
    DATAWAY_URL=url            # Dataway服务地址
    OPS_ADDR=url               # 运维平台地址

示例:
    # 使用环境变量 (推荐)
    export DATAKIT_VERSION=1.78.0
    export S3_BUCKET=my-bucket
    export S3_ACCESS_KEY=your-key
    export S3_SECRET_KEY=your-secret
    export DATAWAY_URL=https://dataway.example.com
    export OPS_ADDR=http://ops.example.com:5000
    $INSTALLER_SCRIPT_NAME existing-install

    # 指定版本升级
    DATAKIT_VERSION=v1.5.0 $INSTALLER_SCRIPT_NAME version-upgrade

    # 使用环境配置文件
    $INSTALLER_SCRIPT_NAME --config benjamin.sh existing-install

    # 使用绝对路径的配置文件
    $INSTALLER_SCRIPT_NAME --config /path/to/custom_config.sh existing-install

    配置工具:
    配置测试: $INSTALLER_CONFIG_DIR/tests/test_config.sh
    配置查看: $INSTALLER_CONFIG_DIR/loader.sh --show

EOF
}

# 主函数
main() {
    local env_config_file=""
    local command=""
    
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
            existing-install|incremental-install|version-upgrade|config-update|reinstall|auto-install)
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
    
    # 加载配置（自动检测环境变量或配置文件）
    load_config "$env_config_file"
    
    # 初始化安装器
    initialize_installer

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
        *)
            echo "[ERROR] 未知命令: $command" >&2
            exit 1
            ;;
    esac
}


# 存量安装场景
execute_existing_installation() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行存量安装场景 ==="
        log_info "场景描述: 已运行但未安装的主机"
    else
        echo "[INFO] === 执行存量安装场景 ==="
        echo "[INFO] 场景描述: 已运行但未安装的主机"
    fi
    
    # 调用scenarios目录下的存量安装脚本
    local scenario_script="$INSTALLER_SCENARIOS_DIR/existing_installation.sh"
    
    if [[ -f "$scenario_script" ]]; then
        if command -v log_info >/dev/null 2>&1; then
            log_info "调用存量安装场景脚本: $scenario_script"
        else
            echo "[INFO] 调用存量安装场景脚本: $scenario_script"
        fi
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        export DATAKIT_VERSION="${DATAKIT_VERSION:-1.78.0}"
        
        # 导出所有关键配置变量
        export CONFIG_UPDATE_OPS_API_URL="${CONFIG_UPDATE_OPS_API_URL:-}"
        export OPS_ADDR="${OPS_ADDR:-}"
        export DATAWAY_LOG_URL="${DATAWAY_LOG_URL:-}"
        export DATAWAY_URL="${DATAWAY_URL:-}"
        export CONFIG_UPDATE_DATAWAY_URL="${CONFIG_UPDATE_DATAWAY_URL:-}"
        export S3_BUCKET="${S3_BUCKET:-}"
        export S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
        export S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
        export DATAKIT_INSTALL_DIR="${DATAKIT_INSTALL_DIR:-}"
        
        # 执行场景脚本
        bash "$scenario_script"
    else
        if command -v log_error >/dev/null 2>&1; then
            log_error "存量安装场景脚本不存在: $scenario_script"
        else
            echo "[ERROR] 存量安装场景脚本不存在: $scenario_script" >&2
        fi
        exit 1
    fi
}

# 增量安装场景
execute_incremental_installation() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行增量安装场景 ==="
        log_info "场景描述: 初始化创建镜像的主机"
    else
        echo "[INFO] === 执行增量安装场景 ==="
        echo "[INFO] 场景描述: 初始化创建镜像的主机"
    fi
    
    # 调用scenarios目录下的增量安装脚本
    local scenario_script="$INSTALLER_SCENARIOS_DIR/incremental_installation.sh"
    
    if [[ -f "$scenario_script" ]]; then
        if command -v log_info >/dev/null 2>&1; then
            log_info "调用增量安装场景脚本: $scenario_script"
        else
            echo "[INFO] 调用增量安装场景脚本: $scenario_script"
        fi
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        
        # 执行场景脚本
        bash "$scenario_script"
    else
        if command -v log_error >/dev/null 2>&1; then
            log_error "增量安装场景脚本不存在: $scenario_script"
        else
            echo "[ERROR] 增量安装场景脚本不存在: $scenario_script" >&2
        fi
        exit 1
    fi
}

# 版本更新场景
execute_version_upgrade() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行版本更新场景 ==="
        log_info "场景描述: 升级Datakit版本"
    else
        echo "[INFO] === 执行版本更新场景 ==="
        echo "[INFO] 场景描述: 升级Datakit版本"
    fi
    
    # 调用scenarios目录下的版本更新脚本
    local scenario_script="$INSTALLER_SCENARIOS_DIR/version_upgrade.sh"
    
    if [[ -f "$scenario_script" ]]; then
        if command -v log_info >/dev/null 2>&1; then
            log_info "调用版本更新场景脚本: $scenario_script"
        else
            echo "[INFO] 调用版本更新场景脚本: $scenario_script"
        fi
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        
        # 执行场景脚本
        bash "$scenario_script"
    else
        if command -v log_error >/dev/null 2>&1; then
            log_error "版本更新场景脚本不存在: $scenario_script"
        else
            echo "[ERROR] 版本更新场景脚本不存在: $scenario_script" >&2
        fi
        exit 1
    fi
}

# 配置更新场景
execute_config_update() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行配置更新场景 ==="
        log_info "场景描述: 仅更新配置文件"
    else
        echo "[INFO] === 执行配置更新场景 ==="
        echo "[INFO] 场景描述: 仅更新配置文件"
    fi
    
    # 调用scenarios目录下的配置更新脚本
    local scenario_script="$INSTALLER_SCENARIOS_DIR/config_update.sh"
    
    if [[ -f "$scenario_script" ]]; then
        if command -v log_info >/dev/null 2>&1; then
            log_info "调用配置更新场景脚本: $scenario_script"
        else
            echo "[INFO] 调用配置更新场景脚本: $scenario_script"
        fi
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        
        # 执行场景脚本
        bash "$scenario_script"
    else
        if command -v log_error >/dev/null 2>&1; then
            log_error "配置更新场景脚本不存在: $scenario_script"
        else
            echo "[ERROR] 配置更新场景脚本不存在: $scenario_script" >&2
        fi
        exit 1
    fi
}

# 重装场景
execute_reinstall() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 执行重装场景 ==="
        log_info "场景描述: 完全重新安装Datakit"
    else
        echo "[INFO] === 执行重装场景 ==="
        echo "[INFO] 场景描述: 完全重新安装Datakit"
    fi
    
    # 调用scenarios目录下的重装脚本
    local scenario_script="$INSTALLER_SCENARIOS_DIR/reinstall.sh"
    
    if [[ -f "$scenario_script" ]]; then
        if command -v log_info >/dev/null 2>&1; then
            log_info "调用重装场景脚本: $scenario_script"
        else
            echo "[INFO] 调用重装场景脚本: $scenario_script"
        fi
        
        # 传递配置信息给场景脚本
        export DATAKIT_CONFIG_FILE="$env_config_file"
        
        # 执行场景脚本
        bash "$scenario_script"
    else
        if command -v log_error >/dev/null 2>&1; then
            log_error "重装场景脚本不存在: $scenario_script"
        else
            echo "[ERROR] 重装场景脚本不存在: $scenario_script" >&2
        fi
        exit 1
    fi
}


# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 