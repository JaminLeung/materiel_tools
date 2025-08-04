#!/bin/bash

#=================================================
# 步骤1: 获取主机信息
#=================================================
# 功能: 获取本机IP、调用运维平台API获取配置
#=================================================

step_01_get_host_info() {
    log_info "=== 步骤1: 获取主机信息 ==="
    
    # 获取本机IP地址
    if ! get_host_ip; then
        log_error "获取本机IP地址失败"
        dataway_log "error" "获取本机IP地址失败"
        return 1
    fi
    
    # 获取运维平台配置
    if ! get_ops_config; then
        log_warning "获取运维平台配置失败，使用默认配置"
        dataway_log "warning" "获取运维平台配置失败，使用默认配置"
        
        # 设置默认配置
        set_global_state "ENV" "test"
        set_global_state "WORKSPACE" "default"
        set_global_state "GLOBAL_TAGS" "{}"
        set_global_state "WORKSPACE_TOKEN" "default_token"
        set_global_state "DATAWAY_FULL_URL" "$DATAWAY_LOG_URL"
        
        log_info "使用默认配置:"
        log_info "  - 环境: test"
        log_info "  - 工作空间: default"
        log_info "  - Dataway地址: $DATAWAY_LOG_URL"
    fi
    
    # 验证主机信息完整性
    if ! validate_host_info; then
        log_error "主机信息验证失败"
        dataway_log "error" "主机信息验证失败"
        return 1
    fi
    
    log_success "主机信息获取完成"
    dataway_log "info" "主机信息获取完成"
    return 0
}

# 验证主机信息完整性
validate_host_info() {
    log_info "验证主机信息完整性..."
    
    local host_ip=$(get_global_state 'HOST_IP')
    local env=$(get_global_state 'ENV')
    local workspace=$(get_global_state 'WORKSPACE')
    local workspace_token=$(get_global_state 'WORKSPACE_TOKEN')
    local dataway_full_url=$(get_global_state 'DATAWAY_FULL_URL')
    
    # 检查必需的信息
    if [ -z "$host_ip" ]; then
        log_error "主机IP地址为空"
        return 1
    fi
    
    if [ -z "$env" ]; then
        log_error "环境信息为空"
        return 1
    fi
    
    if [ -z "$workspace" ]; then
        log_error "工作空间信息为空"
        return 1
    fi
    
    if [ -z "$workspace_token" ]; then
        log_error "工作空间Token为空"
        return 1
    fi
    
    if [ -z "$dataway_full_url" ]; then
        log_error "Dataway地址为空"
        return 1
    fi
    
    log_info "主机信息验证通过:"
    log_info "  - 主机IP: $host_ip"
    log_info "  - 环境: $env"
    log_info "  - 工作空间: $workspace"
    log_info "  - Dataway地址: $dataway_full_url"
    
    return 0
} 