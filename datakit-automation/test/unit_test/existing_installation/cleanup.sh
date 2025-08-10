#!/bin/bash

#=================================================
# 临时文件清理脚本
#=================================================
# 功能: 清理单元测试产生的临时文件
#=================================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_info() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# 清理所有临时文件
cleanup_all_temp_files() {
    local pattern="${1:-datakit_unit_test.*}"
    local temp_dirs=()
    local cleaned_count=0
    
    log_info "查找临时目录 (模式: $pattern)..."
    
    # 查找所有匹配的临时目录
    while IFS= read -r -d '' dir; do
        temp_dirs+=("$dir")
    done < <(find /tmp -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null)
    
    if [[ ${#temp_dirs[@]} -eq 0 ]]; then
        log_info "未找到需要清理的临时目录"
        return 0
    fi
    
    log_info "找到 ${#temp_dirs[@]} 个临时目录需要清理"
    
    # 清理每个临时目录
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "清理临时目录: $dir"
            if rm -rf "$dir" 2>/dev/null; then
                ((cleaned_count++))
                log_info "已清理: $dir"
            else
                log_error "清理失败: $dir"
            fi
        fi
    done
    
    log_info "清理完成，共清理 $cleaned_count 个临时目录"
}

# 清理测试相关的临时文件
cleanup_test_temp_files() {
    log_info "清理测试相关的临时文件..."
    
    # 清理测试日志文件
    cleanup_log_files
    
    # 清理可能残留的测试文件
    local test_files=(
        "/tmp/datakit_test.log"
        "/tmp/datakit_*.log"
        "/tmp/test_*.log"
    )
    
    for pattern in "${test_files[@]}"; do
        find /tmp -maxdepth 1 -name "$(basename "$pattern")" -delete 2>/dev/null || true
    done
    
    log_info "测试临时文件清理完成"
}

# 清理日志文件
cleanup_log_files() {
    log_info "清理日志文件..."
    
    local log_patterns=(
        "datakit_test.log"
        "datakit_*.log"
        "test_*.log"
        "unit_test_*.log"
    )
    
    local cleaned_count=0
    
    for pattern in "${log_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            if rm -f "$file" 2>/dev/null; then
                ((cleaned_count++))
                log_info "已清理日志文件: $file"
            fi
        done < <(find /tmp -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
    done
    
    log_info "日志文件清理完成，共清理 $cleaned_count 个文件"
}

# 清理孤立的临时文件（超过指定时间的）
cleanup_orphaned_temp_files() {
    local pattern="${1:-datakit_unit_test.*}"
    local max_age_hours="${2:-1}"
    
    log_info "清理孤立的临时文件 (超过 ${max_age_hours} 小时)..."
    
    local cleaned_count=0
    
    # 查找超过指定时间的临时目录
    while IFS= read -r -d '' dir; do
        local dir_age_seconds=$(( $(date +%s) - $(stat -c %Y "$dir") ))
        local max_age_seconds=$(printf "%.0f" $(echo "$max_age_hours * 3600" | bc -l 2>/dev/null || echo "3600"))
        
        if [[ $dir_age_seconds -gt $max_age_seconds ]]; then
            local dir_age_hours=$(printf "%.2f" $(echo "scale=2; $dir_age_seconds / 3600" | bc -l 2>/dev/null || echo "0"))
            log_info "清理过期临时目录: $dir (已存在 ${dir_age_hours} 小时)"
            if rm -rf "$dir" 2>/dev/null; then
                ((cleaned_count++))
                log_info "已清理: $dir"
            else
                log_error "清理失败: $dir"
            fi
        fi
    done < <(find /tmp -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null)
    
    log_info "孤立临时文件清理完成，共清理 $cleaned_count 个目录"
}

# 强制清理所有临时文件（谨慎使用）
cleanup_force_temp_files() {
    local pattern="${1:-datakit_unit_test.*}"
    
    log_warning "⚠️  强制清理所有临时文件 (模式: $pattern)"
    log_warning "这将删除所有匹配的临时目录，请确认..."
    
    read -p "确认要强制清理所有临时文件吗？(y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "开始强制清理..."
        cleanup_all_temp_files "$pattern"
    else
        log_info "取消强制清理"
    fi
}

# 显示临时文件统计信息
show_temp_files_stats() {
    local pattern="${1:-datakit_unit_test.*}"
    
    log_info "临时文件统计信息 (模式: $pattern)..."
    
    local temp_dirs=()
    local total_size=0
    
    # 查找所有匹配的临时目录
    while IFS= read -r -d '' dir; do
        temp_dirs+=("$dir")
        local dir_size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo "0")
        total_size=$((total_size + dir_size))
    done < <(find /tmp -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null)
    
    echo ""
    echo "=========================================="
    echo "临时文件统计"
    echo "=========================================="
    echo "临时目录数量: ${#temp_dirs[@]}"
    echo "总大小: $(numfmt --to=iec $total_size 2>/dev/null || echo "${total_size} bytes")"
    echo ""
    
    if [[ ${#temp_dirs[@]} -gt 0 ]]; then
        echo "临时目录列表:"
        echo "------------------------------------------"
        for dir in "${temp_dirs[@]}"; do
            local dir_size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "未知")
            local dir_age=$(( ( $(date +%s) - $(stat -c %Y "$dir") ) / 60 ))
            echo "$dir ($dir_size, ${dir_age}分钟前)"
        done
    fi
    
    echo ""
}

# 显示使用说明
show_usage() {
    cat << EOF
临时文件清理脚本

用法: $0 [选项] [参数]

选项:
  -h, --help              显示此帮助信息
  -a, --all               清理所有临时文件 (默认)
  -t, --test              清理测试相关的临时文件
  -l, --logs              清理日志文件
  -o, --orphaned [小时]   清理孤立的临时文件 (默认1小时)
  -f, --force             强制清理所有临时文件 (需要确认)
  -s, --stats             显示临时文件统计信息
  -p, --pattern PATTERN   指定临时目录匹配模式 (默认: datakit_unit_test.*)

示例:
  $0                      # 清理所有临时文件
  $0 --all                # 清理所有临时文件
  $0 --test               # 清理测试相关文件
  $0 --logs               # 清理日志文件
  $0 --orphaned 2         # 清理超过2小时的孤立文件
  $0 --force              # 强制清理所有临时文件
  $0 --stats              # 显示临时文件统计信息
  $0 --pattern "test_*"   # 清理匹配test_*模式的临时目录

说明:
  - 默认清理模式为 datakit_unit_test.*
  - 孤立文件清理默认超过1小时
  - 强制清理需要用户确认
  - 统计信息显示目录大小和创建时间

EOF
}

# 主函数
main() {
    local cleanup_type="all"
    local show_stats=false
    local pattern="datakit_unit_test.*"
    local orphaned_hours=1
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -a|--all)
                cleanup_type="all"
                shift
                ;;
            -t|--test)
                cleanup_type="test"
                shift
                ;;
            -l|--logs)
                cleanup_type="logs"
                shift
                ;;
            -o|--orphaned)
                cleanup_type="orphaned"
                if [[ -n "$2" && "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    orphaned_hours="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -f|--force)
                cleanup_type="force"
                shift
                ;;
            -s|--stats)
                show_stats=true
                shift
                ;;
            -p|--pattern)
                pattern="$2"
                shift 2
                ;;
            *)
                echo "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 处理统计信息显示
    if [[ "$show_stats" == "true" ]]; then
        show_temp_files_stats "$pattern"
        exit 0
    fi
    
    # 执行清理操作
    case "$cleanup_type" in
        "all")
            cleanup_all_temp_files "$pattern"
            ;;
        "test")
            cleanup_test_temp_files
            ;;
        "logs")
            cleanup_log_files
            ;;
        "orphaned")
            cleanup_orphaned_temp_files "$pattern" "$orphaned_hours"
            ;;
        "force")
            cleanup_force_temp_files "$pattern"
            ;;
        *)
            log_error "未知的清理类型: $cleanup_type"
            show_usage
            exit 1
            ;;
    esac
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 