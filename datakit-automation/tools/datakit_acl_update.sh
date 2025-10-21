#!/bin/bash
#
#===========================================================================================
# Description  : read用户权限更新脚本
# Script Name  : acl_update.sh
# Script Path  : /usr/local/src/sys_mgt/acl_update.sh
# Script Type  : shell
# Invocation   : crontab调用
# Crontab Item :
# Usage        : */2 * * * * flock -xn /tmp/acl_update.lock timeout 100 /bin/bash /usr/local/src/sys_mgt/acl_update.sh
# Example      : /bin/bash /usr/local/src/sys_mgt/acl_update.sh
# Adapted Site : defaults | third_party | nyx | sap | wtg | sap | ox
# Adapted OS   : Ubuntu 18.04 | Ubuntu 20.04 | Ubuntu 22.04 | Ubuntu 24.04 ｜ CentOS 7.9
# Author       : Will
# Created Date : 2025-10-21
# Version      : V2025.10.21.01
#
# History      :
#   2025-10-21  Will  V2025.10.21.01|  新增
#===========================================================================================
#
# 全局设置日志文件路径
LOG_FILE="/var/log/datakit/datakit_acl_update.log"

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
if ! id "read" &>/dev/null; then
    log "错误：用户 'read' 不存在，请先创建用户"
    exit 1
fi

if ! id "datakit" &>/dev/null; then
    log "错误：用户 'datakit' 不存在，请先创建用户"
    exit 1
fi

# 检查是否为NFS挂载点的函数
is_nfs_mount() {
    local path=$1
    # 方法1: 检查挂载信息
    if mount | grep -q "^[^[:space:]]* on $path type nfs"; then
        return 0
    fi

    # 方法2: 检查文件系统类型
    local fs_type=$(stat -f -c %T "$path" 2>/dev/null)
    if [[ "$fs_type" =~ ^nfs ]]; then
        return 0
    fi

    return 1
}

# 授予read用户访问/home/app/目录的权限
process_dir() {
    local path=$1
    if [[ -d "$path" ]]; then
        log "正在处理 $path 目录..."

        # 检查根目录是否为NFS
        if is_nfs_mount "$path"; then
            log "跳过NFS挂载点: $path"
            return 0
        fi

        # 获取所有NFS挂载点，用于排除
        local nfs_mounts=$(mount | grep "type nfs" | awk '{print $3}' | grep "^$path" || true)

        set +e
        if [[ -n "$nfs_mounts" ]]; then
            # 构建排除参数
            local exclude_args=""
            while IFS= read -r nfs_mount; do
                exclude_args="$exclude_args -path $nfs_mount -prune -o"
            done <<< "$nfs_mounts"

            log "排除NFS挂载点: $nfs_mounts"
            # 2次find：目录和文件分别处理，但合并用户权限设置
            eval "find '$path' $exclude_args -type d -exec setfacl -m u:read:rx,u:datakit:rx {} + 2>/dev/null"
            eval "find '$path' $exclude_args -type f -exec setfacl -m u:read:r,u:datakit:r {} + 2>/dev/null"
        else
            # 没有NFS子挂载点，2次find处理
            find "$path" -type d -exec setfacl -m u:read:rx,u:datakit:rx {} + 2>/dev/null
            find "$path" -type f -exec setfacl -m u:read:r,u:datakit:r {} + 2>/dev/null
        fi
        set -e

        log "$path ACL设置完成"
        return 0
    else
        log "警告：$path 目录不存在"
        return 1
    fi
}


# 通用特殊文件处理函数
handle_special_files() {
    declare -a files=(
        # 格式: "文件路径:权限"
        # read
        "/var/log/read_history.log:u:read:rw"
        "/var/log/app_history.log:u:app:rw"
        "/var/log/app_history.log:u:read:-"
        "/var/log/root_history.log:u:read:-"
        # datakit
        "/var/log/read_history.log:u:datakit:-"
        "/var/log/app_history.log:u:datakit:-"
        "/var/log/root_history.log:u:datakit:-"
    )

    for spec in "${files[@]}"; do
        IFS=":" read -r file perm <<< "$spec"

        if [[ -e "$file" ]]; then
            # "-" 表示删除权限
            if [[ "$perm" == "-" ]]; then
                setfacl -b "$file"
                log "清除权限: $file"
            else
                setfacl -m "$perm" "$file"
                log "设置权限: $file => $perm"
            fi
        else
            log "注意: 特殊文件不存在 - $file"
        fi
    done
}


# 清除敏感目录权限
clear_sensitive_dirs_files() {
    local dirs_files=(
        "/home/app/.ssh"
        "/var/log/wtmp"
        "/var/log/btmp"
    )

    for dir_file in "${dirs_files[@]}"; do
        if [[ -e "$dir_file" ]]; then
            # 清除ACL权限后，设置默认权限
            setfacl -R -b "$dir_file"
            log "$dir_file ACL已清除，基础权限加固完成"
        else
           log "$dir_file 不存在，跳过"
        fi
    done
}

# ===== 主执行逻辑 =====
main() {
    # 处理主目录
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

    # 特殊文件处理
    handle_special_files

    # 敏感目录处理
    clear_sensitive_dirs_files

    log "===== ACL权限更新完成 ====="
    exit 0
}

# 执行主函数
main