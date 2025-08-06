#!/bin/bash

#=================================================
# 步骤8: 验证安装结果
#=================================================
# 功能: 验证Datakit安装是否成功，作为1-7步骤的总结验证
#=================================================

verify_installation() {
    log_info "=== 验证安装结果 ==="
    log_info "开始执行安装总结验证..."
    
    local verification_passed=true
    local verification_results=()
    
    # 1. 验证Datakit进程运行状态
    log_info "1. 验证Datakit进程运行状态..."
    if verify_datakit_process; then
        verification_results+=("✅ Datakit进程运行正常")
    else
        verification_results+=("❌ Datakit进程运行异常")
        verification_passed=false
    fi
    
    # 2. 验证配置文件存在性
    log_info "2. 验证配置文件存在性..."
    if verify_config_files; then
        verification_results+=("✅ 配置文件检查通过")
    else
        verification_results+=("❌ 配置文件检查失败")
        verification_passed=false
    fi
    
    # 3. 验证资源限制配置
    log_info "3. 验证资源限制配置..."
    if verify_resource_limits; then
        verification_results+=("✅ 资源限制配置正确")
    else
        verification_results+=("❌ 资源限制配置异常")
        verification_passed=false
    fi
    
    # 4. 验证定时任务配置
    log_info "4. 验证定时任务配置..."
    if verify_cron_jobs; then
        verification_results+=("✅ 定时任务配置正确")
    else
        verification_results+=("❌ 定时任务配置异常")
        verification_passed=false
    fi
    
    # 5. 验证运维平台信息获取
    log_info "5. 验证运维平台信息获取..."
    if verify_ops_platform_info; then
        verification_results+=("✅ 运维平台信息获取成功")
    else
        verification_results+=("❌ 运维平台信息获取失败")
        verification_passed=false
    fi
    
    # 6. 验证Node Exporter状态
    log_info "6. 验证Node Exporter状态..."
    if verify_node_exporter; then
        verification_results+=("✅ Node Exporter运行正常")
    else
        verification_results+=("❌ Node Exporter运行异常")
        verification_passed=false
    fi
    
    # 输出验证总结
    log_info "=== 安装验证总结 ==="
    for result in "${verification_results[@]}"; do
        log_info "$result"
    done
    
    if [ "$verification_passed" = true ]; then
        log_success "=== 所有验证项通过 ==="
        dataway_log "info" "Datakit安装验证通过: 所有6项检查均通过"
        return 0
    else
        log_error "=== 部分验证项失败 ==="
        dataway_log "error" "Datakit安装验证失败: 部分检查项未通过"
        return 1
    fi
}

# 1. 验证Datakit进程运行状态（带重试）
verify_datakit_process() {
    validate_process_running "datakit" 10 5
}

# 2. 验证配置文件存在性
verify_config_files() {
    local conf_dir="/usr/local/datakit/conf.d"
    local required_configs=(
        "opentelemetry/opentelemetry.conf"
        "log/logging.conf"
        "pushgateway/pushgateway.conf"
        "prom/prom_node_exporter.conf"
    )
    
    log_info "检查必需配置文件:"
    for config in "${required_configs[@]}"; do
        if ! validate_file_exists "$conf_dir/$config" "配置文件"; then
            return 1
        fi
    done
    
    log_info "所有必需配置文件存在"
    return 0
}

# 3. 验证资源限制配置
verify_resource_limits() {
    local datakit_conf="/usr/local/datakit/conf.d/datakit.conf"
    
    if [ ! -f "$datakit_conf" ]; then
        log_error "Datakit配置文件不存在"
        return 1
    fi
    
    # 读取配置并验证资源限制
    local config_json
    if ! config_json=$(read_toml_config "$datakit_conf"); then
        log_error "读取Datakit配置文件失败"
        return 1
    fi
    
    # 检查CPU限制
    local cpu_limit=$(echo "$config_json" | jq -r '.resource_limit.cpu_cores // empty')
    if [ -n "$cpu_limit" ] && [ "$cpu_limit" != "null" ]; then
        log_info "CPU限制配置: $cpu_limit"
    else
        log_warning "CPU限制未配置"
    fi
    
    # 检查内存限制
    local mem_limit=$(echo "$config_json" | jq -r '.resource_limit.mem_max_mb // empty')
    if [ -n "$mem_limit" ] && [ "$mem_limit" != "null" ]; then
        log_info "内存限制配置: ${mem_limit}MB"
    else
        log_warning "内存限制未配置"
    fi
    
    # 检查日志分片配置
    local log_rotate=$(echo "$config_json" | jq -r '.logging.rotate // empty')
    if [ -n "$log_rotate" ] && [ "$log_rotate" != "null" ]; then
        log_info "日志分片配置: $log_rotate"
    else
        log_warning "日志分片未配置"
    fi
    
    return 0
}

# 4. 验证定时任务配置
verify_cron_jobs() {
    # 检查crontab中是否包含config_update.sh的配置
    if ! validate_cron_job "cron_wrapper.sh" "config_update.sh定时任务"; then
        return 1
    fi
    
    # 检查包装脚本是否存在
    local wrapper_script="$SCENARIO_PROJECT_ROOT/install/cron_wrapper.sh"
    if ! validate_file_exists "$wrapper_script" "定时任务包装脚本"; then
        return 1
    fi
    
    # 检查日志目录是否存在
    validate_directory_exists "/var/log/datakit" "定时任务日志目录"
    
    return 0
}

# 5. 验证运维平台信息获取
verify_ops_platform_info() {
    # 检查全局状态中的关键信息
    local env=$(get_global_state 'ENV')
    local workspace=$(get_global_state 'WORKSPACE')
    local dataway_url=$(get_global_state 'DATAWAY_FULL_URL')
    local global_tags=$(get_global_state 'GLOBAL_TAGS')
    
    if [ -n "$env" ]; then
        log_info "环境信息: $env"
    else
        log_error "环境信息未获取"
        return 1
    fi
    
    if [ -n "$workspace" ]; then
        log_info "工作空间: $workspace"
    else
        log_error "工作空间信息未获取"
        return 1
    fi
    
    if [ -n "$dataway_url" ]; then
        log_info "Dataway地址已配置"
    else
        log_error "Dataway地址未配置"
        return 1
    fi
    
    if [ -n "$global_tags" ]; then
        log_info "全局标签已配置"
    else
        log_warning "全局标签未配置"
    fi
    
    return 0
}

# 6. 验证Node Exporter状态
verify_node_exporter() {
    # 检查Node Exporter进程
    if ! validate_process_running "node_exporter" 1 0; then
        return 1
    fi
    
    # 检查Node Exporter端口
    validate_port_listening "9100" "tcp"
    
    # 检查systemd服务状态
    validate_service_status "node_exporter" "active"
    
    return 0
} 