#!/bin/bash

# Datakit健康检查脚本
# 功能：定期检查Datakit健康状态，异常时自动重启
# 版本：2.0.0
# 作者：Datakit运维团队

set -euo pipefail

# =============================================================================
# 加载基础配置
# =============================================================================
# 获取脚本所在目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载基础配置
source "$SCRIPT_DIR/../config/base/base_config.sh" 2>/dev/null || echo "警告: 无法加载base_config.sh" >&2

# =============================================================================
# 配置变量（从base_config.sh加载）
# =============================================================================
# 直接使用base_config.sh中的HEALTH_CHECK_变量，无需重新赋值

# =============================================================================
# 全局变量
# =============================================================================
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
# 注意：die函数已废弃，使用handle_error替代

# =============================================================================
# 锁机制函数
# =============================================================================
check_lock() {
    if [ -f "$HEALTH_CHECK_LOCK_FILE" ]; then
        local pid=$(cat "$HEALTH_CHECK_LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            record_error "SERVICE_ERROR" "上一个健康检查任务(PID: $pid)还在运行，跳过本次执行" "WARNING"
            return 1
        else
            record_error "SERVICE_ERROR" "发现僵尸锁文件，清理并继续执行" "WARNING"
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
        record_error "SERVICE_ERROR" "Datakit进程或端口检查失败" "WARNING"
        return 1
    fi
    
    # 检查Datakit ping接口
    if timeout_execute "$HEALTH_CHECK_PING_TIMEOUT" "curl -s $HEALTH_CHECK_PING_URL" "Datakit ping接口检查"; then
        log_success "Datakit健康检查通过"
        return 0
    else
        record_error "SERVICE_ERROR" "Datakit ping接口检查失败" "WARNING"
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
            reset_failure_count
        fi
    else
        # 检查失败，增加失败计数
        local current_count=$(get_failure_count)
        local new_count=$((current_count + 1))
        set_failure_count "$new_count"
        
        record_error "SERVICE_ERROR" "Datakit健康检查失败 (第 $new_count 次)" "WARNING"
        
        # 达到最大失败次数时重启
        if [ "$new_count" -ge "$HEALTH_CHECK_MAX_FAILURE_COUNT" ]; then
            handle_error "SERVICE_ERROR" "Datakit连续失败 $HEALTH_CHECK_MAX_FAILURE_COUNT 次，执行重启" "ERROR" "false"
            
            if restart_datakit; then
                log_success "Datakit重启成功"
                reset_failure_count
            else
                handle_error "SERVICE_ERROR" "Datakit重启失败" "ERROR" "false"
            fi
        fi
    fi
    
    # 清理锁文件
    remove_lock
    log_info "Datakit健康检查完成"
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
            record_error "SERVICE_ERROR" "发现僵尸锁文件" "WARNING"
        fi
    else
        log_info "无运行中的健康检查任务"
    fi
    
    # 显示失败计数
    local failure_count=$(get_failure_count)
    log_info "当前失败计数: $failure_count/$HEALTH_CHECK_MAX_FAILURE_COUNT"
    
    # 检查Datakit状态
    if check_datakit_health; then
        log_success "Datakit状态正常"
    else
        handle_error "SERVICE_ERROR" "Datakit状态异常" "ERROR" "false"
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
    validate_required_commands || {
        handle_error "DEPENDENCY_ERROR" "依赖检查失败" "ERROR" "false"
        return 1
    }
    
    # 创建日志文件
    touch "$HEALTH_CHECK_LOG_FILE"
    
    # 解析命令行参数
    case "${1:-}" in
        status)
            show_status
            ;;
        *)
            # 默认执行健康检查
            perform_health_check
            ;;
    esac
}

# =============================================================================
# 脚本入口
# =============================================================================
main "$@" 