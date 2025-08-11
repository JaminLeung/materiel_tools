#!/bin/bash

#=================================================
# 日志系统模块
#=================================================
# 功能: 结构化日志、日志轮转、性能优化、监控告警
#=================================================

#=================================================
# 常量定义
#=================================================



# 日志级别定义
LOG_LEVELS_NAMES=("DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL" "SUCCESS")
LOG_LEVELS_VALUES=(0 1 2 3 4 5)

# 日志级别颜色映射
LOG_COLORS_NAMES=("DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL" "SUCCESS")
LOG_COLORS_VALUES=("$CYAN" "$BLUE" "$YELLOW" "$RED" "$PURPLE" "$GREEN")


#=================================================
# 配置变量（从配置文件加载，这里只提供默认值作为后备）
#=================================================

LOG_FILE="${LOG_FILE:-/var/log/datakit_install.log}"
LOG_FORMAT="json"  # 统一使用JSON格式


#=================================================
# 日志格式生成
#=================================================

# 生成JSON格式日志消息
generate_structured_log() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    local extra_fields="${4:-}"
    
    local timestamp=$(date -Iseconds)
    local pid=$$
    local script_name="${SCRIPT_NAME:-$(basename "$0")}"
    local script_version="${SCRIPT_VERSION:-unknown}"
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local user=$(whoami 2>/dev/null || echo "unknown")
    
    # TODO 日志格式改为一行
    local json_log=$(cat <<EOF
{
    "timestamp": "$timestamp",
    "level": "$level",
    "message": "$message",
    "pid": $pid,
    "script_name": "$script_name",
    "script_version": "$script_version",
    "hostname": "$hostname",
    "user": "$user",
    "context": "$context"$extra_fields
}
EOF
)
    echo "$json_log"
}


#=================================================
# 日志写入
#=================================================

# 写入日志到文件
write_log_to_file() {
    local log_message="$1"
    local level="$2"
    
    # 直接写入日志文件
    if [[ -n "$LOG_FILE" && "$LOG_FILE" != "/dev/null" ]]; then
        echo "$log_message" >> "$LOG_FILE" 2>/dev/null || {
            # 如果写入失败，输出到stderr
            echo "$log_message" >&2
        }
    fi
}



#=================================================
# 核心日志函数
#=================================================

# 核心日志函数
log_message() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    local extra_fields="${4:-}"
     
    # 生成日志消息
    local log_message=$(generate_structured_log "$level" "$message" "$context" "$extra_fields")
    
    echo "$log_message"
    
    # 写入日志文件
    write_log_to_file "$log_message" "$level"
}

# 便捷日志函数
log_debug() { log_message "DEBUG" "$1" "${2:-}" "${3:-}"; }
log_info() { log_message "INFO" "$1" "${2:-}" "${3:-}"; }
log_warning() { log_message "WARNING" "$1" "${2:-}" "${3:-}"; }
log_error() { log_message "ERROR" "$1" "${2:-}" "${3:-}"; }
log_critical() { log_message "CRITICAL" "$1" "${2:-}" "${3:-}"; }
log_success() { log_message "SUCCESS" "$1" "${2:-}" "${3:-}"; }


#=================================================
# 系统管理函数
#=================================================

# 日志系统初始化
init_logging() {
    local log_file="${LOG_FILE}"
    local log_dir=$(dirname "$log_file")
    
    # 创建日志目录
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            echo "警告：无法创建日志目录 $log_dir，将输出到标准输出" >&2
            LOG_FILE="/dev/null"
            return 1
        }
    fi
    
    # 创建日志文件
    touch "$log_file" 2>/dev/null || {
        echo "警告：无法创建日志文件 $log_file，将输出到标准输出" >&2
        LOG_FILE="/dev/null"
        return 1
    }
    
    # 设置文件权限
    chmod 644 "$log_file" 2>/dev/null || true
    
    # 记录初始化信息
    local init_message=$(generate_structured_log "INFO" "日志系统初始化完成" "logging_init" ", \"log_file\": \"$log_file\")
    echo "$init_message" >> "$log_file"
    
    return 0
}

# 清理历史日志文件
cleanup_old_logs() {
    local log_dir=$(dirname "$LOG_FILE")
    local base_name=$(basename "$LOG_FILE" | cut -d. -f1)
    local retention_days="${LOG_RETENTION_DAYS:-30}"
    
    log_info "开始清理 $retention_days 天前的日志文件" "log_cleanup"
    
    # 查找并删除过期的日志文件
    local deleted_count=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$log_dir" -name "${base_name}.*" -type f -mtime +$retention_days -print0 2>/dev/null)
    
    log_info "清理完成，删除了 $deleted_count 个过期日志文件" "log_cleanup"
}


#=================================================
# 命令行接口
#=================================================

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "init")
            init_logging
            ;;
        "cleanup")
            cleanup_old_logs
            ;;
        "test")
            init_logging
            log_debug "这是一条调试日志"
            log_info "这是一条信息日志"
            log_warning "这是一条警告日志"
            log_error "这是一条错误日志"
            log_critical "这是一条严重错误日志"
            log_info "这是一条成功日志"
            ;;
        *)
            echo "用法: $0 {init|cleanup|test}"
            echo ""
            echo "命令说明:"
            echo "  init    - 初始化日志系统"
            echo "  cleanup - 清理过期日志文件"
            echo "  test    - 测试日志功能"
            ;;
    esac
fi 