#!/bin/bash

# Datakit SSM主安装脚本
# 通过AWS SSM Agent向目标主机发送安装任务

set -e

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/datakit_install.log"
CONFIG_PY_FILE="/usr/lib/zabbix/externalscripts/config.py"
DATAWAY_URL="https://dataway.prod-guance.houtai.io"
S3_ENDPOINT="https://s3.ap-southeast-1.amazonaws.com"
S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
S3_BUCKET="benjamin--test"
S3_DATAKIT_DIR="datakit"
DATAKIT_VERSION="1.78.0"
DATAKIT_INSTALL_DIR="/opt/datakit_install"


# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# 全局变量
HOST_IP=""
OPS_TOKEN=""
OPS_ADDR=""
ENV=""
WORKSPACE=""
GLOBAL_TAGS=""
WORKSPACE_TOKEN=""
DATAWAY_LOG_URL="https://openway.guance.com/v1/write/logging?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82"

DATAWAY_FULL_URL="https://openway.guance.com/v1/write/logging?token=tkn_3a0052c9f6d3498c8ce9ca0988fd9c82"
CGROUP_CPU_LIMIT=""
CGROUP_MEMORY_LIMIT=""

# 日志函数
log_info() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${BLUE}${message}${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
    echo -e "${GREEN}${message}${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
    echo -e "${YELLOW}${message}${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${message}${NC}" | tee -a "$LOG_FILE"
}

# 获取本机IP地址
get_host_ip() {
    log_info "获取本机IP地址..."
    
    # 使用 `ip` 命令获取主网卡的 IP 地址，排除回环地址
    HOST_IP=$(ip -4 addr show | grep -v '127.0.0.1' | awk '/inet/ {print $2}' | cut -d'/' -f1 | head -n 1)
    
    # 如果没有找到 IP 地址，尝试使用 `ifconfig` 命令
    if [ -z "$HOST_IP" ]; then
        HOST_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
    fi
    
    if [ -z "$HOST_IP" ]; then
        log_error "无法获取本机IP地址"
        exit 1
    fi
    
    log_success "获取到本机IP地址: $HOST_IP"
}


# Dataway日志上报函数
dataway_log() {
    local level="$1"
    local message="$2"
    # local timestamp=$(date +%s%M)
    
    # 构建上报数据结构
    local log_data=$(cat <<EOF
{
    "measurement": "datakit_host",
    "tags": {
        "level": "$level",
        "host_ip": "$HOST_IP",
        "env": "$ENV",
        "workspace": "$WORKSPACE"
    },
    "fields": {
        "message": "$message"
    }
}
EOF
)
    # log_info "上报数据: $log_data"
    
    # 上报到Dataway
    if [ -n "$DATAWAY_LOG_URL" ]; then
        # log_info "完整curl命令: curl -s -X POST \"$DATAWAY_LOG_URL\" -H \"Content-Type: application/json\" -d \"$log_data\""
        
        curl -s -X POST "$DATAWAY_LOG_URL" \
            -H "Content-Type: application/json" \
            -d "$log_data" >/dev/null 2>&1 || true
        if [ $? -ne 0 ]; then
            log_error "Dataway上报失败"
        fi
    fi
    
    # 同时记录到本地日志
    case "$level" in
        "info")
            log_info "$message"
            ;;
        "error")
            log_error "$message"
            ;;
        *)
            log_info "$message"
            ;;
    esac
}


# 获取运维平台配置
get_ops_config() {
    log_info "获取运维平台配置..."
    
    # 设置默认的运维平台地址
    OPS_ADDR="http://localhost:5000"
    OPS_TOKEN="mock_token"  # 模拟token，实际使用时可以为空
    get_host_ip
    if [ $? -ne 0 ]; then
        log_error "获取本机IP地址失败"
        exit 1
    fi
    
    # 调用运维平台接口获取配置信息
    local response=$(curl -s -X POST "$OPS_ADDR/api/v2/cmdb/observation-agent" \
        -H "Content-Type: application/json" \
        -d '{"server_ip": "$HOST_IP"}' 2>/dev/null)
    
    # 输出response并jq解析
    echo "$response" | jq .

    if [ $? -eq 0 ] && [ -n "$response" ]; then
        # 解析返回数据
        ENV=$(echo "$response" | jq -r '.env // empty' 2>/dev/null)
        WORKSPACE=$(echo "$response" | jq -r '.workspace // empty' 2>/dev/null)
        GLOBAL_TAGS=$(echo "$response" | jq -r '.global_tags.global_source // empty' 2>/dev/null)
        DATAWAY_URL=$(echo "$response" | jq -r '.dataway_url // empty' 2>/dev/null)
        WORKSPACE_TOKEN=$(echo "$response" | jq -r '.workspace_token // empty' 2>/dev/null)
        
        if [ -n "$ENV" ] && [ -n "$WORKSPACE" ] && [ -n "$WORKSPACE_TOKEN" ]; then
            # 构建完整的Dataway URL
            DATAWAY_FULL_URL="$DATAWAY_URL?token=$WORKSPACE_TOKEN"
            
            log_success "获取运维平台配置成功"
            log_info "环境: $ENV"
            log_info "工作空间: $WORKSPACE"
            log_info "全局标签: $GLOBAL_TAGS"
            log_info "Dataway地址: $DATAWAY_FULL_URL"
            
            # 上报成功日志
            log_info "成功获取运维平台配置: env=$ENV, workspace=$WORKSPACE"
            return 0
        else
            log_error "从运维平台接口获取的配置信息不完整"
            log_error "ENV: $ENV"
            log_error "WORKSPACE: $WORKSPACE"
            log_error "WORKSPACE_TOKEN: $WORKSPACE_TOKEN"
            return 1
        fi
    else
        log_error "调用运维平台接口失败"
        return 1
    fi
}

# 获取主机信息
get_host_info() {
    log_info "获取主机信息..."
    
    # 配置信息已经在get_ops_config中获取，这里只需要验证
    if [ -n "$ENV" ] && [ -n "$WORKSPACE" ] && [ -n "$WORKSPACE_TOKEN" ] && [ -n "$DATAWAY_FULL_URL" ]; then
        log_success "主机信息验证成功"
        log_info "环境: $ENV"
        log_info "工作空间: $WORKSPACE"
        log_info "全局标签: $GLOBAL_TAGS"
        log_info "Dataway地址: $DATAWAY_FULL_URL"
        
        # 上报成功日志
        log_info "主机信息验证成功: env=$ENV, workspace=$WORKSPACE"
        return 0
    else
        # 执行get_ops_config函数
        get_ops_config
        if [ $? -eq 0 ]; then
            log_success "主机信息验证成功"
            return 0
        else
            log_error "主机信息不完整，请检查get_ops_config函数"
            dataway_log "error" "主机信息不完整"
            exit 1
        fi
    fi
}

# 检查Datakit安装状态
check_datakit_status() {
    log_info "检查Datakit安装状态..."
    
    # 检查Datakit进程是否存在
    if pgrep -x "datakit" >/dev/null; then
        log_warning "Datakit进程已存在"
        log_info "Datakit进程已存在，跳过安装"
        exit 0
    fi
    
    # 检查Datakit端口是否被监听
    if netstat -tlnp 2>/dev/null | grep -q ":9529 "; then
        log_warning "Datakit端口9529已被占用"
        log_info "Datakit端口9529已被占用，跳过安装"
        exit 0
    fi
    
    # 检查Datakit配置文件是否存在
    if [ -d "/usr/local/datakit" ]; then
        log_warning "Datakit配置文件已存在"
        log_info "Datakit配置文件已存在，跳过安装"
        exit 0
    fi
    
    log_success "Datakit未安装，可以继续安装"
}

# 通过yj读取TOML文件并转换为JSON格式
read_toml_as_json() {
    local toml_file="$1"
    local json_path="$2"
    
    log_info "读取TOML文件: $toml_file"
    
    # 检查文件是否存在
    if [ ! -f "$toml_file" ]; then
        log_error "TOML文件不存在: $toml_file"
        return 1
    fi
    
    # 检查yj工具是否可用
    if ! command -v yj >/dev/null 2>&1; then
        log_error "yj工具不可用，请先安装yj"
        return 1
    fi
    
    # 使用yj将TOML转换为JSON
    local json_output
    if json_output=$(yj -t < "$toml_file" 2>/dev/null); then
        # 如果指定了JSON路径，则提取该路径的值
        if [ -n "$json_path" ]; then
            if command -v jq >/dev/null 2>&1; then
                local extracted_value
                if extracted_value=$(echo "$json_output" | jq -r "$json_path" 2>/dev/null); then
                    if [ "$extracted_value" != "null" ]; then
                        echo "$extracted_value"
                        log_info "成功提取JSON路径 $json_path 的值"
                        return 0
                    else
                        log_warning "JSON路径 $json_path 的值为null"
                        return 1
                    fi
                else
                    log_error "jq解析JSON路径失败: $json_path"
                    return 1
                fi
            else
                log_error "jq工具不可用，无法提取JSON路径"
                return 1
            fi
        else
            # 没有指定路径，返回完整JSON
            echo "$json_output"
            log_info "成功转换TOML为JSON格式"
            return 0
        fi
    else
        log_error "yj转换TOML文件失败: $toml_file"
        return 1
    fi
}

# 获取机器规格并设置资源限制
get_machine_specs() {
    log_info "获取机器规格并设置资源限制..."
    
    # 获取CPU规格
    local cpu_cores=$(lscpu | grep "CPU(s)" | cut -d ':' -f 2 | sed 's/^ //' | awk '{print $1}' | head -n 1)
    
    # 获取内存规格（GB）
    local memory_gb=$(free -g | grep "Mem" | awk '{print $2}')
    
    log_info "机器规格: ${cpu_cores}核 ${memory_gb}GB"
    cpu_cores=3
    memory_gb=6
    # 根据规格设置资源限制
    if [ "$cpu_cores" -lt 4 ] || [ "$memory_gb" -lt 8 ]; then
        # 2C4G ~ 4C8G: 使用规格的12.5%，最低0.5C0.5G
        local cpu_limit_raw=$(echo "scale=2; $cpu_cores * 0.125" | bc | sed 's/^\./0./')
        local memory_limit_raw=$(echo "scale=2; $memory_gb * 0.125" | bc | sed 's/^\./0./')
        
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
            memory_limit=$(echo "scale=0; $memory_limit_raw * 1024" | bc)
        fi
        
        CGROUP_CPU_LIMIT="$cpu_limit"
        CGROUP_MEMORY_LIMIT="$memory_limit"
        
        log_info "2C4G~4C8G 规格资源限制计算:"
        log_info "CPU原始限制: ${cpu_limit_raw}C (规格的12.5%)"
        log_info "内存原始限制: ${memory_limit_raw}GB (规格的12.5%)"
        log_info "CPU最终限制: ${cpu_limit}C (应用最低限制0.5C)"
        log_info "内存最终限制: ${memory_limit}MB (应用最低限制0.5GB)"
        log_info "设置动态资源限制: ${cpu_limit}C${memory_limit}MB"
        
    else
        # ≥ 4C8G: 使用固定限制
        CGROUP_CPU_LIMIT="1"
        CGROUP_MEMORY_LIMIT="2048"
        log_info "≥4C8G规格，设置默认资源限制: 1C2G"
    fi
    
    log_info "设置资源限制: ${CGROUP_CPU_LIMIT}C${CGROUP_MEMORY_LIMIT}MB"
}

# 下载Datakit安装包
download_datakit_packages() {
    log_info "下载Datakit安装包..."

    
    # 判断DATAKIT_DIR是否存在，如果存在则备份，增加日期
    if [ -d "$DATAKIT_INSTALL_DIR" ]; then
        log_info "DATAKIT_INSTALL_DIR已存在，备份"
        cp -r "$DATAKIT_INSTALL_DIR" "$DATAKIT_INSTALL_DIR.$(date +%Y%m%d%H%M)"
    fi
    
    # 创建临时目录
    
    mkdir -p "$DATAKIT_INSTALL_DIR"
    cd "$DATAKIT_INSTALL_DIR"
    

    # 下载已打包的bundle文件
    local bundle_name="datakit_bundle-linux-amd64-$DATAKIT_VERSION.tar.gz"
    local bundle_key="$S3_DATAKIT_DIR/$bundle_name"
    local md5_key="$S3_DATAKIT_DIR/$bundle_name.md5"
    

    log_info "下载bundle文件: $bundle_name"
    
    if [ -f "$DATAKIT_INSTALL_DIR/$bundle_name" ]; then
        log_info "bundle文件已存在，跳过下载"
    else
        # 下载bundle文件
        if ! download_from_s3_with_curl "$S3_BUCKET" "$bundle_key" "./$bundle_name"; then
            log_error "下载bundle文件失败"
            dataway_log "error" "下载bundle文件失败"
            exit 1
        fi
    fi
    
    
    # 下载MD5文件
    if ! download_from_s3_with_curl "$S3_BUCKET" "$md5_key" "./$bundle_name.md5"; then
        log_error "下载bundle MD5文件失败"
        dataway_log "error" "下载bundle MD5文件失败"
        exit 1
    fi
    
    # 验证MD5
    local expected_md5=$(cat "./$bundle_name.md5")
    local actual_md5=$(md5sum "$bundle_name" | awk '{print $1}')
    
    if [ "$expected_md5" != "$actual_md5" ]; then
        log_error "Bundle文件MD5验证失败"
        log_error "期望: $expected_md5"
        log_error "实际: $actual_md5"
        dataway_log "error" "Bundle文件MD5验证失败"
        exit 1
    fi
    
    log_success "Bundle文件MD5验证成功"
    
    # 解压bundle文件
    log_info "解压bundle文件..."
    if ! tar -xzf "$bundle_name"; then
        log_error "解压bundle文件失败"
        dataway_log "error" "解压bundle文件失败"
        exit 1
    fi
    
    # 检查解压后的文件
    if [ ! -f "./installer-linux-amd64-$DATAKIT_VERSION" ] || \
       [ ! -f "./datakit-linux-amd64-$DATAKIT_VERSION.tar.gz" ] || \
       [ ! -f "./dk_upgrader-linux-amd64.tar.gz" ] || \
       [ ! -f "./data.tar.gz" ]; then
        log_error "Bundle文件解压后缺少必要文件"
        dataway_log "error" "Bundle文件解压后缺少必要文件"
        exit 1
    fi
    
    
    # 复制工具文件到系统目录
    if [ -f "./jq" ]; then
        cp ./jq /usr/local/bin/ && chmod +x /usr/local/bin/jq
        log_info "jq工具安装完成"
    fi
    if [ -f "./yj" ]; then
        cp ./yj /usr/local/bin/ && chmod +x /usr/local/bin/yj
        log_info "yj工具安装完成"
    fi
    
    log_success "Bundle文件解压完成，所有文件准备就绪"
    log_info "Bundle文件下载和解压完成"
    
    # 返回临时目录路径
    log_info "Datakit安装包下载完成，路径: $DATAKIT_INSTALL_DIR"
    log_info "Datakit安装包下载完成，路径: $DATAKIT_INSTALL_DIR"
    return 0
}




# 安装Node Exporter
install_node_exporter() {
    log_info "安装Node Exporter..."
    
    # 检查Node Exporter是否已安装
    if pgrep -x "node_exporter" >/dev/null; then
        log_info "Node Exporter进程已存在"
        return 0
    fi
    
    # 检查端口9100是否被占用
    if netstat -tlnp 2>/dev/null | grep -q ":9100 "; then
        log_warning "端口9100已被占用，跳过Node Exporter安装"
        log_info "端口9100已被占用，跳过Node Exporter安装"
        return 0
    fi
    
    
    # 进入DATAKIT_INSTALL_DIR
    cd "$DATAKIT_INSTALL_DIR"   
    
    
    # 解压并安装
    tar -xzf node_exporter-1.8.2.linux-amd64.tar.gz
    cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
    chmod +x /usr/local/bin/node_exporter
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    # 检查服务状态,没2s检查一次，最多检查5次
    for i in {1..5}; do
        if systemctl is-active --quiet node_exporter; then
            log_success "Node Exporter安装成功"
            log_info "Node Exporter安装成功"
            return 0
        else
            log_info "Node Exporter启动中... ($i/5)"
            sleep 2
        fi
    done
    
    log_error "Node Exporter启动失败"
    dataway_log "error" "Node Exporter启动失败"
    return 1
}

# 安装Datakit
install_datakit() {
    log_info "安装Datakit..."
    
    # 判断DATAKIT_INSTALL_DIR是否存在，不存在则退出函数
    if [ ! -d "$DATAKIT_INSTALL_DIR" ]; then
        log_error "DATAKIT_INSTALL_DIR不存在"
        dataway_log "error" "DATAKIT_INSTALL_DIR不存在"
        return 1
    fi
    
    cd "$DATAKIT_INSTALL_DIR"
    
    # 设置安装器权限
    chmod +x "./installer-linux-amd64-$DATAKIT_VERSION"
    
    # 执行离线安装
    log_info "执行Datakit离线安装..."

    ./installer-linux-amd64-$DATAKIT_VERSION --offline --dataway "$DATAWAY_FULL_URL" --srcs "datakit-linux-amd64-$DATAKIT_VERSION.tar.gz,dk_upgrader-linux-amd64.tar.gz,data.tar.gz"
    if [ $? -ne 0 ]; then
        log_error "Datakit安装失败"
        dataway_log "error" "Datakit安装失败"
        return 1    
    fi
    

    # 检查Datakit是否启动成功
    local check_count=0
    local max_checks=10

    # 启动Datakit
    systemctl daemon-reload
    systemctl enable datakit
    systemctl start datakit

    # 检查Datakit是否启动成功,没5s检查一次，最多检查10次    
    while [ $check_count -lt $max_checks ]; do
        if systemctl is-active --quiet datakit; then
            log_success "Datakit启动成功"
            log_info "Datakit启动成功"
            return 0
        fi
        
        check_count=$((check_count + 1))
        log_info "等待Datakit启动... ($check_count/$max_checks)"
        sleep 5
    done
    
    log_error "Datakit启动超时"
    dataway_log "error" "Datakit启动超时"
    return 1
}

# 配置Datakit
configure_datakit() {
    log_info "配置Datakit..."
    
    local datakit_conf="/usr/local/datakit/conf.d/datakit.conf"
    
    if [ ! -f "$datakit_conf" ]; then
        log_error "Datakit配置文件不存在"
        return 1
    fi
    
    # 设置日志分片
    yq eval '.logging.rotate = "32"' "$datakit_conf" -i
    
    # 设置Cgroup配置
    if [ -n "$CGROUP_CPU_LIMIT" ]; then
        yq eval ".resource_limit.cpu_cores = \"$CGROUP_CPU_LIMIT\"" "$datakit_conf" -i
    fi
    if [ -n "$CGROUP_MEMORY_LIMIT" ]; then
        yq eval ".resource_limit.mem_max_mb = \"$CGROUP_MEMORY_LIMIT\"" "$datakit_conf" -i
    fi
    
    # 设置全局标签
    if [ -n "$ENV" ]; then
        yq eval ".global_host_tags.env = \"$ENV\"" "$datakit_conf" -i
    fi
    if [ -n "$WORKSPACE" ]; then
        yq eval ".global_host_tags.workspace = \"$WORKSPACE\"" "$datakit_conf" -i
    fi
    if [ -n "$GLOBAL_TAGS" ]; then
        yq eval ".global_host_tags.global_source = \"$GLOBAL_TAGS\"" "$datakit_conf" -i
    fi
    
    # 修改Dataway地址
    yq eval ".dataway.dataway_url = [\"$DATAWAY_FULL_URL\"]" "$datakit_conf" -i
    
    log_success "Datakit配置完成"
    log_info "Datakit配置完成"
}

# 配置采集器
configure_inputs() {
    log_info "配置采集器..."
    
    local conf_dir="/usr/local/datakit/conf.d"
    
    # Prometheus配置
    cat > "$conf_dir/prom_node_exporter.conf" << 'EOF'
# {"version": "1.63.1", "desc": "do NOT edit this line"}

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
    cat > "$conf_dir/opentelemetry.conf" << 'EOF'
# {"version": "1.64.1", "desc": "do NOT edit this line"}
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
    cat > "$conf_dir/logging.conf" << 'EOF'
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
    cat > "$conf_dir/pushgateway.conf" << 'EOF'
[[inputs.pushgateway]]
  ## Prefix for the internal routes of web endpoints. Defaults to empty.
  route_prefix = "/v1/pushgateway"

  job_as_measurement = false
  keep_exist_metric_name = true
EOF

    log_success "采集器配置完成"
    log_info "采集器配置完成"
}

# 重启Datakit并检查状态
restart_datakit() {
    log_info "重启Datakit..."
    
    # 重启Datakit
    systemctl restart datakit
    
    # 检查重启状态
    local check_count=0
    local max_checks=5
    
    while [ $check_count -lt $max_checks ]; do
        if pgrep -x "datakit" >/dev/null && netstat -tlnp 2>/dev/null | grep -q ":9529 "; then
            log_success "Datakit重启成功"
            log_info "Datakit重启成功"
            return 0
        fi
        
        check_count=$((check_count + 1))
        log_info "等待Datakit重启... ($check_count/$max_checks)"
        sleep 10
    done
    
    log_error "Datakit重启失败"
    dataway_log "error" "Datakit重启失败"
    return 1
}

# 设置定时任务
setup_cron_jobs() {
    log_info "设置定时任务..."
    
    # 日志删除定时任务
    cat > /etc/cron.d/datakit_cleanup << 'EOF'
# 每天00:00执行日志清理
0 0 * * * root find /var/log/datakit -name "*.log.*" -mtime +7 -delete
EOF

    # Datakit健康检查定时任务
    cat > /etc/cron.d/datakit_health_check << 'EOF'
# 每5分钟检查Datakit健康状态
*/5 * * * * root /usr/local/bin/datakit --check-health >/dev/null 2>&1 || systemctl restart datakit
EOF

    # 重新加载cron配置
    systemctl reload crond 2>/dev/null || systemctl reload cron 2>/dev/null || true
    
    log_success "定时任务设置完成"
    log_info "定时任务设置完成"
}

# 验证安装结果
verify_installation() {
    log_info "验证安装结果..."
    
    local verification_passed=true
    
    # 检查Datakit进程
    if ! pgrep -x "datakit" >/dev/null; then
        log_error "Datakit进程不存在"
        verification_passed=false
    fi
    
    # 检查Datakit端口
    if ! netstat -tlnp 2>/dev/null | grep -q ":9529 "; then
        log_error "Datakit端口9529未监听"
        verification_passed=false
    fi
    
    # 检查Node Exporter（如果安装了）
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        if ! netstat -tlnp 2>/dev/null | grep -q ":9100 "; then
            log_warning "Node Exporter端口9100未监听"
        fi
    fi
    
    # 检查配置文件
    if [ ! -f "/usr/local/datakit/conf.d/datakit.conf" ]; then
        log_error "Datakit配置文件不存在"
        verification_passed=false
    fi
    
    if [ "$verification_passed" = true ]; then
        log_success "安装验证通过"
        log_info "Datakit安装验证通过"
        return 0
    else
        log_error "安装验证失败"
        dataway_log "error" "Datakit安装验证失败"
        return 1
    fi
}

# 清理临时文件
cleanup_temp_files() {
    local temp_dir="$1"
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        log_info "清理临时文件..."
        rm -rf "$temp_dir"
    fi
}



# 使用curl下载私有S3文件（AWS签名v4）- 修复版本
download_from_s3_with_curl() {
    local bucket="$1"
    local key="$2"
    local local_path="$3"
    
    log_info "使用curl从私有S3下载: $key"
    
    # 检查AWS凭证
    if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
        log_error "缺少AWS凭证，无法访问私有S3 bucket"
        return 1
    fi
    
    # 设置变量
    local http_method="GET"
    local canonical_uri="/$key"
    local canonical_querystring=""
    local timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    local date_stamp=$(date -u +%Y%m%d)
    local region="ap-southeast-1"
    local service="s3"
    local host="$bucket.s3.$region.amazonaws.com"
    
    # 生成负载哈希（GET请求为空）
    local payload_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    
    # 构建Canonical Headers - 确保格式完全正确
    local canonical_headers="host:$host"$'\n'"x-amz-content-sha256:$payload_hash"$'\n'"x-amz-date:$timestamp"$'\n'
    local signed_headers="host;x-amz-content-sha256;x-amz-date"
    
    # 构建Canonical Request - 使用精确的换行符
    local canonical_request="$http_method"$'\n'"$canonical_uri"$'\n'"$canonical_querystring"$'\n'"$canonical_headers"$'\n'"$signed_headers"$'\n'"$payload_hash"
    
    # 计算Canonical Request哈希
    local canonical_request_hash=$(printf "%s" "$canonical_request" | sha256sum | awk '{print $1}')
    
    # 构建String to Sign
    local credential_scope="$date_stamp/$region/$service/aws4_request"
    local string_to_sign="AWS4-HMAC-SHA256"$'\n'"$timestamp"$'\n'"$credential_scope"$'\n'"$canonical_request_hash"
    
    # 生成签名密钥
    local kSecret="AWS4$S3_SECRET_KEY"
    local kDate=$(printf "%s" "$date_stamp" | openssl dgst -sha256 -hmac "$kSecret" -binary)
    local kRegion=$(printf "%s" "$region" | openssl dgst -sha256 -hmac "$kDate" -binary)
    local kService=$(printf "%s" "$service" | openssl dgst -sha256 -hmac "$kRegion" -binary)
    local kSigning=$(printf "%s" "aws4_request" | openssl dgst -sha256 -hmac "$kService" -binary)
    
    # 生成签名
    local signature=$(printf "%s" "$string_to_sign" | openssl dgst -sha256 -hmac "$kSigning" | awk '{print $2}')
    
    # 生成授权头
    local authorization_header="AWS4-HMAC-SHA256 Credential=$S3_ACCESS_KEY/$credential_scope,SignedHeaders=$signed_headers,Signature=$signature"
    
    # 构建完整URL
    local s3_url="https://$host$canonical_uri"
    
    # 使用curl下载（带进度条）
    log_info "开始下载文件..."
    if curl -L -o "$local_path" "$s3_url" \
        -H "Authorization: $authorization_header" \
        -H "x-amz-content-sha256: $payload_hash" \
        -H "x-amz-date: $timestamp" \
        --progress-bar \
        --connect-timeout 30 --max-time 600; then
        
        # 检查文件大小，确保下载成功
        local file_size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path" 2>/dev/null)
        if [ "$file_size" -gt 0 ]; then
            log_success "文件下载成功: $local_path (${file_size} bytes)"
            return 0
        else
            log_error "下载的文件为空: $key"
            return 1
        fi
    else
        log_error "下载失败: $key"
        return 1
    fi
}

# 配置AWS凭证
configure_aws_credentials() {
    log_info "配置AWS凭证..."
    
    # 创建AWS配置目录
    mkdir -p ~/.aws
    
    # 配置AWS凭证文件
    cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $S3_ACCESS_KEY
aws_secret_access_key = $S3_SECRET_KEY
EOF
    
    # 配置AWS配置文件
    cat > ~/.aws/config << EOF
[default]
region = ap-southeast-1
output = json
EOF
    
    # 设置权限
    chmod 600 ~/.aws/credentials
    chmod 600 ~/.aws/config
    
    log_success "AWS凭证配置完成"
}

# 主函数
main() {
    log_info "开始Datakit安装流程..."
    
    # 初始化日志文件
    touch "$LOG_FILE"
    
    
    # 关键步骤一：获取业务主机信息
    log_info "=== 关键步骤一：获取业务主机信息 ==="
    get_host_ip
    get_ops_config
    get_host_info
    
    # 关键步骤二：判断Datakit安装状态
    log_info "=== 关键步骤二：判断Datakit安装状态 ==="
    check_datakit_status
    
    # 关键步骤三：运行资源限制策略
    log_info "=== 关键步骤三：运行资源限制策略 ==="
    get_machine_specs
    
    # 关键步骤四：物料准备
    log_info "=== 关键步骤四：物料准备 ==="
    local temp_dir=$(download_datakit_packages)
    
    # 关键步骤五：执行安装流程
    log_info "=== 关键步骤五：执行安装流程 ==="
    
    # 安装Node Exporter
    install_node_exporter "$temp_dir"
    
    # 安装Datakit
    if ! install_datakit "$temp_dir"; then
        cleanup_temp_files "$temp_dir"
        exit 1
    fi
    
    # 配置Datakit
    configure_datakit
    
    # 配置采集器
    configure_inputs
    
    # 重启Datakit
    if ! restart_datakit; then
        cleanup_temp_files "$temp_dir"
        exit 1
    fi
    
    # 关键步骤六：下发定时任务
    log_info "=== 关键步骤六：下发定时任务 ==="
    setup_cron_jobs
    
    # 验证安装结果
    log_info "=== 验证安装结果 ==="
    if verify_installation; then
        log_success "Datakit安装完成"
        log_info "Datakit安装完成"
    else
        log_error "Datakit安装失败"
        dataway_log "error" "Datakit安装失败"
        cleanup_temp_files "$temp_dir"
        exit 1
    fi
    
    # 清理临时文件
    cleanup_temp_files "$temp_dir"
    
    log_success "所有安装步骤完成"
    log_info "Datakit安装流程完成"
}



# 运行主函数
# main "$@" 

# get_host_ip
# get_host_info
# get_machine_specs
# download_datakit_packages
get_ops_config
# download_datakit_packages
# install_node_exporter
# install_datakit

# 如果提供了参数，则调用TOML读取函数
# read_toml_as_json "$1" "$2"
