#!/bin/bash

# Datakit 资源限制设置脚本
# 功能: 根据机器硬件规格自动设置 datakit 服务的 CPU 和内存限制

set -euo pipefail

# 日志函数
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"
} 

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 错误处理函数
handle_error() {
    local error_message="$1"
    log_error "$error_message"
    exit 1
}

# 检查依赖工具
check_dependencies() {
    log_info "检查依赖工具..."
    
    local missing_tools=()
    
    # 检查 bc 命令
    if ! command -v bc &> /dev/null; then
        missing_tools+=("bc")
    fi
    
    # 检查 lscpu 命令
    if ! command -v lscpu &> /dev/null; then
        missing_tools+=("lscpu")
    fi
    
    # 检查 free 命令
    if ! command -v free &> /dev/null; then
        missing_tools+=("free")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        handle_error "缺少必要工具: ${missing_tools[*]}"
    fi
    
    log_info "依赖工具检查通过"
}

# 获取机器规格
get_machine_specs() {
    log_info "获取机器规格..."
    
    # 获取CPU核心数
    local cpu_cores
    cpu_cores=$(lscpu | grep "CPU(s)" | cut -d ':' -f 2 | sed 's/^ //' | awk '{print $1}' | head -n 1)
    
    # 获取内存大小（GB）
    local memory_gb
    memory_gb=$(free -g | grep "Mem" | awk '{print $2}')
    
    # 验证获取的数据
    if [[ ! "$cpu_cores" =~ ^[0-9]+$ ]] || [[ ! "$memory_gb" =~ ^[0-9]+$ ]]; then
        handle_error "无法正确获取机器规格: CPU=${cpu_cores}, 内存=${memory_gb}GB"
    fi
    
    log_info "机器规格: ${cpu_cores}核 ${memory_gb}GB"
    
    # 设置全局变量
    MACHINE_CPU_CORES="$cpu_cores"
    MACHINE_MEMORY_GB="$memory_gb"
}

# 计算资源限制
calculate_resource_limits() {
    local cpu_cores="$1"
    local memory_gb="$2"
    
    log_info "计算资源限制..."
    
    local cpu_limit
    local memory_limit_mb
    
    # 根据规格设置资源限制
    if [ "$cpu_cores" -lt 4 ] || [ "$memory_gb" -lt 8 ]; then
        # 2C4G ~ 4C8G: 使用规格的12.5%，最低0.5C0.5G
        log_info "小规格机器 (< 4C8G)，使用动态资源限制"
        
        # 计算原始限制
        local cpu_limit_raw
        cpu_limit_raw=$(echo "$cpu_cores * 0.125" | bc)
        
        local memory_limit_raw_mb
        memory_limit_raw_mb=$(echo "$memory_gb * 0.125 * 1024" | bc)
        
        # 确保最低限制：0.5C0.5G
        if (( $(echo "$cpu_limit_raw < 0.5" | bc -l) )); then
            cpu_limit="0.5"
        else
            cpu_limit="$cpu_limit_raw"
        fi
        
        if (( $(echo "$memory_limit_raw_mb < 512" | bc -l) )); then
            memory_limit_mb="512"  # 0.5GB = 512MB
        else
            memory_limit_mb=$(echo "$memory_limit_raw_mb" | bc)
        fi
        
        log_info "动态资源限制计算:"
        log_info "  CPU原始限制: ${cpu_limit_raw}C (规格的12.5%)"
        log_info "  内存原始限制: ${memory_limit_raw_mb}MB (规格的12.5%)"
        log_info "  CPU最终限制: ${cpu_limit}C"
        log_info "  内存最终限制: ${memory_limit_mb}MB"
        
    else
        # ≥ 4C8G: 使用固定限制
        log_info "大规格机器 (≥ 4C8G)，使用固定资源限制"
        cpu_limit="1"
        memory_limit_mb="2048"
        log_info "固定资源限制: ${cpu_limit}C ${memory_limit_mb}MB"
    fi
    
    # 验证资源限制是否满足最低要求
    if (( $(echo "$cpu_limit < 0.5" | bc -l) )) || (( $(echo "$memory_limit_mb < 512" | bc -l) )); then
        handle_error "资源限制不满足最低要求: CPU=${cpu_limit}C, 内存=${memory_limit_mb}MB"
    fi
    
    log_info "资源限制验证通过: CPU=${cpu_limit}C, 内存=${memory_limit_mb}MB"
    
    # 设置全局变量
    CPU_LIMIT="$cpu_limit"
    MEMORY_LIMIT_MB="$memory_limit_mb"
}

# 备份服务文件
backup_service_file() {
    local service_file="/etc/systemd/system/datakit.service"
    local backup_file="/etc/systemd/system/datakit.service.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$service_file" ]; then
        log_info "备份服务文件到: $backup_file"
        cp "$service_file" "$backup_file"
        log_info "服务文件备份完成"
    else
        log_warn "服务文件不存在: $service_file"
    fi
}

# 检查是否需要更新服务配置
check_service_config() {
    local cpu_limit="$1"
    local memory_limit_mb="$2"
    local service_file="/etc/systemd/system/datakit.service"
    
    if [ ! -f "$service_file" ]; then
        log_warn "服务文件不存在: $service_file"
        return 1  # 需要更新
    fi
    
    # 将CPU限制转换为systemd CPUQuota百分比
    local expected_cpu_quota
    expected_cpu_quota=$(echo "scale=4; $cpu_limit / $MACHINE_CPU_CORES * 100" | bc | sed 's/\.00*$//' | sed 's/\(.*\..\)0*$/\1/')
    
    # 获取当前配置
    local current_cpu_quota
    local current_memory_limit
    current_cpu_quota=$(grep "^CPUQuota=" "$service_file" | cut -d'=' -f2 | sed 's/%//')
    current_memory_limit=$(grep "^MemoryLimit=" "$service_file" | cut -d'=' -f2 | sed 's/M//')
    
    log_info "配置比较:"
    log_info "  当前 CPUQuota: ${current_cpu_quota}%"
    log_info "  期望 CPUQuota: ${expected_cpu_quota}%"
    log_info "  当前 MemoryLimit: ${current_memory_limit}M"
    log_info "  期望 MemoryLimit: ${memory_limit_mb}M"
    
    # 比较配置是否一致
    if [ "$current_cpu_quota" = "$expected_cpu_quota" ] && [ "$current_memory_limit" = "$memory_limit_mb" ]; then
        log_info "服务配置与期望一致，无需更新"
        return 0  # 不需要更新
    else
        log_info "服务配置与期望不一致，需要更新"
        return 1  # 需要更新
    fi
}

# 更新服务文件
update_service_file() {
    local cpu_limit="$1"
    local memory_limit_mb="$2"
    local service_file="/etc/systemd/system/datakit.service"
    
    log_info "更新服务文件: $service_file"
    
    if [ ! -f "$service_file" ]; then
        handle_error "服务文件不存在: $service_file"
    fi
    
    # 将CPU限制转换为systemd CPUQuota百分比 (限制的CPU核数/总CPU核数 * 100%)
    local cpu_quota_percent
    cpu_quota_percent=$(echo "scale=4; $cpu_limit / $MACHINE_CPU_CORES * 100" | bc | sed 's/\.00*$//' | sed 's/\(.*\..\)0*$/\1/')
    
    # 创建临时文件
    local temp_file
    temp_file=$(mktemp)
    
    # 更新服务文件
    awk -v cpu_quota="$cpu_quota_percent%" -v memory_limit="${memory_limit_mb}M" '
    /^CPUQuota=/ { 
        print "CPUQuota=" cpu_quota; 
        next 
    }
    /^MemoryLimit=/ { 
        print "MemoryLimit=" memory_limit; 
        next 
    }
    { print }
    ' "$service_file" > "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$service_file"
    
    log_info "服务文件更新完成:"
    log_info "  CPUQuota=${cpu_quota_percent}%"
    log_info "  MemoryLimit=${memory_limit_mb}M"
}

# 重载systemd配置
reload_systemd() {
    log_info "重载 systemd 配置..."
    
    if ! systemctl daemon-reload; then
        handle_error "systemd 配置重载失败"
    fi
    log_info "systemd 配置重载成功"
}

# 重启datakit服务
restart_datakit_service() {
    log_info "重启 datakit 服务..."
    
    if ! systemctl restart datakit; then
        handle_error "datakit 服务重启失败"
    fi
    
    log_info "datakit 服务重启成功"
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet datakit; then
        log_info "datakit 服务运行正常"
    else
        log_warn "datakit 服务可能未正常运行，请检查状态"
        systemctl status datakit --no-pager -l || true
    fi
}

# 显示当前配置
show_current_config() {
    local service_file="/etc/systemd/system/datakit.service"
    
    log_info "当前 datakit 服务配置:"
    if [ -f "$service_file" ]; then
        grep -E "^(CPUQuota|MemoryLimit)=" "$service_file" | while read -r line; do
            log_info "  $line"
        done
    else
        log_warn "服务文件不存在"
    fi
}

# 主函数
main() {
    log_info "开始设置 datakit 资源限制..."
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        handle_error "请使用 root 用户运行此脚本"
    fi
    
    # 检查依赖
    check_dependencies
    
    # 获取机器规格
    get_machine_specs
    
    # 计算资源限制
    calculate_resource_limits "$MACHINE_CPU_CORES" "$MACHINE_MEMORY_GB"
    
    # 显示当前配置
    show_current_config
    
    # 检查是否需要更新服务配置
    local service_file="/etc/systemd/system/datakit.service"
    local current_memory_limit=""
    
    if [ -f "$service_file" ]; then
        current_memory_limit=$(grep "^MemoryLimit=" "$service_file" | cut -d'=' -f2 | sed 's/M//')
    fi
    
    if check_service_config "$CPU_LIMIT" "$MEMORY_LIMIT_MB"; then
        log_info "服务配置无需更新，跳过重启"
    else
        # 备份服务文件
        backup_service_file
        
        # 更新服务文件
        update_service_file "$CPU_LIMIT" "$MEMORY_LIMIT_MB"
        
        # 重载systemd配置
        reload_systemd
        
        # 检查是否需要重启服务（内存限制修改需要重启）
        if [ "$current_memory_limit" != "$MEMORY_LIMIT_MB" ]; then
            log_info "内存限制已修改，需要重启服务"
            restart_datakit_service
        else
            log_info "仅CPU限制修改，无需重启服务"
        fi
    fi
    
    # 显示最终配置
    log_info "资源限制设置完成!"
    show_current_config
    
    # 计算实际分配的百分比
    local cpu_percent
    cpu_percent=$(echo "scale=3; $CPU_LIMIT / $MACHINE_CPU_CORES * 100" | bc | sed 's/\.00*$//' | sed 's/\(.*\..\)0*$/\1/')
    log_info "设置完成: ${MACHINE_CPU_CORES}核${MACHINE_MEMORY_GB}GB -> ${CPU_LIMIT}C(${cpu_percent}%)${MEMORY_LIMIT_MB}MB"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
