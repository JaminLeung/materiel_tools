#!/bin/bash

#=================================================
# 脚本初始化核心函数模块
#=================================================

# 检查运行实例
check_running_instance() {
    local pid_file="${DATAKIT_PID_FILE}"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "脚本已在运行 (PID: $pid)"
            # TODO 全局不使用 log_error luke
            # TODO 全局不要出现 exit 
            exit 1
        else
            log_warning "发现过期的PID文件，清理中..."
            safe_cleanup_pid "$pid_file"
        fi
    fi
}
# TODO 需要将新的备份逻辑合入
# 创建备份目录
create_backup_directory() {
    local backup_dir="${BACKUP_DIR:-/opt/datakit_backups}"
    mkdir -p "$backup_dir"
    
    log_info "备份目录: $backup_dir"
}

# 检查当前操作权限，如果不是root，则跳过步骤，如果是则继续执行
check_current_user_permission() {
    if [[ $EUID -ne 0 ]]; then
        log_warning "非root用户运行，跳过步骤"
        # 跳过步骤
        return 1
    fi
}

# 验证系统资源（重命名避免冲突）
validate_system_resources_initialize() {
    # 检查磁盘空间
    local required_space=100  # MB
    local available_space=$(df -m / | awk 'NR==2 {print $4}')
    
    if [[ $available_space -lt $required_space ]]; then
        log_warning "磁盘空间不足: ${available_space}MB < ${required_space}MB"
        return 1
    fi
    
    return 0
}

# 验证配置参数
validate_config() {
    local current_command="${CURRENT_COMMAND:-}"
    local required_vars=()
    local missing_vars=()
    
    # 根据不同的命令设置不同的必需环境变量
    case "$current_command" in
        existing-install|incremental-install|version-upgrade|reinstall)
            # 安装相关命令需要所有环境变量
            required_vars=("DATAKIT_VERSION" "S3_BUCKET" "S3_ACCESS_KEY" "S3_SECRET_KEY" "DATAWAY_URL" "OPS_ADDR")
            ;;
        config-update)
            # 配置更新需要基本配置
            required_vars=("DATAKIT_VERSION" "DATAWAY_URL" "OPS_ADDR")
            ;;
        app-init)
            # 应用初始化需要运维平台地址
            required_vars=()
            ;;
        config-sync)
            # 配置同步需要运维平台地址
            required_vars=()
            ;;
        health-check)
            # 健康检查不需要外部环境变量
            required_vars=()
            ;;
        setup-cron)
            # 设置定时任务不需要外部环境变量
            required_vars=()
            ;;
        *)
            # 默认情况，检查所有环境变量
            required_vars=("DATAKIT_VERSION" "S3_BUCKET" "S3_ACCESS_KEY" "S3_SECRET_KEY" "DATAWAY_URL" "OPS_ADDR")
            ;;
    esac
    
    # 如果没有必需的环境变量，直接返回成功
    if [[ ${#required_vars[@]} -eq 0 ]]; then
        return 0
    fi
    
    # 检查必需的环境变量
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "缺少必需的环境变量: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

# 验证系统环境
validate_system_environment() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        handle_error "SYSTEM_ERROR" "非root用户运行，跳过步骤" "ERROR" "true"
    fi
    
    return 0
}

# 验证必需命令
validate_required_commands() {
    local required_commands=("curl" "jq" "systemctl", "yj")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "缺少必需的命令: ${missing_commands[*]}"
        return 1
    fi
    
    return 0
}

# 脚本初始化
initialize_script() {
    log_info "开始初始化脚本..."
    
    log_info "=== 生产级别脚本启动 ==="
    log_info "脚本名称: $SCRIPT_NAME"
    log_info "脚本版本: $SCRIPT_VERSION"
    log_info "启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "进程ID: $$"
    
    # 检查是否已有实例运行
    check_running_instance
    
    # 创建备份目录
    create_backup_directory
    
    # 验证系统资源
    if ! validate_system_resources_initialize; then
        log_error "系统资源验证失败"
        exit 1
    fi
    
    # TODO 去掉配置校验参数
    # 验证配置参数
    if ! validate_config; then
        log_error "配置验证失败"
        exit 1
    fi
    
    # 验证系统环境
    if ! validate_system_environment; then
        log_error "系统环境验证失败"
        exit 1
    fi
    
    # 验证必需命令
    if ! validate_required_commands; then
        log_error "必需命令验证失败"
        exit 1
    fi
    
    log_info "脚本初始化完成"
} 