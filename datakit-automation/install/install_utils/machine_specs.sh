#!/bin/bash

#=================================================
# 机器规格检测工具模块
#=================================================
# 功能: 获取机器规格、设置资源限制
#=================================================

# 获取本机IP地址
get_host_ip() {
    log_info "获取本机IP地址..."
    
    # 使用 `ip` 命令获取主网卡的 IP 地址，排除回环地址
    local host_ip=$(ip -4 addr show | grep -v '127.0.0.1' | awk '/inet/ {print $2}' | cut -d'/' -f1 | head -n 1)
    
    # 如果没有找到 IP 地址，尝试使用 `ifconfig` 命令
    if [ -z "$host_ip" ]; then
        host_ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
    fi
    
    if [ -z "$host_ip" ]; then
        log_error "无法获取本机IP地址"
        return 1
    fi
    
    # 设置全局状态
    set_global_state "HOST_IP" "$host_ip"
    log_success "获取到本机IP地址: $host_ip"
    return 0
}

# 获取机器规格并设置资源限制
get_machine_specs() {
    log_info "获取机器规格并设置资源限制..."
    
    # 获取CPU规格
    local cpu_cores=$(lscpu | grep "CPU(s)" | cut -d ':' -f 2 | sed 's/^ //' | awk '{print $1}' | head -n 1)
    
    # 获取内存规格（GB）
    local memory_gb=$(free -g | grep "Mem" | awk '{print $2}')
    
    log_info "机器规格: ${cpu_cores}核 ${memory_gb}GB"
    
    # 根据规格设置资源限制
    if [ "$cpu_cores" -lt 4 ] || [ "$memory_gb" -lt 8 ]; then
        # 2C4G ~ 4C8G: 使用规格的12.5%，最低0.5C0.5G
        local cpu_limit_raw=$(echo "$cpu_cores * 0.125" | bc | sed 's/^\./0./' | sed 's/\.$//')
        local memory_limit_raw=$(echo "$memory_gb * 0.125 * 1024" | bc | sed 's/^\./0./' | sed 's/\.$//')
        
        # 确保最低限制：0.5C0.5G
        local cpu_limit
        if (( $(echo "$cpu_limit_raw < 0.5" | bc -l) )); then
            cpu_limit="0.5"
        else
            cpu_limit="$cpu_limit_raw"
        fi
        
        local memory_limit
        if (( $(echo "$memory_limit_raw < 0.5" | bc -l) )); then
            memory_limit="512"  # 0.5GB = 512MB
        else
            memory_limit=$(echo "$memory_limit_raw " | bc | sed 's/^\./0./' | sed 's/\.$//')    
        fi
        
        # 设置全局状态
        set_global_state "CGROUP_CPU_LIMIT" "$cpu_limit"
        set_global_state "CGROUP_MEMORY_LIMIT" "$memory_limit"
        
        log_info "2C4G~4C8G 规格资源限制计算:"
        log_info "CPU原始限制: ${cpu_limit_raw}C (规格的12.5%)"
        log_info "内存原始限制: ${memory_limit_raw}GB (规格的12.5%)"
        log_info "CPU最终限制: ${cpu_limit}C (应用最低限制0.5C)"
        log_info "内存最终限制: ${memory_limit}MB (应用最低限制0.5GB)"
        log_info "设置动态资源限制: ${cpu_limit}C${memory_limit}MB"
        
    else
        # ≥ 4C8G: 使用固定限制
        set_global_state "CGROUP_CPU_LIMIT" "1"
        set_global_state "CGROUP_MEMORY_LIMIT" "2048"
        log_info "≥4C8G规格，设置默认资源限制: 1C2G"
    fi
    
    dataway_log "info" "设置资源限制: $(get_global_state 'CGROUP_CPU_LIMIT')C$(get_global_state 'CGROUP_MEMORY_LIMIT')MB"
}

# 验证系统资源
validate_system_resources() {
    log_info "验证系统资源..."
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "磁盘空间不足: 可用 ${available_space}KB，需要 ${required_space}KB"
        return 1
    fi
    
    # 检查内存
    local available_memory=$(free -k | awk 'NR==2 {print $7}')
    local required_memory=524288  # 512MB in KB
    
    if [[ $available_memory -lt $required_memory ]]; then
        log_warning "可用内存较少: 可用 ${available_memory}KB，建议 ${required_memory}KB"
    fi
    
    # 检查CPU负载
    local load_average=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    if (( $(echo "$load_average > 5.0" | bc -l) )); then
        log_warning "系统负载较高: $load_average"
    fi
    
    log_success "系统资源验证通过"
    return 0
} 