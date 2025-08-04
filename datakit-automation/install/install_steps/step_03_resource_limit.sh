#!/bin/bash

#=================================================
# 步骤3: 设置资源限制
#=================================================
# 功能: 获取机器规格并设置资源限制
#=================================================

step_03_set_resource_limits() {
    log_info "=== 步骤3: 设置资源限制 ==="
    
    # 验证系统资源
    if ! validate_system_resources; then
        log_error "系统资源验证失败"
        dataway_log "error" "系统资源验证失败"
        return 1
    fi
    
    # 获取机器规格并设置资源限制
    if ! get_machine_specs; then
        log_error "获取机器规格失败"
        dataway_log "error" "获取机器规格失败"
        return 1
    fi
    
    # 验证资源限制设置
    if ! validate_resource_limits; then
        log_error "资源限制验证失败"
        dataway_log "error" "资源限制验证失败"
        return 1
    fi
    
    log_success "资源限制设置完成"
    dataway_log "info" "资源限制设置完成"
    return 0
}

# 验证资源限制设置
validate_resource_limits() {
    log_info "验证资源限制设置..."
    
    local cpu_limit=$(get_global_state 'CGROUP_CPU_LIMIT')
    local memory_limit=$(get_global_state 'CGROUP_MEMORY_LIMIT')
    
    if [ -z "$cpu_limit" ]; then
        log_error "CPU限制未设置"
        return 1
    fi
    
    if [ -z "$memory_limit" ]; then
        log_error "内存限制未设置"
        return 1
    fi
    
    # 验证CPU限制格式
    if ! [[ "$cpu_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "CPU限制格式错误: $cpu_limit"
        return 1
    fi
    
    # 验证内存限制格式
    if ! [[ "$memory_limit" =~ ^[0-9]+$ ]]; then
        log_error "内存限制格式错误: $memory_limit"
        return 1
    fi
    
    # 验证限制值合理性
    if (( $(echo "$cpu_limit < 0.1" | bc -l) )); then
        log_error "CPU限制过小: $cpu_limit"
        return 1
    fi
    
    if [ "$memory_limit" -lt 128 ]; then
        log_error "内存限制过小: ${memory_limit}MB"
        return 1
    fi
    
    log_info "资源限制验证通过:"
    log_info "  - CPU限制: ${cpu_limit}C"
    log_info "  - 内存限制: ${memory_limit}MB"
    
    return 0
} 