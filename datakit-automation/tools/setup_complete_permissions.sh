#!/bin/bash

#=================================================
# Datakit完整权限设置脚本
#=================================================
# 功能: 创建所有必要的目录并配置datakit用户权限
#=================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
        "/var/log/datakit/runtime"
        "/var/log/datakit/runtime/releases"
        "/var/log/datakit/runtime/releases/current"
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
        "/var/lib/datakit"
        "/var/log/datakit"
        "/var/run/datakit"
        "/tmp/datakit"
    )
    
    for dir in "${own_dirs[@]}"; do
        chown -R datakit:datakit "$dir"
        chmod -R 755 "$dir"
        log_info "设置权限: $dir -> datakit:datakit 755"
    done
    
    # 特殊权限设置
    chmod 1777 /tmp/datakit  # 临时目录权限
    log_info "设置临时目录权限: /tmp/datakit -> 1777"
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

# 验证配置
verify_configuration() {
    log_info "验证配置..."
    
    # 验证sudoers语法
    if visudo -c -f /etc/sudoers.d/datakit; then
        log_info "✓ sudoers语法验证通过"
    else
        log_error "✗ sudoers语法验证失败"
        return 1
    fi
    
    # 验证目录权限
    local test_dirs=(
        "/opt/datakit"
        "/usr/local/datakit"
        "/var/lib/datakit"
        "/var/log/datakit"
        "/var/run/datakit"
        "/tmp/datakit"
    )
    
    for dir in "${test_dirs[@]}"; do
        if [ -d "$dir" ] && [ "$(stat -c '%U:%G' "$dir")" = "datakit:datakit" ]; then
            log_info "✓ 目录权限正确: $dir"
        else
            log_error "✗ 目录权限错误: $dir"
            return 1
        fi
    done
    
    # 测试datakit用户sudo权限
    if sudo -u datakit sudo -l >/dev/null 2>&1; then
        log_info "✓ datakit用户sudo权限验证通过"
    else
        log_error "✗ datakit用户sudo权限验证失败"
        return 1
    fi
    
    log_info "✓ 所有配置验证通过"
}

# 显示使用说明
show_usage() {
    log_info "配置完成！现在可以使用以下命令："
    echo
    echo "1. 启动安装服务："
    echo "   sudo systemctl start datakit_auto_installer"
    echo
    echo "2. 查看服务状态："
    echo "   sudo systemctl status datakit_auto_installer"
    echo
    echo "3. 查看日志："
    echo "   sudo journalctl -u datakit_auto_installer -f"
    echo
    echo "4. 手动测试权限："
    echo "   sudo -u datakit sudo -l"
    echo
    echo "5. 手动运行安装："
    echo "   sudo -u datakit DATAKIT_ENV=dev /opt/datakit/datakit_auto_installer.sh existing-install"
}

# 主函数
main() {
    log_info "开始配置Datakit完整权限..."
    
    check_root
    create_datakit_user
    create_directories
    set_directory_permissions
    configure_sudo_permissions
    verify_configuration
    
    log_info "Datakit权限配置完成！"
    show_usage
}

# 执行主函数
main "$@" 