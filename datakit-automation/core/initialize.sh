#!/bin/bash

#=================================================
# 脚本初始化核心函数模块
#=================================================

# 简单的safe_execute函数（如果utils模块未加载）
if ! command -v safe_execute >/dev/null 2>&1; then
    safe_execute() {
        local cmd="$1"
        local description="${2:-执行命令}"
        
        log_info "$description: $cmd"
        if eval "$cmd"; then
            log_info "$description 成功"
            return 0
        else
            local exit_code=$?
            log_error "$description 失败"
            return $exit_code
        fi
    }
fi


# 检查运行实例
check_running_instance() {

    # 需要跳过的命令清单
    local skip_command_list=(
        "app-init"
        "config-update"
    )
    command=$(get_global_state "command")
    # 如果是command_list 中的命令，则需要判断是否存在与当前进程不一样pid的datakit_auto_installer.sh进程，如果存在则退出
    if [[ " ${skip_command_list[@]} " =~ " $command " ]]; then
        # 如果存在与当前进程不一样pid的datakit_auto_installer.sh进程，则退出
        if [ $(pgrep -f "datakit_auto_installer.sh" | grep -v $$ | wc -l) -gt 1 ]; then
            handle_error "COMMAND_ERROR" "命令正在执行中，请勿重复执行" "WARNING" "true"
        fi

        if [[ "$command" == "app-init" ]]; then
            # 如果存在与当前进程不一样pid的datakit_auto_installer.sh进程，则退出
            if [ $(pgrep -f "/usr/local/datakit/datakit" | grep -v $$ | wc -l) == 0 ]; then
                handle_error "COMMAND_ERROR" "Datakit未运行，跳过app-init执行" "WARNING" "true"
            fi
        fi
    fi
}

# =============================================================================
# Runtime目录管理
# =============================================================================

# 初始化运行时环境（整合版本）
init_runtime_environment() {
    local create_release="${1:-false}"
    local script_type="${2:-}"
    
    log_info "初始化运行时环境"
    
    # # 初始化安全删除目录
    # init_safe_delete_dir
    
    # 创建基础运行时目录
    init_base_runtime_dirs
    
    # 如果需要创建版本目录
    if [ "$create_release" = "true" ]; then
        create_release_directories "$script_type"
    fi
    
    log_info "运行时环境初始化完成"
}

# 创建基础运行时目录
init_base_runtime_dirs() {
    local dirs=(
        "$RUNTIME_DIR"
        "$RUNTIME_DIR"/releases
        "$RUNTIME_DIR"/releases/current
        "$RUNTIME_DIR"/releases/archive
        "$RUNTIME_DIR"/releases/current/$(get_global_state "RELEASE_ID")
        "$RUNTIME_DIR"/releases/current/$(get_global_state "RELEASE_ID")/log
        "$RUNTIME_DIR"/releases/current/$(get_global_state "RELEASE_ID")/backup
        "$RUNTIME_DIR"/releases/current/$(get_global_state "RELEASE_ID")/tmp
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            safe_execute "mkdir -p '$dir'" "创建运行时目录: $dir"
        fi
    done
    set_global_state "RUNTIME_RELEASE_DIR" "$RUNTIME_DIR/releases/current/$(get_global_state "RELEASE_ID")"
    # 设置基础目录权限
    safe_execute "chmod 755 '$RUNTIME_DIR'" "设置运行时根目录权限" || true
    safe_execute "chmod 755 '$RUNTIME_DIR/releases'" "设置运行时版本目录权限" || true
    safe_execute "chmod 755 '$RUNTIME_DIR/releases/current'" "设置运行时当前版本目录权限" || true
    safe_execute "chmod 755 '$RUNTIME_DIR/releases/archive'" "设置运行时归档版本目录权限" || true
    # safe_execute "chmod 755 '$RUNTIME_TMP_ROOT'" "设置临时目录权限" || true
    # safe_execute "chmod 755 '$RUNTIME_DIFF_ROOT'" "设置对比目录权限" || true
}

# 创建版本目录
create_release_directories() {
    local script_type="$1"
    local runtime_release="$RUNTIME_DIR/releases/current/$(get_global_state "RELEASE_ID")"
    
    log_info "创建版本目录: $runtime_release"
    
    # 创建版本目录结构
    local release_dirs=(
        "$runtime_release"
        "$runtime_release/backup"
        "$runtime_release/conf"
        "$runtime_release/log" 
        "$runtime_release/tmp"
    )
    
    # 根据脚本类型添加特定目录
    case "$script_type" in
        "app_init")
            release_dirs+=(
                "$runtime_release/backup/app_init"
                # 移除临时目录，app_init已改造为配置项级直接对比
            )
            ;;
        "config_update")
            release_dirs+=(
                "$runtime_release/backup/config_update"
            )
            ;;
        "health_check")
            release_dirs+=(
                "$runtime_release/backup/health_check"
            )
            ;;
    esac
    
    # 创建目录
    for dir in "${release_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            safe_execute "mkdir -p '$dir'" "创建版本目录: $dir"
        fi
    done
    
    # 设置版本目录权限
    safe_execute "chmod 755 '$runtime_release'" "设置版本目录权限" || true
    
    
    # 设置全局变量供其他函数使用
    set_global_state "RUNTIME_RELEASE" "$runtime_release"
    set_global_state "RUNTIME_RELEASE_LOG_DIR" "$runtime_release/log"

    set_global_state "RUNTIME_BACKUP_DIR" "$runtime_release/backup"
    set_global_state "RUNTIME_TMP_DIR" "$runtime_release/tmp"
    

    log_info "版本目录创建完成: $runtime_release"
    
}

# =============================================================================
# 备份管理（与Runtime整合）
# =============================================================================

# 注意：以下函数已移动到 error_handler.sh 中
# - init_safe_delete_dir
# - safe_delete

# 注意：以下清理函数已移动到 error_handler.sh 中
# - cleanup_safe_delete_dir
# - cleanup_old_runtime_releases  
# - cleanup_expired_logs_safe

# 清理旧备份目录（基于文件数保留版本）
# 详细说明函数功能
# 1. 清理旧备份目录（按文件数保留）
# 2. 清理过期备份目录
# 3. 清理过期配置
# 4. 清理过期配置同步
# 5. 清理过期健康检查
# 6. 清理过期应用初始化
cleanup_old_backups() {
    local backup_base_dir="$1"
    local max_backups="${2:-$BACKUP_MAX_FILES}"
    local backup_type="${3:-}"
    
    log_info "清理旧备份目录（保留最新的 $max_backups 个备份）"
    
    if [ ! -d "$backup_base_dir" ]; then
        log_info "备份基础目录不存在，跳过清理"
        return 0
    fi
    
    # 确保安全删除目录存在
    if ! command -v init_safe_delete_dir >/dev/null 2>&1; then
        log_warning "安全删除函数不可用，跳过备份目录清理"
        return 1
    fi
    
    init_safe_delete_dir
    
    # 统计当前备份目录数量
    local current_backups=$(find "$backup_base_dir" -maxdepth 1 -type d -name "20*" | wc -l)
    log_info "当前备份目录数量: $current_backups"
    log_info "最大保留备份目录数量: $max_backups"
    
    if [ "$current_backups" -gt "$max_backups" ]; then
        log_info "清理旧备份目录，保留最新的 $max_backups 个备份"
        
        # 查找需要删除的备份目录（按修改时间排序，保留最新的）
        local dirs_to_delete=$(find "$backup_base_dir" -maxdepth 1 -type d -name "20*" -printf '%T@ %p\n' | sort -n | head -n $((current_backups - max_backups)) | awk '{print $2}' 2>/dev/null)
        
        local deleted_count=0
        if [ -n "$dirs_to_delete" ]; then
            for dir in $dirs_to_delete; do
            if [ -d "$dir" ]; then
                local dir_name=$(basename "$dir")
                log_info "安全删除旧备份目录: $dir_name"
                if safe_delete "$dir" "移动旧备份目录"; then
                    deleted_count=$((deleted_count + 1))
                fi
            fi
        done
        fi
        
        log_info "备份目录清理完成，删除了 $deleted_count 个旧备份目录"
    else
        log_info "备份目录数量 ($current_backups) 未超过限制 ($max_backups)，无需清理"
    fi
}

# 计算日期差
calculate_days_diff() {
    local date1="$1"
    local date2="$2"
    
    if command_exists dateutils.ddiff; then
        dateutils.ddiff "$date1" "$date2" 2>/dev/null || echo "999"
    else
        # 简单的日期比较（假设日期格式为YYYYMMDD）
        local year1=${date1:0:4}
        local month1=${date1:4:2}
        local day1=${date1:6:2}
        local year2=${date2:0:4}
        local month2=${date2:4:2}
        local day2=${date2:6:2}
        
        # 使用10进制避免八进制问题
        year1=$((10#$year1))
        month1=$((10#$month1))
        day1=$((10#$day1))
        year2=$((10#$year2))
        month2=$((10#$month2))
        day2=$((10#$day2))
        
        echo $(( (year2 - year1) * 365 + (month2 - month1) * 30 + (day2 - day1) ))
    fi
}

# =============================================================================
# 兼容性函数（标记为废弃）
# =============================================================================

# 废弃：初始化运行时目录（保持向后兼容）
# init_runtime_dirs() {
#     log_warning "init_runtime_dirs 函数已废弃，请使用 init_runtime_environment"
#     local runtime_root="${1:-$RUNTIME_DIR}"
#     local create_release="${2:-false}"
    
#     # 调用新的函数
#     init_runtime_environment "$create_release"
# }

# # 废弃：清理旧备份目录（保持向后兼容）
cleanup_old_backup_dirs() {
    log_warning "cleanup_old_backup_dirs 函数已废弃，请使用 cleanup_old_backups"
    local backup_base_dir="$1"
    local keep_days="${2:-7}"
    
    # 调用新的函数
    cleanup_old_backups "$backup_base_dir" "$keep_days"
}

# =============================================================================
# 原有函数（调整TODO项）
# =============================================================================

# 创建备份目录 并备份Datakit配置目录
create_backup_directory() {
    RUNTIME_RELEASE_DIR=$(get_global_state "RUNTIME_RELEASE_DIR")
    local backup_dir="${RUNTIME_RELEASE_DIR}/backup"
    local backup_dir_tmp="/tmp"
    safe_execute "mkdir -p '$backup_dir'" "创建备份目录"
    log_info "备份目录: $backup_dir"
    # 安全删除 
    if [ -d "$backup_dir/conf.d" ]; then    
        if safe_execute "mv '$backup_dir/conf.d' '$backup_dir_tmp/conf.d_before_$RELEASE_ID'" "安全删除备份目录"; then
            log_info "备份目录安全删除完成"
        else
                handle_error "BACKUP_ERROR" "现有的备份目录安全删除失败，请手动删除" "CRITICAL" "false"
        fi
    fi

    # 备份Datakit配置目录
    if safe_execute "cp -rf '/usr/local/datakit/conf.d' '$backup_dir'" "备份Datakit配置目录"; then
        log_info "Datakit配置目录备份完成: $backup_dir/conf.d"
    else
        handle_error "BACKUP_ERROR" "Datakit配置目录备份失败" "CRITICAL" "false"
    fi
}

# 检查当前操作权限，如果不是root，则跳过步骤，如果是则继续执行
check_current_user_permission() {
    if [[ $EUID -ne 0 ]]; then
        log_warning "非root用户运行，某些操作可能受限"
        return 1
    fi
    return 0
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



# 验证系统环境
validate_system_environment() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        log_warning "建议使用root用户运行此脚本"
        # 非root用户不退出，只是警告
    fi
    
    return 0
}

# 验证必需命令
validate_required_commands() {
    local required_commands=("curl" "jq" "systemctl" "yj")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        handle_error "VALIDATION_ERROR" "缺少必需的命令: ${missing_commands[*]}" "CRITICAL" "true"
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
    

    
    # 初始化安全删除目录
    init_safe_delete_dir
    
    if [ -d "/usr/local/datakit/conf.d" ]; then
        log_info "Datakit 文件目录存在，进行备份"
        # 创建备份目录并备份Datakit配置目录
        create_backup_directory
    else
        log_info "Datakit 文件目录不存在，跳过备份"
    fi


    
    # 验证系统资源
    if ! validate_system_resources_initialize; then
        handle_error "VALIDATION_ERROR" "系统资源验证失败" "CRITICAL" "true"
    fi
    

    
    # 验证系统环境
    if ! validate_system_environment; then
        handle_error "VALIDATION_ERROR" "系统环境验证失败" "CRITICAL" "true"
    fi
    
    # 验证必需命令
    #if ! validate_required_commands; then
    #    handle_error "VALIDATION_ERROR" "必需命令验证失败" "CRITICAL" "true"
    #fi
    
    # 注意：cleanup_safe_delete_dir 已移动到 error_handler.sh 中，会在脚本退出时自动调用
    
    log_info "脚本初始化完成"
} 
