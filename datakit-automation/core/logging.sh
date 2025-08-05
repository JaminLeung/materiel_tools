#!/bin/bash

#=================================================
# 日志系统模块
#=================================================
# 功能: 多级别日志记录、结构化日志输出、日志轮转管理
#=================================================

# 颜色定义（兼容性版本）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志级别定义（兼容性版本）
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARNING=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_SUCCESS=4

# 当前日志级别（可通过环境变量设置）
CURRENT_LOG_LEVEL=${LOG_LEVEL:-1}  # 默认INFO级别

# 日志文件路径（可通过环境变量设置）
if [ -z "${LOG_FILE:-}" ]; then
    LOG_FILE="/var/log/datakit_install.log"
fi

# 日志系统初始化
init_logging() {
    local log_file="${LOG_FILE}"
    touch "$log_file" 2>/dev/null || {
        echo "警告：无法创建日志文件 $log_file，将输出到标准输出"
        LOG_FILE="/dev/null"
    }
}

# 通用日志函数
log_message() {
    local level="$1"
    local message="$2"
    local color="$NC"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    
    # 根据日志级别设置颜色
    case "$level" in
        "DEBUG") color="$BLUE" ;;
        "INFO") color="$BLUE" ;;
        "WARNING") color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
        "SUCCESS") color="$GREEN" ;;
    esac
    
    # 检查日志级别
    local level_num=1
    case "$level" in
        "DEBUG") level_num=$LOG_LEVEL_DEBUG ;;
        "INFO") level_num=$LOG_LEVEL_INFO ;;
        "WARNING") level_num=$LOG_LEVEL_WARNING ;;
        "ERROR") level_num=$LOG_LEVEL_ERROR ;;
        "SUCCESS") level_num=$LOG_LEVEL_SUCCESS ;;
    esac
    
    if [ "$level_num" -ge "$CURRENT_LOG_LEVEL" ]; then
        local formatted_message="${timestamp} [${level}] ${message}"
        echo -e "${color}${formatted_message}${NC}" | tee -a "${LOG_FILE}"
    fi
}

# 便捷日志函数
log_debug() { log_message "DEBUG" "$1"; }
log_info() { log_message "INFO" "$1"; }
log_warning() { log_message "WARNING" "$1"; }
log_error() { log_message "ERROR" "$1"; }
log_success() { log_message "SUCCESS" "$1"; }

# 记录脚本启动
record_script_start() {
    local start_info=$(cat <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "script_name": "$SCRIPT_NAME",
    "script_version": "$SCRIPT_VERSION",
    "pid": "$$",
    "action": "start",
    "hostname": "$(hostname)",
    "user": "$(whoami)"
}
EOF
)
    echo "$start_info" >> "${LOG_FILE}.json"
}

# 记录脚本结束
record_script_end() {
    local end_info=$(cat <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "script_name": "$SCRIPT_NAME",
    "script_version": "$SCRIPT_VERSION",
    "pid": "$$",
    "action": "end",
    "exit_code": "${SCRIPT_EXIT_CODE:-0}",
    "total_time": "${PERFORMANCE_TOTAL_TIME:-0}",
    "current_step": "${SCRIPT_CURRENT_STEP:-unknown}",
    "error_message": "${SCRIPT_ERROR_MESSAGE:-}"
}
EOF
)
    echo "$end_info" >> "${LOG_FILE}.json"
}

# 输出性能指标
output_performance_metrics() {
    log_info "=== 性能指标 ==="
    log_info "总运行时间: ${PERFORMANCE_METRICS[TOTAL_TIME]}秒"
    log_info "下载时间: ${PERFORMANCE_METRICS[DOWNLOAD_TIME]}秒"
    log_info "安装时间: ${PERFORMANCE_METRICS[INSTALL_TIME]}秒"
    log_info "配置时间: ${PERFORMANCE_METRICS[CONFIG_TIME]}秒"
} 