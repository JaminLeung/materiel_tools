#!/bin/bash

#=================================================
# 配置和验证
#=================================================
# 功能: 配置Datakit、采集器、定时任务、验证安装
#=================================================

configure_and_verify() {
    local Date=$(date +%Y%m%d%H%M%S)
    log_info "=== 配置和验证 ==="
    
    # 配置Datakit主配置文件
    if ! configure_datakit_main_config; then
        handle_error "CONFIG_ERROR" "配置Datakit主配置文件失败" "ERROR" "false"
        dataway_log "error" "配置Datakit主配置文件失败"
        return 1
    fi
    
    # 配置采集器
    if ! configure_datakit_inputs; then
        handle_error "CONFIG_ERROR" "配置采集器失败" "ERROR" "false"
        dataway_log "error" "配置采集器失败"
        return 1
    fi
    
    # 重启Datakit
    # TODO restart_datakit 提取单独封装
    if ! restart_datakit; then
        handle_error "SERVICE_ERROR" "重启Datakit失败，回退配置" "ERROR" "false"
        dataway_log "error" "重启Datakit失败，回退配置"

        # 1、获取 ops 配置，写到一个目录里
        # 2、将 datakit 已有的配置与 ops 的对比
            # - 有差异：备份整个 datakit 相关配置
            # /var/datakit/backup/20151001/
            # 保留最近 30 个版本

        # TODO 备份统一处理
        # 备份失败的配置文件
        mv "$datakit_conf" "$datakit_conf.backup.$Date.failed"

        # 还原回原来的配置文件
        mv "$datakit_conf.backup.$Date" "$datakit_conf"

        # 重启Datakit
        if ! restart_datakit; then
            handle_error "SERVICE_ERROR" "重启Datakit失败" "ERROR" "false"
            dataway_log "error" "重启Datakit失败"
            return 1
        else
            log_info "配置回退成功"
            return 0
        fi

        return 1

    fi
    
    log_info "配置完成"
    return 0
}

# 配置Datakit主配置文件
configure_datakit_main_config() {
    log_info "配置Datakit主配置文件..."
    
    local datakit_conf="/usr/local/datakit/conf.d/datakit.conf"
    
    if [ ! -f "$datakit_conf" ]; then
        handle_error "FILE_ERROR" "Datakit配置文件不存在" "ERROR" "false"
        return 1
    fi
    
    # 读取当前配置
    local current_config
    log_info "读取Datakit配置文件: $datakit_conf"
    if ! current_config=$(read_toml_config "$datakit_conf"); then
        handle_error "FILE_ERROR" "读取Datakit配置文件失败" "ERROR" "false"
        return 1
    fi
    
    # 使用jq更新配置项
    # 设置日志分片 (int类型)
    current_config=$(echo "$current_config" | jq '.logging.rotate = 32')
    log_info "设置日志分片: 32 (int类型)"
    
    # 设置HTTP API监听地址
    current_config=$(echo "$current_config" | jq '.http_api.listen = "0.0.0.0:9529"')
    log_info "设置HTTP API监听地址: 0.0.0.0:9529"
    
    # 设置Cgroup配置
    local cpu_limit=$(get_global_state 'CGROUP_CPU_LIMIT')
    local memory_limit=$(get_global_state 'CGROUP_MEMORY_LIMIT')
    
    if [ -n "$cpu_limit" ]; then
        current_config=$(echo "$current_config" | jq ".resource_limit.cpu_cores = $cpu_limit")
        log_info "设置CPU限制: $cpu_limit (float类型)"
    fi
    
    if [ -n "$memory_limit" ]; then
        current_config=$(echo "$current_config" | jq ".resource_limit.mem_max_mb = ($memory_limit | floor)")
        log_info "设置内存限制: $memory_limit MB (int类型，已去除小数点)"
    fi
    
    # 设置全局标签
    local env=$(get_global_state 'ENV')
    local workspace=$(get_global_state 'WORKSPACE')
    local global_tags=$(get_global_state 'GLOBAL_TAGS')
    
    if [ -n "$env" ]; then
        current_config=$(echo "$current_config" | jq ".global_host_tags.env = \"$env\"")
        log_info "设置环境标签: $env"
    fi
    
    if [ -n "$workspace" ]; then
        current_config=$(echo "$current_config" | jq ".global_host_tags.workspace = \"$workspace\"")
        log_info "设置工作空间标签: $workspace"
    fi
    
    # 设置GLOBAL_TAGS
    if [ -n "$global_tags" ]; then
        if echo "$global_tags" | jq -e . >/dev/null 2>&1; then
            log_info "检测到GLOBAL_TAGS为JSON对象，开始遍历配置..."
            
            local keys=$(echo "$global_tags" | jq -r 'keys[]' 2>/dev/null)
            if [ -n "$keys" ]; then
                for key in $keys; do
                    local value=$(echo "$global_tags" | jq -r ".[\"$key\"]" 2>/dev/null)
                    if [ "$value" != "null" ] && [ -n "$value" ]; then
                        current_config=$(echo "$current_config" | jq ".global_host_tags[\"$key\"] = \"$value\"")
                        log_info "设置全局标签: $key=$value (可能覆盖默认值)"
                    fi
                done
            fi
        else
            current_config=$(echo "$current_config" | jq ".global_host_tags.global_source = \"$global_tags\"")
            log_info "设置全局标签: $global_tags"
        fi
    fi
    
    # 修改Dataway地址
    local dataway_url=$(get_global_state 'DATAWAY_FULL_URL')
    current_config=$(echo "$current_config" | jq ".dataway.urls = [\"$dataway_url\"]")
    log_info "设置Dataway地址: $dataway_url"
    
    # 备份原配置文件
    cp "$datakit_conf" "$datakit_conf.backup.$Date"
    
    # 创建临时配置文件
    local temp_conf="/tmp/datakit.conf.tmp"
    
    # 使用yj将更新后的JSON转换回TOML格式
    if ! echo "$current_config" | yj -jt > "$temp_conf"; then
        handle_error "CONFIG_ERROR" "转换配置文件格式失败" "ERROR" "false"
        return 1
    fi
    
    # 替换原配置文件
    mv "$temp_conf" "$datakit_conf"
    
    # 验证配置是否正确
    if ! read_toml_config "$datakit_conf" >/dev/null; then
        handle_error "CONFIG_ERROR" "配置文件验证失败，恢复备份" "ERROR" "false"
        mv "$datakit_conf.backup.$Date" "$datakit_conf"
        return 1
    fi
    
    log_info "Datakit主配置文件配置完成"
    log_info "Datakit主配置文件配置完成"
    return 0
}

# 配置采集器
configure_datakit_inputs() {
    log_info "配置采集器..."
    
    local conf_dir="/usr/local/datakit/conf.d"
    
    # Prometheus配置
    if [ -f "$conf_dir/prom/prom_node_exporter.conf" ]; then
        cp "$conf_dir/prom/prom_node_exporter.conf" "$conf_dir/prom/prom_node_exporter.conf.backup.$Date"
    fi
    
    cat > "$conf_dir/prom/prom_node_exporter.conf" << 'EOF'
# {"version": "1.78.0", "desc": "do NOT edit this line"}

[[inputs.prom]]
  ## Exporter URLs.
  urls = ["http://127.0.0.1:9100/metrics"]

  uds_path = ""

  ## Ignore URL request errors.
  ignore_req_err = false

  ## Collector alias.
  source = "prom"

  measurement_name = "node_exporter"

  keep_exist_metric_name = true

  election = true

  ## disable setting host tag for this input
  disable_host_tag = false

  ## disable setting instance tag for this input
  disable_instance_tag = false

  ## disable info tag for this input
  disable_info_tag = false

  [[inputs.prom.measurements]]
    prefix = "etcd_network_"
    name = "etcd_network"
    
  [[inputs.prom.measurements]]
    prefix = "etcd_server_"
    name = "etcd_server"

  ## Rename tag key in prom data.
  [inputs.prom.tags_rename]
    overwrite_exist_tags = false

  [inputs.prom.as_logging]
    enable = false
    service = "service_name"

  ## Customize tags.
  # [inputs.prom.tags]
    # some_tag = "some_value"
    # more_tag = "some_other_value"
  
  ## (Optional) Collect interval: (defaults to "30s").
  # interval = "30s"

  ## (Optional) Timeout: (defaults to "30s").
  # timeout = "30s"
EOF

    # OpenTelemetry配置
    if [ -f "$conf_dir/opentelemetry/opentelemetry.conf" ]; then
        cp "$conf_dir/opentelemetry/opentelemetry.conf" "$conf_dir/opentelemetry/opentelemetry.conf.backup.$Date"
    fi
    
    cat > "$conf_dir/opentelemetry/opentelemetry.conf" << 'EOF'
# {"version": "1.78.0", "desc": "do NOT edit this line"}
[[inputs.opentelemetry]]
  [inputs.opentelemetry.http]
   enable = true
   http_status_ok = 200
   trace_api = "/otel/v1/trace"
   metric_api = "/otel/v1/metric"
   logs_api = "/otel/v1/logs"

  [inputs.opentelemetry.grpc]
   trace_enable = true
   metric_enable = true
   addr = "0.0.0.0:4317"
EOF

    # 日志配置
    if [ -f "$conf_dir/log/logging.conf" ]; then
        cp "$conf_dir/log/logging.conf" "$conf_dir/log/logging.conf.backup.$Date"
    fi
    
    cat > "$conf_dir/log/logging.conf" << 'EOF'
[[inputs.logging]]
  logfiles = [
    "/var/log/syslog",
    "/var/log/messages",
    "/var/log/dmesg",
    "/var/log/aws-routed-eni/*",
    "/var/log/secure",
    "/var/log/audit/*",
    "/var/log/lastlog",
    "/opt/datakit/*.log",
    "/var/log/datakit/log"
  ]

  ignore = [""]

  source = ""

  service = ""

  pipeline = ""

  ignore_status = []

  character_encoding = ""

  auto_multiline_detection = true
  auto_multiline_extra_patterns = []

  remove_ansi_escape_codes = false

  ignore_dead_log = "12h"

  from_beginning = false

  [inputs.logging.tags]
EOF

    # Pushgateway配置
    if [ -f "$conf_dir/pushgateway/pushgateway.conf" ]; then
        cp "$conf_dir/pushgateway/pushgateway.conf" "$conf_dir/pushgateway/pushgateway.conf.backup.$Date"
    fi
    
    cat > "$conf_dir/pushgateway/pushgateway.conf" << 'EOF'
[[inputs.pushgateway]]
  ## Prefix for the internal routes of web endpoints. Defaults to empty.
  route_prefix = "/v1/pushgateway"

  job_as_measurement = false
  keep_exist_metric_name = true
EOF

    log_info "采集器配置完成"
    log_info "采集器配置完成"
    return 0
}



 