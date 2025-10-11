#!/bin/bash

#=================================================
# Datakit完整权限设置脚本
#=================================================
# 功能: 创建所有必要的目录并配置datakit用户权限
#=================================================

set -e


# 日志函数
log_info() {
    echo -e "[INFO] ${NC} $1"
}

log_warn() {
    echo -e "[WARN] ${NC} $1"
}

log_error() {
    echo -e "[ERROR] ${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "此脚本必须以root用户身份运行"
        exit 1
    fi
}

# 创建datakit用户
create_datakit_user() {
    log_info "创建datakit用户..."
    if ! id "datakit" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin --user-group datakit
        log_info "✓ 用户datakit创建成功"
    else
        log_info "✓ 用户datakit已存在"
    fi
}

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录..."

    # 基础目录
    local dirs=(
        "/opt/datakit"
        "/usr/local/datakit"
        "/usr/local/datakit/conf.d"
        "/var/log/datakit"
        "/var/run/datakit"
        "/tmp/datakit"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "创建目录: $dir"
        else
            log_info "目录已存在: $dir"
        fi
    done
}

# 设置目录权限
set_directory_permissions() {
    log_info "设置目录权限..."

    # 设置所有权
    local own_dirs=(
        "/opt/datakit"
        "/usr/local/datakit"
        "/var/run/datakit"
        "/var/log/datakit"
        "/tmp/datakit"
    )

    # 使用setfacl设置权限的目录
    local acl_dirs=(
        "/var/log"
        #"/proc"
        "/home/app" # 排除.ssh目录授权
        "/data/processLog"
        "/data/invokeLog"
        "/data/probeLog"
    )

    # 设置标准目录权限
    for dir in "${own_dirs[@]}"; do
        chown -R datakit:datakit "$dir"
        chmod -R 755 "$dir"
        log_info "设置权限: $dir -> datakit:datakit 755"
    done

    # 使用setfacl设置ACL权限（含默认ACL用于新建项继承）
    for dir in "${acl_dirs[@]}"; do
        # 如果是/home/app 目录，需要排除.ssh目录授权
        if [ "$dir" == "/home/app" ]; then
            if [ -d "$dir" ]; then
                setfacl -R -m u:datakit:rx -m d:u:datakit:rx "$dir"
                if [ -d "$dir/.ssh" ]; then
                    setfacl -R -x u:datakit "$dir/.ssh" || true
                    setfacl -R -x d:u:datakit "$dir/.ssh" || true
                fi
                log_info "设置ACL权限: $dir -> datakit:rx 且 d:datakit:rx (排除.ssh目录)"
            fi
        else
            if [ -d "$dir" ]; then
                setfacl -R -m u:datakit:rx -m d:u:datakit:rx "$dir"
                log_info "设置ACL权限: $dir -> datakit:rx 且 d:datakit:rx"
            fi
        fi
    done
}


# 将datakit用户添加到crontab组并授权
add_datakit_user_to_crontab_group() {
    log_info "将datakit用户添加到crontab组并授权..."
    if ! usermod -a -G crontab datakit; then
        log_info "✓ 用户datakit添加到crontab组失败"
    fi
}

# 配置sudo权限
configure_sudo_permissions() {
    log_info "配置sudo权限..."

    # 清理现有的sudoers文件
    cat > /etc/sudoers.d/datakit << 'EOF'
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl start datakit.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl stop datakit.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl restart datakit.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl status datakit.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl enable datakit.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl disable datakit.service



datakit ALL=(root) NOPASSWD: /usr/bin/systemctl enable node_exporter.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl disable node_exporter.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl start node_exporter.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl stop node_exporter.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl restart node_exporter.service
datakit ALL=(root) NOPASSWD: /usr/bin/systemctl status node_exporter.service


datakit ALL=(root) NOPASSWD: /usr/bin/systemctl daemon-reload

EOF

    chmod 440 /etc/sudoers.d/datakit
    log_info "✓ sudo权限配置完成"
}



# 主函数
main() {
    log_info "开始配置Datakit完整权限..."

    check_root
    create_datakit_user
    create_directories
    add_datakit_user_to_crontab_group
    set_directory_permissions
    configure_sudo_permissions

    log_info "Datakit权限配置完成！"
}

# 执行主函数
main "$@"