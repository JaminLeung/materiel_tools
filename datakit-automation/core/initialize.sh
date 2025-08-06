#!/bin/bash

#=================================================
# 脚本初始化核心函数模块
#=================================================

# 检查运行实例
check_running_instance() {
    local pid_file="${PID_FILE:-/var/run/datakit_install.pid}"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            if command -v log_error >/dev/null 2>&1; then
                log_error "脚本已在运行 (PID: $pid)"
            else
                echo "[ERROR] 脚本已在运行 (PID: $pid)" >&2
            fi
            exit 1
        else
            if command -v log_warning >/dev/null 2>&1; then
                log_warning "发现过期的PID文件，清理中..."
            else
                echo "[WARN] 发现过期的PID文件，清理中..."
            fi
            rm -f "$pid_file"
        fi
    fi
}

# 创建备份目录
create_backup_directory() {
    local backup_dir="${BACKUP_DIR:-/opt/datakit_backups}"
    mkdir -p "$backup_dir"
    
    if command -v log_info >/dev/null 2>&1; then
        log_info "备份目录: $backup_dir"
    else
        echo "[INFO] 备份目录: $backup_dir"
    fi
}

# 检查当前操作权限，如果不是root，则跳过步骤，如果是则继续执行
check_current_user_permission() {
    if [[ $EUID -ne 0 ]]; then
        if command -v log_warning >/dev/null 2>&1; then
            log_warning "非root用户运行，跳过步骤"
        else
            echo "[WARN] 非root用户运行，跳过步骤" >&2
            # 跳过步骤
            return 1
        fi
    fi
}

# 验证系统资源（重命名避免冲突）
validate_system_resources_initialize() {
    # 检查磁盘空间
    local required_space=100  # MB
    local available_space=$(df -m / | awk 'NR==2 {print $4}')
    
    if [[ $available_space -lt $required_space ]]; then
        if command -v log_warning >/dev/null 2>&1; then
            log_warning "磁盘空间不足: ${available_space}MB < ${required_space}MB"
        else
            echo "[WARN] 磁盘空间不足: ${available_space}MB < ${required_space}MB"
        fi
        return 1
    fi
    
    return 0
}

# 验证配置参数
validate_config() {
    # 检查必需的环境变量
    local required_vars=("DATAKIT_VERSION" "S3_BUCKET" "S3_ACCESS_KEY" "S3_SECRET_KEY" "DATAWAY_URL" "OPS_ADDR")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "缺少必需的环境变量: ${missing_vars[*]}"
        else
            echo "[ERROR] 缺少必需的环境变量: ${missing_vars[*]}" >&2
        fi
        return 1
    fi
    
    return 0
}

# 验证系统环境
validate_system_environment() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        if command -v log_warning >/dev/null 2>&1; then
            log_warning "建议使用root用户运行此脚本"
        else
            echo "[WARN] 建议使用root用户运行此脚本"
        fi
    fi
    
    return 0
}

# 验证必需命令
validate_required_commands() {
    local required_commands=("curl" "jq" "systemctl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "缺少必需的命令: ${missing_commands[*]}"
        else
            echo "[ERROR] 缺少必需的命令: ${missing_commands[*]}" >&2
        fi
        return 1
    fi
    
    return 0
}

# 脚本初始化
initialize_script() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "开始初始化脚本..."
    else
        echo "[INFO] 开始初始化脚本..."
    fi
    
    if command -v log_info >/dev/null 2>&1; then
        log_info "=== 生产级别脚本启动 ==="
        log_info "脚本名称: $SCRIPT_NAME"
        log_info "脚本版本: $SCRIPT_VERSION"
        log_info "启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
        log_info "进程ID: $$"
    else
        echo "[INFO] === 生产级别脚本启动 ==="
        echo "[INFO] 脚本名称: $SCRIPT_NAME"
        echo "[INFO] 脚本版本: $SCRIPT_VERSION"
        echo "[INFO] 启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "[INFO] 进程ID: $$"
    fi
    
    # 检查是否已有实例运行
    check_running_instance
    
    # 创建备份目录
    create_backup_directory
    
    # 验证系统资源
    if ! validate_system_resources_initialize; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "系统资源验证失败"
        else
            echo "[ERROR] 系统资源验证失败" >&2
        fi
        exit 1
    fi
    
    # 验证配置参数
    if ! validate_config; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "配置验证失败"
        else
            echo "[ERROR] 配置验证失败" >&2
        fi
        exit 1
    fi
    
    # 验证系统环境
    if ! validate_system_environment; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "系统环境验证失败"
        else
            echo "[ERROR] 系统环境验证失败" >&2
        fi
        exit 1
    fi
    
    # 验证必需命令
    if ! validate_required_commands; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "必需命令验证失败"
        else
            echo "[ERROR] 必需命令验证失败" >&2
        fi
        exit 1
    fi
    
    if command -v log_success >/dev/null 2>&1; then
        log_success "脚本初始化完成"
    else
        echo "[SUCCESS] 脚本初始化完成"
    fi
} 