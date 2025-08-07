#!/bin/bash

#=================================================
# 步骤1: 获取主机信息
#=================================================
# 功能: 获取本机IP、调用运维平台API获取配置
#=================================================

get_host_info() {
    log_info "=== 获取主机信息 ==="
    
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
        

        
        # 使用缺省配置逻辑
        local dataway_url="${DATAWAY_LOG_URL:-${DATAWAY_URL:-${CONFIG_UPDATE_DATAWAY_URL:-}}}"
        local env="${ENV:-test}"
        local workspace="${WORKSPACE:-default}"

 
        if [ -n "$dataway_url" ]; then
            set_global_state "DATAWAY_FULL_URL" "$dataway_url"
            log_info "使用默认配置:"
            log_info "  - 环境: $env"
            log_info "  - 工作空间: $workspace"
            log_info "  - Dataway地址: $dataway_url"
        else
            log_error "所有Dataway URL都未设置"
            return 1
        fi
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
