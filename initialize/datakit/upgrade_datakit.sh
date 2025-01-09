#!/bin/bash

sleep $((RANDOM % 300 + 1))

STATIC_URL="https://static-api.pre-guance.houtai.io/guance/datakit"
DATAWAY_URL="https://dataway.pre-guance.houtai.io"
UPDATE_INFO_URL="$STATIC_URL/datakit_update_info.json"
DATAKIT_VERSION_CMD="datakit version | grep -oP 'Version: \K[0-9]+\.[0-9]+\.[0-9]+'"
UPDATE_INFO_FILE="/opt/datakit/datakit_update_info.json"
CURRENT_VERSION=$(eval $DATAKIT_VERSION_CMD)
CURRENT_TOKEN=$(grep -oP 'tkn_\w+' /usr/local/datakit/conf.d/datakit.conf | head -n 1)

# 获取最新版本、升级类型、配置文件路径、配置文件key、配置文件value
UPGRADE_INFO=$(curl -s "$UPDATE_INFO_URL")
LATEST_VERSION=$(echo "$UPGRADE_INFO" | jq -r '.upgrade_version')
UPGRADE_TYPE=$(echo "$UPGRADE_INFO" | jq -r '.upgrade_type')

log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    LOG_FILE="/opt/datakit/upgrade_datakit.log"
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
    echo "$timestamp - $message" >> "$LOG_FILE"
}

# 检查9529端口是否监听，如果未监听则重启datakit
check_port_and_restart() {
    local attempts=0
    local max_attempts=10
    local restart_count=0

    while [ $attempts -lt $max_attempts ]; do
        if netstat -tuln | grep -q ":9529"; then
            log_message "upgrade_datakit:  DataKit 服务在 9529 端口运行"
            return 0
        fi
        sleep 2
        attempts=$((attempts + 1))
        log_message "upgrade_datakit: 正在等待 9529 端口... (第 %d 次尝试/%d)\n" "$attempts" "$max_attempts"
    done

    while [ $restart_count -lt 3 ]; do
        restart_datakit
        attempts=0

        while [ $attempts -lt $max_attempts ]; do
            if netstat -tuln | grep -q ":9529"; then
                log_message "upgrade_datakit:  DataKit 服务已成功重启并在 9529 端口运行"
                return 0
            fi
            sleep 2
            attempts=$((attempts + 1))
            log_message "upgrade_datakit: 正在等待 9529 端口... (第 %d 次尝试/%d)\n" "$attempts" "$max_attempts"
        done

        restart_count=$((restart_count + 1))
        log_message "upgrade_datakit: 第 %d 次重启后，9529 端口仍未监听\n" "$restart_count"
    done

    log_message "upgrade_datakit: 错误: 连续重启 DataKit 3 次后仍未能在 9529 端口监听，异常退出"
    return 1
}

# 加载配置文件
load_config_file() {
    # 如果 LATEST_VERSION 与 CURRENT_VERSION 相等，则不进行升级
    if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
        log_message "upgrade_datakit: 当前版本与最新版本一致，跳过升级退出。"
        return 1
    fi

    log_message "upgrade_datakit: 当前版本与最新版本不一致，开始升级/回滚 datakit..."

    # 如果 UPGRADE_TYPE 为 rollback 则无需执行配置操作
    if [ "$UPGRADE_TYPE" == "rollback" ]; then
        log_message "upgrade_datakit: 当前版本为回滚版本，无需执行配置操作"
    fi

    log_message "upgrade_datakit: 当前版本为升级版本，执行配置操作"

    # 下载当前版本的installer-linux-amd64
    UPGRADER_NAME="installer-linux-amd64-$LATEST_VERSION"
    UPGRADER_URL="$STATIC_URL/$UPGRADER_NAME"

    wget -O "/opt/datakit/$UPGRADER_NAME" "$UPGRADER_URL"

    if [ $? -ne 0 ]; then
        log_message "upgrade_datakit: 下载失败，异常退出,upgrade_current_version:$CURRENT_VERSION,upgrade_latest_version:$LATEST_VERSION,upgrade_type:$UPGRADE_TYPE,upgrade_error_message:download_failed"
        return 1
    fi

    chmod +x "/opt/datakit/$UPGRADER_NAME"

    # 执行升级
    /opt/datakit/$UPGRADER_NAME --upgrade --installer_base_url="$STATIC_URL"

    # 检查9529端口是否监听，如果未监听则重启datakit
    check_port_and_restart

    if netstat -tuln | grep -q ":9529"; then
        log_message "upgrade_datakit: DataKit 服务已成功重启并在 9529 端口运行"
        UPGRADE_STATUS="success"
    else
        log_message "upgrade_datakit: DataKit 服务重启失败，异常退出,upgrade_current_version:$CURRENT_VERSION,upgrade_latest_version:$LATEST_VERSION,upgrade_type:$UPGRADE_TYPE,upgrade_error_message:datakit_not_running"
        UPGRADE_STATUS="failed"

        return 1
    fi  
}

load_config_file