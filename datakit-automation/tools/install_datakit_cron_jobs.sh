#!/bin/bash

set -euo pipefail

# 说明:
# 1) 先执行 setup_complete_permissions.sh，确保创建 datakit 用户并完成权限配置
# 2) 将 datakit_acl_update.sh 与 set_datakit_resource_limits.sh 复制到 /usr/local/src/sys_mgt/
# 3) 为 root 安装 crontab 定时任务，参照 datakit_acl_update.sh 注释（*/2 * * * * + flock + timeout）

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error(){ echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

check_root() {
    if [ "${EUID}" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

run_setup_permissions() {
    local setup_script="./setup_complete_permissions.sh"
    if [ ! -f "$setup_script" ]; then
        log_error "找不到脚本: $setup_script"
        exit 1
    fi
    chmod +x "$setup_script" || true
    log_info "执行: $setup_script"
    "$setup_script"
}

install_system_scripts() {
    local dst_dir="/usr/local/src/sys_mgt"
    mkdir -p "$dst_dir"

    local src_acl="./datakit_acl_update.sh"
    local src_limits="./set_datakit_resource_limits.sh"

    if [ ! -f "$src_acl" ]; then
        log_error "找不到脚本: $src_acl"
        exit 1
    fi
    if [ ! -f "$src_limits" ]; then
        log_error "找不到脚本: $src_limits"
        exit 1
    fi

    cp "$src_acl"    "$dst_dir/datakit_acl_update.sh"
    cp "$src_limits" "$dst_dir/set_datakit_resource_limits.sh"
    chmod 755 "$dst_dir/datakit_acl_update.sh" "$dst_dir/set_datakit_resource_limits.sh"
    log_info "脚本已安装到: $dst_dir"
}

ensure_cron_job() {
    local line="$1"
    # 读取当前 root crontab（若不存在则忽略错误）
    local current
    current=$(crontab -l 2>/dev/null || true)
    if echo "$current" | grep -Fq "$line"; then
        log_info "已存在定时任务: $line"
        return 0
    fi
    # 追加并安装
    {
        echo "$current"
        echo "$line"
    } | crontab -
    log_info "已新增定时任务: $line"
}



install_cron_jobs() {
    # 检查并注释旧的 setfacl 定时任务
    local old_cron_pattern="/user/bin/killall setfacl;/usr/bin/setfacl -R -m read:rx /home/app/ /var/log/;/usr/bin/setfacl -m read:rw /var/log/history.log;/usr/bin/setfacl -R -b /home/app/.ssh /var/log/wtmp /var/log/btmp"

    # 读取当前 crontab
    local current
    current=$(crontab -l 2>/dev/null || true)

    # 检查是否存在旧的 setfacl 定时任务
    if echo "$current" | grep -Fq "$old_cron_pattern"; then
        log_info "发现旧的 setfacl 定时任务，正在注释..."

        # 创建临时文件来存储修改后的 crontab
        local temp_cron=$(mktemp)

        # 将旧任务注释掉
        echo "$current" | sed "s|^\(.*$old_cron_pattern.*\)$|# \1|" > "$temp_cron"

        # 安装修改后的 crontab
        crontab "$temp_cron"
        # 安全清理临时文件（使用 unlink 替代 rm）
        unlink "$temp_cron" 2>/dev/null || true

        log_info "已注释旧的 setfacl 定时任务"
    else
        log_info "未发现旧的 setfacl 定时任务"
    fi

    # 参考 datakit_acl_update.sh 注释: */2 * * * * flock -xn /tmp/datakit_acl_update.lock timeout 100 /bin/bash /usr/local/src/sys_mgt/datakit_acl_update.sh
    local cron_acl="*/2 * * * * flock -xn /tmp/datakit_acl_update.lock timeout 100 /bin/bash /usr/local/src/sys_mgt/datakit_acl_update.sh"
    ensure_cron_job "$cron_acl"


    # 为资源限制脚本设置相同的周期与并发保护
    local cron_limits="*/30 * * * * flock -xn /tmp/set_datakit_resource_limits.lock timeout 100 /bin/bash /usr/local/src/sys_mgt/set_datakit_resource_limits.sh"
    ensure_cron_job "$cron_limits"
}

main() {
    check_root
    log_info "开始执行 Datakit 定时任务安装流程..."
    run_setup_permissions
    install_system_scripts
    install_cron_jobs
    log_info "全部完成"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi