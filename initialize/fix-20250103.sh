#! /bin/bash


installer_base_url="https://static-api.pre-guance.houtai.io/guance/datakit"


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
            log_message "fix-20250103: 23 line DataKit 服务在 9529 端口运行"
            return 0
        fi
        sleep 2
        attempts=$((attempts + 1))
        log_message "fix-20250103: 28 line 正在等待 9529 端口... (第 %d 次尝试/%d)" "$attempts" "$max_attempts"
    done

    while [ $restart_count -lt 3 ]; do
        restart_datakit
        attempts=0

        while [ $attempts -lt $max_attempts ]; do
            if netstat -tuln | grep -q ":9529"; then
                log_message "fix-20250103: 37 line DataKit 服务已成功重启并在 9529 端口运行"
                return 0
            fi
            sleep 2
            attempts=$((attempts + 1))
            log_message "fix-20250103: 42 line 正在等待 9529 端口... (第 %d 次尝试/%d)" "$attempts" "$max_attempts"
        done

        restart_count=$((restart_count + 1))
        log_message "fix-20250103: 46 line 第 %d 次重启后，9529 端口仍未监听" "$restart_count"
    done

    log_message "fix-20250103: 49 line 错误: 连续重启 DataKit 3 次后仍未能在 9529 端口监听，异常退出"
    return 1
}

upgrade_logging_config() {

    cat <<EOF > /usr/local/datakit/conf.d/log/opt_datakit.conf
[[inputs.logging]]
  logfiles = [
    "/opt/datakit/*.log",
  ]

  ignore = [""]
  source = "opt_datakit_log"
  service = "opt_datakit_log"
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

    log_message " upgrade_logging_config 修改完成"

}

upgrade_cloud_provider() {
# 修改datakit 配置文件 /usr/local/datakit/conf.d/host/hostobject.conf 文件 中 
        UPGRADE_CONFIG_PATH="/usr/local/datakit/conf.d/host/hostobject.conf"
        UPGRADE_SOURCE_CONTENT="cloud_provider = \"aliyun\""
        UPGRADE_TARGET_CONTENT="cloud_provider = \"aws\""

        log_message "fix-20250103: 60 line 正在修改 $UPGRADE_CONFIG_PATH 文件，将 $UPGRADE_SOURCE_CONTENT 修改为 $UPGRADE_TARGET_CONTENT"

        sed -i "s|$UPGRADE_SOURCE_CONTENT|$UPGRADE_TARGET_CONTENT|g" "$UPGRADE_CONFIG_PATH"

        log_message "upgrade_cloud_provider 修改完成"
}

get_upgrade_datakit_script() {
    # 业务初始化脚本下载链接
    UPGRADE_SCRIPT_DOWNLOAD_URL="$installer_base_url/upgrade_datakit_debug.sh"

    # 本地存放路径
    UPGRADE_SCRIPT_DIR="/opt/datakit"
    UPGRADE_SCRIPT_PATH="/opt/datakit/upgrade_datakit.sh"

    if [ ! -d "$INIT_SCRIPT_DIR" ]; then
        mkdir -p "$UPGRADE_SCRIPT_DIR"
        printf "* 目录 %s 不存在，已创建\n" "$UPGRADE_SCRIPT_DIR"
    else
        printf "* 目录 %s 已存在\n" "$UPGRADE_SCRIPT_DIR"
    fi
    # 下载脚本
    echo "Download upgrade_datakit.sh ..."
    wget -q "$UPGRADE_SCRIPT_DOWNLOAD_URL" -O $UPGRADE_SCRIPT_PATH

    # 授权

    chmod +x $UPGRADE_SCRIPT_PATH
    echo "upgrade_datakit.sh Download successfully...."
}


set_cron_job_upgrade_datakit() {
    # 定义要执行的脚本路径
    UPGRADE_DATAKIT_SCRIPT_PATH="/opt/datakit/upgrade_datakit.sh"  # 请替换为实际的脚本路径

    # 检查脚本是否存在
    if [ ! -f "$UPGRADE_DATAKIT_SCRIPT_PATH" ]; then
        echo "Error: Script $UPGRADE_DATAKIT_SCRIPT_PATH does not exist."
        return 1
    fi

    # 检查是否已存在相同的 cron 任务
    if crontab -l 2>/dev/null | grep -q "$UPGRADE_DATAKIT_SCRIPT_PATH"; then
        echo "Cron job for $UPGRADE_DATAKIT_SCRIPT_PATH already exists. Exiting."
        return 0
    fi

    # 创建一个新的 cron 任务
    (crontab -l 2>/dev/null; echo "*/5 * * * * $UPGRADE_DATAKIT_SCRIPT_PATH") | crontab -

    echo "Cron job set to execute $UPGRADE_DATAKIT_SCRIPT_PATH every 5 minutes."

}



upgrade_logging_config

upgrade_cloud_provider

get_upgrade_datakit_script

set_cron_job_upgrade_datakit

# 重启datakit
datakit service -R
log_message "fix-20250103: 重启datakit"

# 检查9529端口是否监听
check_port_and_restart


