#!/bin/bash

# Datakit健康检查脚本
# 功能：定期检查Datakit健康状态，异常时自动重启
# 版本：1.0.0
# 作者：Datakit运维团队

set -euo pipefail

# =============================================================================
# 加载环境配置
# =============================================================================
# 配置加载函数
load_script_config() {
    # 检查是否通过installer.sh调用，如果是则配置已加载
    # 否则尝试加载默认配置或从环境变量获取
    if [[ -z "${DATAKIT_VERSION:-}" ]]; then
        # 尝试从环境变量获取配置文件路径
        local config_file="${DATAKIT_CONFIG_FILE:-}"
        
        if [[ -n "$config_file" ]]; then
            # 加载指定的配置文件
            if [[ -f "$config_file" ]]; then
                source "$config_file"
            elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config_file" ]]; then
                source "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config_file"
            else
                echo "[ERROR] 指定的配置文件不存在: $config_file" >&2
                exit 1
            fi
        else
            # 尝试加载默认配置
            local default_configs=("benjamin.sh" "production.sh" "development.sh")
            local config_loaded=false
            
            for config in "${default_configs[@]}"; do
                if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config" ]]; then
                    echo "[INFO] 加载默认配置文件: $config"
                    source "$(dirname "${BASH_SOURCE[0]}")/../config/env/$config"
                    config_loaded=true
                    break
                fi
            done
            
            if [[ "$config_loaded" == "false" ]]; then
                echo "[ERROR] 未找到可用的配置文件，请设置 DATAKIT_CONFIG_FILE 环境变量" >&2
                exit 1
            fi
        fi
    fi
}

# 加载配置
load_script_config

# =============================================================================
# 健康检查专用配置
# =============================================================================
readonly HEALTH_CHECK_SCRIPT_NAME="datakit_health_check"
readonly HEALTH_CHECK_SCRIPT_VERSION="1.0.0"
readonly HEALTH_CHECK_LOG_FILE="/var/log/datakit_health_check.log"
readonly HEALTH_CHECK_LOCK_FILE="/var/run/datakit_health_check.lock"
readonly HEALTH_CHECK_FAILURE_COUNT_FILE="/var/run/datakit_health_check_failure_count"

# 健康检查配置
readonly HEALTH_CHECK_MAX_FAILURE_COUNT=3
readonly HEALTH_CHECK_PING_TIMEOUT=10
readonly HEALTH_CHECK_PING_URL="http://localhost:9529/v1/ping"

# =============================================================================
# 全局变量
# =============================================================================
HOST_IP=""
ENV=""
WORKSPACE=""
FAILURE_COUNT=0

# =============================================================================
# 加载核心模块
# =============================================================================
source "$CONFIG_UPDATE_CORE_DIR/logging.sh"
source "$CONFIG_UPDATE_CORE_DIR/utils.sh"
source "$CONFIG_UPDATE_CORE_DIR/validation.sh"
source "$CONFIG_UPDATE_CORE_DIR/datakit_service.sh"

# 初始化日志系统
init_logging

# =============================================================================
# 工具函数
# =============================================================================
die() {
    log_error "$1"
    dataway_log "error" "$1"
    exit 1
}

# =============================================================================
# 锁机制函数
# =============================================================================
check_lock() {
    if [ -f "$HEALTH_CHECK_LOCK_FILE" ]; then
        local pid=$(cat "$HEALTH_CHECK_LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_warning "上一个健康检查任务(PID: $pid)还在运行，跳过本次执行"
            return 1
        else
            log_warning "发现僵尸锁文件，清理并继续执行"
            rm -f "$HEALTH_CHECK_LOCK_FILE"
        fi
    fi
    return 0
}

create_lock() {
    echo $$ > "$HEALTH_CHECK_LOCK_FILE"
    log_info "创建锁文件: $HEALTH_CHECK_LOCK_FILE"
}

remove_lock() {
    rm -f "$HEALTH_CHECK_LOCK_FILE"
    log_info "清理锁文件"
}

# =============================================================================
# 失败计数管理
# =============================================================================
get_failure_count() {
    if [ -f "$HEALTH_CHECK_FAILURE_COUNT_FILE" ]; then
        cat "$HEALTH_CHECK_FAILURE_COUNT_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

set_failure_count() {
    local count="$1"
    echo "$count" > "$HEALTH_CHECK_FAILURE_COUNT_FILE"
}

reset_failure_count() {
    rm -f "$HEALTH_CHECK_FAILURE_COUNT_FILE"
}

# =============================================================================
# Datakit健康检查函数
# =============================================================================
check_datakit_health() {
    log_info "检查Datakit健康状态"
    
    # 检查Datakit进程和端口
    if ! check_datakit_status; then
        log_warning "Datakit进程或端口检查失败"
        return 1
    fi
    
    # 检查Datakit ping接口
    if timeout_execute "$HEALTH_CHECK_PING_TIMEOUT" "curl -s $HEALTH_CHECK_PING_URL" "Datakit ping接口检查"; then
        log_success "Datakit健康检查通过"
        return 0
    else
        log_warning "Datakit ping接口检查失败"
        return 1
    fi
}

# =============================================================================
# 主健康检查逻辑
# =============================================================================
perform_health_check() {
    log_info "开始Datakit健康检查"
    
    # 检查锁文件
    if ! check_lock; then
        return 0
    fi
    
    # 创建锁文件
    create_lock
    
    # 执行健康检查
    if check_datakit_health; then
        # 检查成功，重置失败计数
        local current_count=$(get_failure_count)
        if [ "$current_count" -gt 0 ]; then
            log_success "Datakit恢复正常，重置失败计数"
            dataway_log "info" "Datakit恢复正常，重置失败计数"
            reset_failure_count
        fi
    else
        # 检查失败，增加失败计数
        local current_count=$(get_failure_count)
        local new_count=$((current_count + 1))
        set_failure_count "$new_count"
        
        log_warning "Datakit健康检查失败 (第 $new_count 次)"
        dataway_log "warning" "Datakit健康检查失败 (第 $new_count 次)"
        
        # 达到最大失败次数时重启
        if [ "$new_count" -ge "$HEALTH_CHECK_MAX_FAILURE_COUNT" ]; then
            log_error "Datakit连续失败 $HEALTH_CHECK_MAX_FAILURE_COUNT 次，执行重启"
            dataway_log "error" "Datakit连续失败 $HEALTH_CHECK_MAX_FAILURE_COUNT 次，执行重启"
            
            if restart_datakit; then
                log_success "Datakit重启成功"
                dataway_log "info" "Datakit重启成功"
                reset_failure_count
            else
                log_error "Datakit重启失败"
                dataway_log "error" "Datakit重启失败"
            fi
        fi
    fi
    
    # 清理锁文件
    remove_lock
    log_info "Datakit健康检查完成"
}

# =============================================================================
# 定时任务管理
# =============================================================================
install_cron_job() {
    log_info "安装Datakit健康检查定时任务"
    
    local script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    local cron_job="*/5 * * * * $script_path >/dev/null 2>&1"
    
    # 检查是否已存在定时任务
    if crontab -l 2>/dev/null | grep -q "$script_path"; then
        log_warning "定时任务已存在"
        return 0
    fi
    
    # 添加定时任务
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    if [ $? -eq 0 ]; then
        log_success "定时任务安装成功"
        dataway_log "info" "Datakit健康检查定时任务安装成功"
    else
        log_error "定时任务安装失败"
        dataway_log "error" "Datakit健康检查定时任务安装失败"
        return 1
    fi
}

uninstall_cron_job() {
    log_info "卸载Datakit健康检查定时任务"
    
    local script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    
    # 移除定时任务
    crontab -l 2>/dev/null | grep -v "$script_path" | crontab -
    
    if [ $? -eq 0 ]; then
        log_success "定时任务卸载成功"
        dataway_log "info" "Datakit健康检查定时任务卸载成功"
    else
        log_error "定时任务卸载失败"
        dataway_log "error" "Datakit健康检查定时任务卸载失败"
        return 1
    fi
}

# =============================================================================
# 状态查询
# =============================================================================
show_status() {
    log_info "Datakit健康检查状态"
    
    # 检查锁文件
    if [ -f "$HEALTH_CHECK_LOCK_FILE" ]; then
        local pid=$(cat "$HEALTH_CHECK_LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_info "健康检查任务正在运行 (PID: $pid)"
        else
            log_warning "发现僵尸锁文件"
        fi
    else
        log_info "无运行中的健康检查任务"
    fi
    
    # 显示失败计数
    local failure_count=$(get_failure_count)
    log_info "当前失败计数: $failure_count/$HEALTH_CHECK_MAX_FAILURE_COUNT"
    
    # 检查定时任务
    local script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    if crontab -l 2>/dev/null | grep -q "$script_path"; then
        log_success "定时任务已安装"
        crontab -l | grep "$script_path"
    else
        log_warning "定时任务未安装"
    fi
    
    # 检查Datakit状态
    if check_datakit_health; then
        log_success "Datakit状态正常"
    else
        log_error "Datakit状态异常"
    fi
}

# =============================================================================
# 清理函数
# =============================================================================
cleanup() {
    log_info "清理资源"
    remove_lock
    exit 0
}

trap cleanup SIGTERM SIGINT

# =============================================================================
# 主函数
# =============================================================================
main() {
    log_info "开始执行 $HEALTH_CHECK_SCRIPT_NAME v$HEALTH_CHECK_SCRIPT_VERSION"
    
    # 检查依赖
    validate_required_commands || die "依赖检查失败"
    
    # 获取配置
    get_host_ip || die "获取主机IP失败"
    get_ops_config || log_warning "获取运维平台配置失败，使用默认配置"
    
    # 创建日志文件
    touch "$HEALTH_CHECK_LOG_FILE"
    
    # 解析命令行参数
    case "${1:-}" in
        install-cron)
            install_cron_job
            ;;
        uninstall-cron)
            uninstall_cron_job
            ;;
        status)
            show_status
            ;;
        *)
            # 默认执行健康检查
            perform_health_check
            ;;
    esac
    
    # 记录脚本结束
    SCRIPT_EXIT_CODE=0
    record_script_end
}

# =============================================================================
# 脚本入口
# =============================================================================
# 设置错误处理
trap 'SCRIPT_EXIT_CODE=$?; SCRIPT_ERROR_MESSAGE="脚本执行出错"; record_script_end; exit $SCRIPT_EXIT_CODE' ERR

main "$@" 