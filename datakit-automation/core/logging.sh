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
    local release_id="${RELEASE_ID:-unknown}"
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local user=$(whoami 2>/dev/null || echo "unknown")

    # 日志格式修改成一行，方便数据上报
    local json_log=$(cat <<EOF
{"timestamp": "$timestamp","level": "$level","message": "$message","pid": $pid,"script_name": "$script_name","script_version": "$script_version","release_id": "$release_id","hostname": "$hostname","user": "$user","context": "$context","extra_fields": "$extra_fields"}
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
    local script_type="${1:-unknown}"
    local log_file="${LOG_FILE}"
    
    # 如果LOG_FILE已经设置且包含执行时间戳，说明已经初始化过
    if [[ "$LOG_FILE" =~ .*_[0-9]{8}_[0-9]{6}\.log$ ]]; then
        log_info "日志系统已初始化，跳过重复初始化" "logging_init"
        return 0
    fi
    
    # 生成执行起始时间
    local execution_start_time=$(get_execution_start_time "$script_type")
    
    # 如果LOG_FILE是相对路径或未设置，使用默认路径
    if [[ -z "$log_file" ]] || [[ "$log_file" != /* ]]; then
        # 确保RUNTIME_LOG_CURRENT_DIR已定义
        if [[ -z "${RUNTIME_LOG_CURRENT_DIR:-}" ]]; then
            RUNTIME_LOG_CURRENT_DIR="${RUNTIME_LOG_DIR:-/tmp}/current"
        fi
        log_file="$RUNTIME_LOG_CURRENT_DIR/$script_type/${execution_start_time}.log"
    fi
    
    # 创建日志目录
    local log_dir=$(dirname "$log_file")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            log_error "无法创建日志目录: $log_dir" "logging_init"
            return 1
        }
    fi
    
    # # 设置日志文件路径
    # export LOG_FILE="$log_file"
    # export SCRIPT_EXECUTION_START_TIME="$execution_start_time"
    
    # # 创建软链接到latest.log
    # local latest_link="$log_dir/latest.log"
    # if [[ -L "$latest_link" ]]; then
    #     rm -f "$latest_link"
    # fi
    # ln -sf "$(basename "$log_file")" "$latest_link" 2>/dev/null || true
    
    # 初始化日志文件
    touch "$log_file" || {
        log_error "无法创建日志文件: $log_file" "logging_init"
        return 1
    }
    
    log_info "日志系统初始化完成: $log_file" "logging_init"
    return 0
}

# 生成执行ID（基于执行起始时间）
generate_execution_id() {
    local script_type="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local pid=$$
    echo "${script_type}_${timestamp}_${pid}"
}

# 获取脚本执行起始时间
get_execution_start_time() {
    local script_type="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    echo "${script_type}_${timestamp}"
}

# 清理历史日志文件
cleanup_old_logs() {
    local log_dir=$(dirname "$LOG_FILE")
    local base_name=$(basename "$LOG_FILE" | cut -d. -f1)
    local retention_days="${LOG_RETENTION_DAYS:-3}"

    log_info "开始清理 $retention_days 天前的日志文件" "log_cleanup"

    # 确保安全删除目录存在
    if command -v init_safe_delete_dir >/dev/null 2>&1; then
        init_safe_delete_dir
    else
        log_warning "安全删除函数不可用，跳过日志清理" "log_cleanup"
        return 1
    fi

    # 查找并安全删除过期的日志文件
    local deleted_count=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            if safe_delete "$file" "清理过期日志文件"; then
                deleted_count=$((deleted_count + 1))
            fi
        fi
    done < <(find "$log_dir" -name "${base_name}.*" -type f -mtime +$retention_days -print0 2>/dev/null)

    log_info "清理完成，安全删除了 $deleted_count 个过期日志文件" "log_cleanup"
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
            log_success "这是一条成功日志"
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