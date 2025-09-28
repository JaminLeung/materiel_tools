#!/bin/bash
#
#===========================================================================================
# Description  : datakit用户权限更新脚本
# Script Name  : datakit_acl_update.sh
# Script Path  : /usr/local/src/sys_mgt/datakit_acl_update.sh
# Script Type  : shell
# Invocation   : crontab调用
# Crontab Item :
# Usage        : */2 * * * * flock -xn /tmp/datakit_acl_update.lock timeout 100 /bin/bash /usr/local/src/sys_mgt/da taki t_acl_update.sh
# Example      : /bin/bash /usr/local/src/sys_mgt/datakit_acl_update.sh
# Adapted Site : defaults | third_party | nyx | sap | wtg | sap | ox
# Adapted OS   : Ubuntu 18.04 | Ubuntu 20.04 | Ubuntu 22.04 | Ubuntu 24.04 ｜ CentOS 7.9
# Author       : Will
# Created Date : 2025-09-08
# Version      : V2025.09.08.01
#
# History      :
#   2025-07-10  Will  V2025.09.08.01 |  新增
#===========================================================================================
#
# 全局设置日志文件路径
LOG_FILE="/var/log/datakit_acl_update.log"

# 初始化日志函数
log() {
    local message="[$(date +'%F %T')] $1"
    echo "$message" >> "$LOG_FILE"
    # 当有终端时（手动运行）也输出到控制台
    if [ -t 1 ]; then
        echo "$message"
    fi
}
# 严格错误处理
set -euo pipefail
trap '[ $? -ne 0 ] && log "错误发生在 ${BASH_SOURCE[0]}:${LINENO}"; exit 1' ERR



log "===== ACL权限更新开始 ====="

# 检查用户存在性（防止错误设置）
if ! id "datakit" &>/dev/null; then
    log "错误：用户 'datakit' 不存在，请先创建用户"
    exit 1
fi

# 授予datakit用户访问目录的权限
process_dir() {
    local path=$1
    if [[ -d "$path" ]]; then
        log "正在处理 $path 目录..."

        # 使用高效的单次setfacl调用
        find "$path" -type d -print0 | xargs -0r setfacl -m u:datakit:rx
        find "$path" -type f -print0 | xargs -0r setfacl -m u:datakit:r

        log "$path ACL设置完成"
        return 0
    else
        log "警告：$path 目录不存在"
        return 1
    fi
}


# 清除敏感目录和文件权限
clear_sensitive_dirs_files() {
    local dirs_files=(
        "/home/app/.ssh"
        "/var/log/wtmp"
        "/var/log/btmp"
    )

    for dir_file in "${dirs_files[@]}"; do
        if [[ -e "$dir_file" ]]; then
            # 判断是目录还是文件
            if [[ -d "$dir_file" ]]; then
                # 目录：递归清除ACL权限
                setfacl -R -b "$dir_file"
                log "$dir_file 目录ACL已清除，基础权限加固完成"
            elif [[ -f "$dir_file" ]]; then
                # 文件：清除ACL权限
                setfacl -b "$dir_file"
                log "$dir_file 文件ACL已清除，基础权限加固完成"
            fi
        else
            log "注意: 敏感路径不存在 - $dir_file"
        fi
    done
}

# ===== 主执行逻辑 =====
main() {
    #基础目录
    process_dir "/opt/datakit"
    process_dir "/usr/local/datakit"
    process_dir "/usr/local/datakit/conf.d"
    process_dir "/var/log/datakit"
    process_dir "/var/run/datakit"
    process_dir "/tmp/datakit"
    process_dir "/var/log"
    process_dir "/home/app"
    process_dir "/data/processLog"
    process_dir "/data/invokeLog"
    process_dir "/data/probeLog"

    # 敏感目录处理
    clear_sensitive_dirs_files

    log "===== ACL权限更新完成 ====="
    exit 0
}

# 执行主函数
main