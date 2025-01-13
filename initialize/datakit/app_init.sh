#!/bin/bash
# 同步业务可观测配置，定时执行
# 镜像初始化时获取


sleep $((RANDOM % 30 + 1))

# 全局调试开关
DEBUG=true  # 设置为 true 启用调试日志，设置为 false 禁用调试日志
# 模板文件路径
LOGGING_TEMPLATE="logging_template.conf"
METRICS_TEMPLATE="metrics_template.conf"
HEALTH_TEMPLATE="health_template.conf"

# 存储目录
LOGGING_DIR="/usr/local/datakit/conf.d/log"
METRICS_DIR="/usr/local/datakit/conf.d/prom"
HEALTH_DIR="/usr/local/datakit/conf.d/host"


# LOGGING_TMP_DIR="/data1/bingbon/log"
# METRICS_TMP_DIR="/data1/bingbon/prom"
# HEALTH_TMP_DIR="/data1/bingbon/host"


# # 前一次存储目录
# LOGGING_PREV_DIR="/data1/bingbon/log_prev"
# METRICS_PREV_DIR="/data1/bingbon/prom_prev"
# HEALTH_PREV_DIR="/data1/bingbon/host_prev"


# 临时存储目录
LOGGING_TMP_DIR="/opt/datakit/log"
METRICS_TMP_DIR="/opt/datakit/prom"
HEALTH_TMP_DIR="/opt/datakit/host"


# 前一次存储目录
LOGGING_PREV_DIR="/opt/datakit/log_prev"
METRICS_PREV_DIR="/opt/datakit/prom_prev"
HEALTH_PREV_DIR="/opt/datakit/host_prev"

# config.toml 
CONFIG_PY_FILE="/usr/lib/zabbix/externalscripts/config.py"



log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    LOG_FILE="/opt/datakit/app_init.log"
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
    echo "$timestamp - $message" >> "$LOG_FILE"
}

# 打印调试信息的函数
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo "【DEBUG】$1 "
    fi
}


# 如果目录不存在，则创建目录
if [ ! -d "$LOGGING_TMP_DIR" ]; then
    mkdir -p "$LOGGING_TMP_DIR"
    log_message "app_init: LOGGING_TMP_DIR 目录不存在，已创建"
fi  

if [ ! -d "$METRICS_TMP_DIR" ]; then
    mkdir -p "$METRICS_TMP_DIR"
    log_message "app_init: METRICS_TMP_DIR 目录不存在，已创建"
fi  

if [ ! -d "$HEALTH_TMP_DIR" ]; then
    mkdir -p "$HEALTH_TMP_DIR"
    log_message "app_init: HEALTH_TMP_DIR 目录不存在，已创建"
fi

if [ ! -d "$LOGGING_PREV_DIR" ]; then
    mkdir -p "$LOGGING_PREV_DIR"
    log_message "app_init: LOGGING_PREV_DIR 目录不存在，已创建"
fi

if [ ! -d "$METRICS_PREV_DIR" ]; then
    mkdir -p "$METRICS_PREV_DIR"
    log_message "app_init: METRICS_PREV_DIR 目录不存在，已创建"
fi

if [ ! -d "$HEALTH_PREV_DIR" ]; then
    mkdir -p "$HEALTH_PREV_DIR"
    log_message "app_init: HEALTH_PREV_DIR 目录不存在，已创建"
fi  




# 计数器 记录diff 差异
diff_count=0
diff_count_logging=0
diff_count_metrics=0
diff_count_health=0


# 日志差异文件列表
logging_diff_file_list=()
# 指标差异文件列表
metrics_diff_file_list=()
# 健康检查差异文件列表
health_diff_file_list=() 


fetch_json_from_ops() {
    OPS_TOKEN=$(grep -v '^\s*#' "$CONFIG_PY_FILE" | grep -oP "ops_token = '\K[^']+")
    OPS_ADDR=$(grep -v '^\s*#' "$CONFIG_PY_FILE" | grep -oP "ops_addr = '\K[^']+")

    log_message "app_init: OPS_TOKEN: $OPS_TOKEN"
    log_message "app_init: OPS_ADDR: $OPS_ADDR" 

    # 使用 `ip` 命令获取主网卡的 IP 地址，排除回环地址
    local ip=$(ip -4 addr show | grep -v '127.0.0.1'  | awk '/inet/ {print $2}' | cut -d'/' -f1 | head -n 1)

    # 如果没有找到 IP 地址，尝试使用 `ifconfig` 命令
    if [ -z "$ip" ]; then
        ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
    fi

    # 返回找到的 IP 地址
    log_message "app_init: 主机IP 地址为：$ip"

    # 使用 curl 发送 POST 请求
    local url="http://$OPS_ADDR/api/v2/cmdb/observation-metadata"
    server_ip=$ip
    log_message "app_init: server_ip: $server_ip"

    # 设置连接超时为 10 秒，最大请求时间为 30 秒
    local random_number=$((RANDOM % 60 + 1))
    log_message "app_init: 随机休眠 $random_number 秒"
    sleep $random_number

    # 将响应结果保存到 tmp.json 文件，并获取 HTTP 状态码
    http_code=$(curl -s -o tmp.json -w "%{http_code}" -X POST "$url" \
        -H "Authorization: Token $OPS_TOKEN" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -d "{\"server_ip\": \"$server_ip\"}" \
        --connect-timeout 10 \
        --max-time 30)

    # 判断 curl 是否超时
    if [ "$http_code" -eq 28 ]; then
        log_message "app_init: 请求超时，当前连接超时设置为10s，最大请求时间为30s，超时退出脚本......"
        exit 1
    elif [ "$http_code" -ne 200 ]; then
        case "$http_code" in
            400) log_message "app_init: 错误请求，可能是请求参数有误。" ;;
            401) log_message "app_init: 未授权，检查 Token 是否有效。" ;;
            403) log_message "app_init: 禁止访问，您没有权限访问该资源。" ;;
            404) log_message "app_init: 未找到，检查 URL 是否正确。" ;;
            500) log_message "app_init: 服务器内部错误，请稍后重试。" ;;
            502) log_message "app_init: 错误网关，可能是上游服务器问题。" ;;
            503) log_message "app_init: 服务不可用，服务器当前无法处理请求。" ;;
            504) log_message "app_init: 网关超时，服务器未能及时响应。" ;;
            *) log_message "app_init: 其他错误，HTTP 状态码: $http_code" ;;
        esac
        log_message "app_init: 业务初始化脚本退出,请检查 $url 是否可以正常访问......"
        exit 1
    fi

    # 判断 response 是否为json 格式    
    if jq empty tmp.json; then
        log_message "app_init: 响应结果已保存到 tmp.json"
    else
        log_message "app_init: 响应结果不是有效的 JSON 格式"
        exit 1
    fi
}

# 日志文件合并
logging_merge_json() {
    log_message "app_init: ----开始合并日志文件----"
    local source="$1"
    # 获取source 的最后一个/ 后的字符串
    local file=$(echo "$source" | rev | cut -d'/' -f1 | rev)
    log_message "app_init: file: $file"

    # 获取datakit 存储目录下同名文件
    local datakit_toml_file="${LOGGING_DIR}/${file}"
    log_message "app_init: datakit_toml_file: $datakit_toml_file"

    # 如果datakit_toml_file 存在，则需要与toml_file 进行一次diff
    if [ -f "$datakit_toml_file" ]; then
        diff_result=$(diff "$source" "$datakit_toml_file")
        log_message "app_init: diff_result: $diff_result"
        if [ -n "$diff_result" ]; then
            # 如果存在差异，则需要将toml_file 合并到datakit_toml_file 中

            log_message "app_init: 【DEBUG】${source} 与 ${datakit_toml_file} 存在差异"
            log_message "app_init: 【DEBUG】将 ${source} 合并到 ${datakit_toml_file} 中"
            
            # 解析  file 以及 datakit 存储目录下同名文件，转成json，解析出 inputs.logging[{}] 的结构
            logging_file_json=$(cat "$source" | yj -tj)
            datakit_toml_file_json=$(cat "$datakit_toml_file" | yj -tj)
            log_message "app_init: logging_file_json: $logging_file_json"
            log_message "app_init: datakit_toml_file_json: $datakit_toml_file_json"


            # 合并 datakit_toml_file_json 的 ".inputs.logging[0]" 与 logging_file_json
            datakit_toml_file_json_result=$(echo "$datakit_toml_file_json" "$logging_file_json" | jq -s '.[0].inputs.logging[0] * .[1].inputs.logging[0]')

            # 将合并后的json 转成toml 并覆盖到datakit 存储目录下同名文件
            echo "{\"inputs\":{\"logging\":[$datakit_toml_file_json_result]}}" | yj -jt > "$datakit_toml_file"

            # 打印合并后的json
            log_message "app_init: 合并后的json: $datakit_toml_file_json_result"
        fi
    else
        # 如果datakit_toml_file 不存在，则直接覆盖
        cp "$source" "$datakit_toml_file"
        log_message "app_init: datakit_toml_file 不存在，已直接覆盖"
    fi

}

# 指标文件合并
metrics_merge_json() {
    log_message "app_init: ----开始合并指标文件----"
    local source="$1"
    # 获取source 的最后一个/ 后的字符串 
    local file=$(echo "$source" | rev | cut -d'/' -f1 | rev)
    # 获取datakit 存储目录下同名文件
    local datakit_toml_file="${METRICS_DIR}/${file}"
    if [ -f "$datakit_toml_file" ]; then
        diff_result=$(diff "$source" "$datakit_toml_file")
        log_message "app_init: diff_result: $diff_result"
        if [ -n "$diff_result" ]; then
            log_message "app_init: 【DEBUG】${source} 与 ${datakit_toml_file} 存在差异"
            log_message "app_init: 【DEBUG】将 ${source} 合并到 ${datakit_toml_file} 中"  

            # 解析 file 以及 datakit 存储目录下同名文件，转成json，解析出 inputs.prom[{}] 的结构
            metrics_file_json=$(cat "$source" | yj -tj)
            datakit_toml_file_json=$(cat "$datakit_toml_file" | yj -tj)

            # 合并 datakit_toml_file_json 的 ".inputs.prom[0].metrics" 与 metrics_file_json_metrics
            datakit_toml_file_json_result=$(echo "$datakit_toml_file_json" "$metrics_file_json" | jq -s '.[0].inputs.prom[0] * .[1].inputs.prom[0]')


            # 将合并后的json 转成toml 并覆盖到datakit 存储目录下同名文件
            echo "{\"inputs\":{\"prom\":[$datakit_toml_file_json_result]}}" | yj -jt > "$datakit_toml_file"

        fi
    fi
}   

# 健康检查文件合并
health_merge_json() {
    log_message "app_init: ----开始合并健康检查文件----"
    local source="$1"
    # 获取source 的最后一个/ 后的字符串 
    local file=$(echo "$source" | rev | cut -d'/' -f1 | rev)
    # 获取datakit 存储目录下同名文件
    local datakit_toml_file="${HEALTH_DIR}/${file}"
    if [ -f "$datakit_toml_file" ]; then
        diff_result=$(diff "$source" "$datakit_toml_file")
        log_message "app_init: diff_result: $diff_result"
        if [ -n "$diff_result" ]; then
            log_message "app_init: 【DEBUG】${source} 与 ${datakit_toml_file} 存在差异"
            log_message "app_init: 【DEBUG】将 ${source} 合并到 ${datakit_toml_file} 中"  

            # 解析 source 以及 datakit 存储目录下同名文件，转成json，解析出 inputs.host_healthcheck[{}] 的结构
            health_file_json=$(cat "$source" | yj -tj)
            datakit_toml_file_json=$(cat "$datakit_toml_file" | yj -tj)

            log_message "app_init: health_file_json: $health_file_json"
            log_message "app_init: datakit_toml_file_json: $datakit_toml_file_json"


            # 合并 datakit_toml_file_json 的 ".inputs.host_healthcheck[0].health" 与 health_file_json_health
            datakit_toml_file_json_result=$(echo "$datakit_toml_file_json" "$health_file_json" | jq -s '.[0].inputs.host_healthcheck[0] * .[1].inputs.host_healthcheck[0]') 
            log_message "app_init: 合并后的json: $datakit_toml_file_json_result"


            # 将合并后的json 转成toml 并覆盖到datakit 存储目录下同名文件
            
            # echo "{\"inputs\":{\"host_healthcheck\":[{\"http\":[$datakit_toml_file_json_result]}]}}" | yj -jt > "$datakit_toml_file"
            echo "{\"inputs\":{\"host_healthcheck\":[$datakit_toml_file_json_result]}}" | yj -jt > "$datakit_toml_file"    
        fi

    fi

}   


# 处理 logging 的函数
process_logging() {
    local service_name="$1"
    local service="$2"

    for i in $(seq 0 $(echo "$service" | jq -r ".\"$service_name\".logging | length - 1")); do
        logging=$(echo "$service" | jq -r ".\"$service_name\".logging[$i]")
        log_message "app_init: logging: $logging"
        # log_type 日志类型
        log_type=$(echo "$logging" | jq -r ".tags.logType")




        # 处理 logging
        logging_content=$(echo "{\"inputs\": {\"logging\": [$logging]}}" | jq -r ".")
        if ! echo "$logging_content" | jq empty; then
            log_message "app_init: 【ERROR】logging_content 不是有效的 JSON 格式"
            continue
        fi

        log_message "app_init: log_type: $log_type"
        log_message "app_init: logging_content: $logging_content"

        # logging_content 使用yj 转成toml 
        logging_content_toml=$( echo "$logging_content" | yj -jt)
        # debug_log "logging_content_toml: $logging_content_toml"

        # 生成临时配置文件
        echo "$logging_content_toml" > "${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf"

        # 如果前一次存储目录存在同名文件，则需要与前一次存储目录的文件进行一次diff
        if [ -f "${LOGGING_PREV_DIR}/${service_name}_${log_type}.conf" ]; then
            diff_result=$(diff "${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf" "${LOGGING_PREV_DIR}/${service_name}_${log_type}.conf")
            log_message "app_init: diff_result: $diff_result"

            # 如果存在差异，则需要将临时配置文件合并到前一次存储目录的文件中
            if [ -n "$diff_result" ]; then

                # 打印差异
                log_message "app_init: ${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf 与 ${LOGGING_PREV_DIR}/${service_name}_${log_type}.conf 存在差异"
                current_time=$(date +%Y%m%d%H%M%S)


                # 将临时配置文件覆盖到前一次存储目录
                
                cp "${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf" "${LOGGING_PREV_DIR}/${service_name}_${log_type}.conf"

                log_message "app_init: 将临时配置文件覆盖到前一次存储目录完成"

                # 计数器+1
                diff_count_logging=$((diff_count_logging + 1))
                diff_count=$((diff_count + 1))  
                log_message "app_init: 日志计数器添加完成"

                # 将差异文件添加到列表
                logging_diff_file_list+=("${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf")

            else
                log_message "app_init: 前后配置文件没有差异，跳过执行......"
            fi
        # 如果不存在同名文件，则直接覆盖
        else
            # 计数器+1
            diff_count_logging=$((diff_count_logging + 1))
            diff_count=$((diff_count + 1))  

            # 将差异文件添加到列表
            logging_diff_file_list+=("${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf")
            log_message "app_init: ${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf 不存在同名文件，直接覆盖"
            # 将临时配置文件覆盖到前一次存储目录
            cp "${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf" "${LOGGING_PREV_DIR}/${service_name}_${log_type}.conf"
            # 复制到datakit 配置目录
            cp "${LOGGING_TMP_DIR}/${service_name}_${log_type}.conf" "${LOGGING_DIR}/"

        fi
    done
}

# 处理 metrics 的函数
process_metrics() {
    local service_name="$1"
    local service="$2"

    for i in $(seq 0 $(echo "$service" | jq -r ".\"$service_name\".metrics | length - 1")); do
        metrics=$(echo "$service" | jq -r ".\"$service_name\".metrics[$i]")
        log_message "app_init: metrics: $metrics"

        # 处理 metrics
        metrics_content=$(echo "{\"inputs\": {\"prom\": [$metrics]}}" | jq -r ".")
        log_message "app_init: metrics_content: $metrics_content"

        # metrics_content 使用yj 转成toml 后 生成配置文件
        metrics_content_toml=$( echo "$metrics_content" | yj -jt)
        log_message "app_init: metrics_content_toml: $metrics_content_toml"

        # 生成临时配置文件
        echo "$metrics_content_toml" > "${METRICS_TMP_DIR}/${service_name}_metrics.conf"

        # 如果前一次存储目录存在同名文件，则需要与前一次存储目录的文件进行一次diff
        if [ -f "${METRICS_PREV_DIR}/${service_name}_metrics.conf" ]; then    
            diff_result=$(diff "${METRICS_TMP_DIR}/${service_name}_metrics.conf" "${METRICS_PREV_DIR}/${service_name}_metrics.conf")
            if [ -n "$diff_result" ]; then
                debug_log "${METRICS_TMP_DIR}/${service_name}_metrics.conf 与 ${METRICS_PREV_DIR}/${service_name}_metrics.conf 存在差异"
                current_time=$(date +%Y%m%d%H%M%S)

                cp "${METRICS_TMP_DIR}/${service_name}_metrics.conf" "${METRICS_PREV_DIR}/${service_name}_metrics.conf"

                # 计数器+1
                diff_count_metrics=$((diff_count_metrics + 1))
                diff_count=$((diff_count + 1))  

                # 将差异文件添加到列表
                metrics_diff_file_list+=("${METRICS_TMP_DIR}/${service_name}_metrics.conf")

            else
                echo "前后配置文件没有差异，跳过执行......"

            fi
        else
            # 计数器+1
            diff_count_metrics=$((diff_count_metrics + 1))
            diff_count=$((diff_count + 1))  
            log_message "app_init: ${METRICS_TMP_DIR}/${service_name}_metrics.conf 不存在同名文件，直接覆盖"
            cp "${METRICS_TMP_DIR}/${service_name}_metrics.conf" "${METRICS_PREV_DIR}/${service_name}_metrics.conf"
            # 复制到datakit 配置目录
            cp "${METRICS_TMP_DIR}/${service_name}_metrics.conf" "${METRICS_DIR}/"
        fi  
    done
}

# 处理 health 的函数
process_health() {
    local service_name="$1"
    local service="$2"

    for i in $(seq 0 $(echo "$service" | jq -r ".\"$service_name\".health | length - 1")); do
        health=$(echo "$service" | jq -r ".\"$service_name\".health[$i]")
        log_message "app_init: health: $health"

        # 处理 health  tags
        health_content=$(echo "{\"inputs\": {\"host_healthcheck\":[{\"interval\": \"1m\" ,\"http\": [$health]}]}}" | jq -r '.inputs.host_healthcheck[0].tags = .inputs.host_healthcheck[0].http[0].tags'| jq -r '.inputs.host_healthcheck[0].http[0].method = "GET"')
 

        # 打印 health_content
        log_message "app_init: health_content: $health_content"

        # # 置换 tags 位置
        # health_content=$(echo "$health_content" | jq  -r --arg tags "$tags" '.inputs.host_healthcheck[0] | .tags = $tag)')
        log_message "app_init: health_content: $health_content"

        log_message "app_init: health_content_result: $health_content"
        # health_content 使用yj 转成toml 后 生成配置文件
        health_content_toml=$( echo "$health_content" | yj -jt)
        log_message "app_init: health_content_toml: $health_content_toml"

        # 生成临时配置文件c 
        echo "$health_content_toml" > "${HEALTH_TMP_DIR}/${service_name}_health.conf"

        # 如果前一次存储目录存在同名文件，则需要与前一次存储目录的文件进行一次diff
        if [ -f "${HEALTH_PREV_DIR}/${service_name}_health.conf" ]; then
            diff_result=$(diff "${HEALTH_TMP_DIR}/${service_name}_health.conf" "${HEALTH_PREV_DIR}/${service_name}_health.conf")
            if [ -n "$diff_result" ]; then
                debug_log "${HEALTH_TMP_DIR}/${service_name}_health.conf 与 ${HEALTH_PREV_DIR}/${service_name}_health.conf 存在差异"
                current_time=$(date +%Y%m%d%H%M%S)

                cp "${HEALTH_TMP_DIR}/${service_name}_health.conf" "${HEALTH_PREV_DIR}/${service_name}_health.conf"

                # 计数器+1
                diff_count_health=$((diff_count_health + 1))
                diff_count=$((diff_count + 1))

                # 将差异文件添加到列表
                health_diff_file_list+=("${HEALTH_TMP_DIR}/${service_name}_health.conf")

            else
                log_message "app_init: 前后配置文件没有差异，跳过执行......"

            
            fi
        else
            diff_count_health=$((diff_count_health + 1))
            diff_count=$((diff_count + 1))

            log_message "app_init: ${HEALTH_TMP_DIR}/${service_name}_health.conf 不存在同名文件，直接覆盖"
            cp "${HEALTH_TMP_DIR}/${service_name}_health.conf" "${HEALTH_PREV_DIR}/${service_name}_health.conf"
            # 复制到datakit 配置目录
            cp "${HEALTH_TMP_DIR}/${service_name}_health.conf" "${HEALTH_DIR}/"
        fi  
    done
}


# 生成临时配置文件
run_main() {
    # 读取 JSON 数据并解析
    services=$(jq -c '.data[]' tmp.json)
    log_message "app_init: services: $services"

    for service in $services; do
        service_name=$(echo "$service" | jq -r 'keys[0]')
        # 打印 service_name 日志
        log_message "app_init: service_name: $service_name"
        # 打印 service 日志
        log_message "app_init: service: $service"

        # 处理 logging
        process_logging "$service_name" "$service"
        
        # 处理 metrics
        process_metrics "$service_name" "$service"

        # 处理 health
        process_health "$service_name" "$service"
    done
}





restart_datakit() {
    log_message "app_init: 正在重启 DataKit 服务..."
    $sudo_cmd datakit service -R || $sudo_cmd systemctl restart datakit
    log_message "app_init: DataKit 服务重启命令已执行"
}

check_port_and_restart() {
    local attempts=0
    local max_attempts=10
    local restart_count=0

    while [ $attempts -lt $max_attempts ]; do
        if netstat -tuln | grep -q ":9529"; then
            log_message "app_init: DataKit 服务在 9529 端口运行"
            return 0
        fi
        sleep 2
        attempts=$((attempts + 1))
        log_message "app_init: 正在等待 9529 端口... (第 %d 次尝试/%d)" "$attempts" "$max_attempts"
    done

    while [ $restart_count -lt 3 ]; do
        restart_datakit
        attempts=0

        while [ $attempts -lt $max_attempts ]; do
            if netstat -tuln | grep -q ":9529"; then
                log_message "app_init: DataKit 服务已成功重启并在 9529 端口运行"
                return 0
            fi
            sleep 2
            attempts=$((attempts + 1))
            log_message "app_init: 正在等待 9529 端口... (第 %d 次尝试/%d)" "$attempts" "$max_attempts"
        done

        restart_count=$((restart_count + 1))
        log_message "app_init: 第 %d 次重启后，9529 端口仍未监听" "$restart_count"
    done

    log_message "app_init: 错误: 连续重启 DataKit 3 次后仍未能在 9529 端口监听，异常退出"
    return 1
}
# 判断业务日志路径是否存在
# remove_logging_line() {
#     # 定义日志文件路径和配置文件路径
#     LOG_FILES_PATH="/home/app/**/logs/*.log"
#     LOGGING_CONF="$LOGGING_DIR/logging.conf"  # 

#     # 检查日志文件是否存在
#     if ls $LOG_FILES_PATH 1> /dev/null 2>&1; then
#         log_message "app_init: 日志文件存在，检查 logging.conf 中是否包含指定行..."

#         # 检查 logging.conf 中是否包含指定行
#         if grep -qF "$LOG_FILES_PATH" "$LOGGING_CONF"; then
#             log_message "app_init: 找到指定行，正在删除..."
#             # 使用 sed 删除指定行
#             sed -i -e 's+"/home/app/\*\*/logs/\*.log",++g' $LOGGING_CONF

#             log_message "app_init: 指定行已删除。"
#         else
#             log_message "app_init: logging.conf 中未找到指定行,保持原有配置。"
#         fi
#     else
#         log_message "app_init: 没有找到logging.conf采集器文件。"
#     fi



# }



# 从 ops 获取数据
fetch_json_from_ops

# 判断 tmp.json 是否存在，并且是否为json格式
if [ ! -f "tmp.json" ] || ! jq empty "tmp.json"; then
    log_message "app_init: 【ERROR】tmp.json 文件不存在或不是有效的 JSON 格式"
    exit 1
fi


# 执行主程序
run_main
# 校验日志是否存在重复采集
# remove_logging_line
# 打印 当前 diff_count 值
log_message "app_init: 【INFO】当前总差异数: $diff_count"
log_message "app_init: 【INFO】当前【logging】差异数: $diff_count_logging" 
log_message "app_init: 【INFO】当前【logging】差异文件列表: ${logging_diff_file_list[@]}"
log_message "app_init: 【INFO】当前【metrics】差异数: $diff_count_metrics"
log_message "app_init: 【INFO】当前【metrics】差异文件列表: ${metrics_diff_file_list[@]}"
log_message "app_init: 【INFO】当前【health】 差异数: $diff_count_health"
log_message "app_init: 【INFO】当前【health】 差异文件列表: ${health_diff_file_list[@]}"

# 如果 logging_diff_file_list 不为空，则将差异文件列表拷贝到对应存储目录中
if [ ${#logging_diff_file_list[@]} -gt 0 ]; then
    for file in "${logging_diff_file_list[@]}"; do
        # 将差异文件与datakit 存储目录下同名文件合并
        logging_merge_json "$file"
        # 打印 file 日志
        log_message "app_init: file: $file 合并完成"

    done
fi

# 如果 metrics_diff_file_list 不为空，则将差异文件列表拷贝到对应存储目录中
if [ ${#metrics_diff_file_list[@]} -gt 0 ]; then
    for file in "${metrics_diff_file_list[@]}"; do
        # 将差异文件与datakit 存储目录下同名文件合并
        metrics_merge_json "$file"
        # 打印 file 日志
        log_message "app_init: file: $file 合并完成"
    done
fi

# 如果 health_diff_file_list 不为空，则将差异文件列表拷贝到对应存储目录中
if [ ${#health_diff_file_list[@]} -gt 0 ]; then
    for file in "${health_diff_file_list[@]}"; do
        # 将差异文件与datakit 存储目录下同名文件合并
        health_merge_json "$file"
        # 打印 file 日志
        log_message "app_init: file: $file 合并完成"
    done
fi


if [ $diff_count -gt 0 ]; then  
    restart_datakit
    check_port_and_restart
fi
