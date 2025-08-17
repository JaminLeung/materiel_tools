#!/bin/bash

#=================================================
# Datakit 状态配置文件
#=================================================
# 管理脚本运行时的状态变量
#=================================================

# 注意：此文件由配置加载器自动加载，无需手动source

# =============================================================================
# 全局状态变量
# =============================================================================
HOST_IP=""
ENV=""
WORKSPACE=""
GLOBAL_TAGS=""
WORKSPACE_TOKEN=""
DATAWAY_FULL_URL=""
CGROUP_CPU_LIMIT=""
CGROUP_MEMORY_LIMIT=""

# =============================================================================
# 脚本状态变量
# =============================================================================
SCRIPT_START_TIME=""
SCRIPT_END_TIME=""
SCRIPT_EXIT_CODE=""
SCRIPT_ERROR_MESSAGE=""
SCRIPT_CURRENT_STEP=""
SCRIPT_BACKUP_CREATED="false"
SCRIPT_LOCK_ACQUIRED="false"

# =============================================================================
# 性能监控变量
# =============================================================================
PERFORMANCE_DOWNLOAD_TIME=""
PERFORMANCE_INSTALL_TIME=""
PERFORMANCE_CONFIG_TIME=""
PERFORMANCE_TOTAL_TIME=""

# =============================================================================
# 安装状态变量
# =============================================================================
INSTALL_STATUS=""
INSTALL_ERROR=""
DATAKIT_STATUS=""
NODE_EXPORTER_STATUS=""

# =============================================================================
# 状态管理函数
# =============================================================================

# 初始化状态
init_state() {
    SCRIPT_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    SCRIPT_CURRENT_STEP="初始化"
    SCRIPT_EXIT_CODE=""
    SCRIPT_ERROR_MESSAGE=""
    SCRIPT_BACKUP_CREATED="false"
    SCRIPT_LOCK_ACQUIRED="false"
    
    # 设置基础环境信息
    ENV="${DATAKIT_ENV:-dev}"
    WORKSPACE="${WORKSPACE:-default}"
    
    # 获取主机IP（如果可能）
    if [[ -z "$HOST_IP" ]]; then
        HOST_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    fi
}

# 更新当前步骤
update_current_step() {
    SCRIPT_CURRENT_STEP="$1"
    log_info "当前步骤: $SCRIPT_CURRENT_STEP"
}

# 记录性能指标
record_performance() {
    local metric="$1"
    local value="$2"
    
    case "$metric" in
        "download") PERFORMANCE_DOWNLOAD_TIME="$value" ;;
        "install") PERFORMANCE_INSTALL_TIME="$value" ;;
        "config") PERFORMANCE_CONFIG_TIME="$value" ;;
        "total") PERFORMANCE_TOTAL_TIME="$value" ;;
        *) log_warning "未知的性能指标: $metric" ;;
    esac
    
    log_info "性能指标记录: $metric = $value"
}

# 设置安装状态
set_install_status() {
    INSTALL_STATUS="$1"
    if [ -n "$2" ]; then
        INSTALL_ERROR="$2"
        log_error "安装状态: $INSTALL_STATUS, 错误: $INSTALL_ERROR"
    else
        log_info "安装状态: $INSTALL_STATUS"
    fi
}

# 设置服务状态
set_service_status() {
    local service="$1"
    local status="$2"
    
    case "$service" in
        "datakit") DATAKIT_STATUS="$status" ;;
        "node_exporter") NODE_EXPORTER_STATUS="$status" ;;
        *) log_warning "未知的服务: $service" ;;
    esac
    
    log_info "服务状态更新: $service = $status"
}

# 完成脚本执行
finish_script() {
    SCRIPT_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    SCRIPT_EXIT_CODE="${1:-0}"
    if [ -n "$2" ]; then
        SCRIPT_ERROR_MESSAGE="$2"
    fi
    
    log_info "脚本执行完成，退出码: $SCRIPT_EXIT_CODE"
    if [[ -n "$SCRIPT_ERROR_MESSAGE" ]]; then
        log_error "错误信息: $SCRIPT_ERROR_MESSAGE"
    fi
}

# 获取状态摘要
get_state_summary() {
    cat << EOF
状态摘要:
  主机IP: $HOST_IP
  环境: $DATAKIT_ENV
  工作空间: $WORKSPACE
  当前步骤: $SCRIPT_CURRENT_STEP
  开始时间: $SCRIPT_START_TIME
  结束时间: $SCRIPT_END_TIME
  退出码: $SCRIPT_EXIT_CODE
  安装状态: $INSTALL_STATUS
  Datakit状态: $DATAKIT_STATUS
  Node Exporter状态: $NODE_EXPORTER_STATUS
EOF
}

# 重置状态
reset_state() {
    HOST_IP=""
    ENV=""
    WORKSPACE=""
    GLOBAL_TAGS=""
    WORKSPACE_TOKEN=""
    DATAWAY_FULL_URL=""
    CGROUP_CPU_LIMIT=""
    CGROUP_MEMORY_LIMIT=""
    
    SCRIPT_START_TIME=""
    SCRIPT_END_TIME=""
    SCRIPT_EXIT_CODE=""
    SCRIPT_ERROR_MESSAGE=""
    SCRIPT_CURRENT_STEP=""
    SCRIPT_BACKUP_CREATED="false"
    SCRIPT_LOCK_ACQUIRED="false"
    
    PERFORMANCE_DOWNLOAD_TIME=""
    PERFORMANCE_INSTALL_TIME=""
    PERFORMANCE_CONFIG_TIME=""
    PERFORMANCE_TOTAL_TIME=""
    
    INSTALL_STATUS=""
    INSTALL_ERROR=""
    DATAKIT_STATUS=""
    NODE_EXPORTER_STATUS=""
    
    log_info "状态已重置"
}

# =============================================================================
# 日志函数（如果尚未定义）
# =============================================================================
if ! declare -F log_info >/dev/null; then
    log_info() {
        echo "[INFO] $1" >&2
    }
fi

if ! declare -F log_warn >/dev/null; then
    log_warn() {
        echo "[WARN] $1" >&2
    }
fi

if ! declare -F log_error >/dev/null; then
    log_error() {
        echo "[ERROR] $1" >&2
    }
fi 