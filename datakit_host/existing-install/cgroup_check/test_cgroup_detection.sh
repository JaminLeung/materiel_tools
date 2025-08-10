#!/bin/bash

# cgroup检测功能测试脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_info() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 测试cgroup检测功能
test_cgroup_detection() {
    echo "=== cgroup检测功能测试 ==="
    echo
    
    # 1. 检查cgroup挂载点
    log_info "1. 检查cgroup挂载点"
    local cgroup_mounts=$(mount | grep -E "cgroup|cgroup2" | awk '{print $3}' | sort -u)
    if [ -n "$cgroup_mounts" ]; then
        log_info "检测到cgroup挂载点: $cgroup_mounts"
    else
        log_warning "未检测到cgroup挂载点"
    fi
    echo
    
    # 2. 检查cgroup文件系统类型
    log_info "2. 检查cgroup文件系统类型"
    local cgroup_fs=$(mount | grep -E "cgroup|cgroup2" | awk '{print $5}' | sort -u)
    if [ -n "$cgroup_fs" ]; then
        log_info "cgroup文件系统类型: $cgroup_fs"
    else
        log_warning "未检测到cgroup文件系统"
    fi
    echo
    
    # 3. 检查cgroup v2
    log_info "3. 检查cgroup v2支持"
    if [ -d "/sys/fs/cgroup/unified" ] || ([ -d "/sys/fs/cgroup" ] && [ -f "/sys/fs/cgroup/cgroup.controllers" ]); then
        log_info "检测到cgroup v2支持"
        if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
            local controllers=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null | tr '\n' ' ')
            log_info "v2控制器: $controllers"
        fi
    else
        log_warning "未检测到cgroup v2支持"
    fi
    echo
    
    # 4. 检查cgroup v1
    log_info "4. 检查cgroup v1支持"
    local v1_controllers=""
    if [ -d "/sys/fs/cgroup/cpu" ]; then
        v1_controllers="$v1_controllers cpu"
    fi
    if [ -d "/sys/fs/cgroup/memory" ]; then
        v1_controllers="$v1_controllers memory"
    fi
    if [ -d "/sys/fs/cgroup/cpu,cpuacct" ]; then
        v1_controllers="$v1_controllers cpu,cpuacct"
    fi
    
    if [ -n "$v1_controllers" ]; then
        log_info "检测到cgroup v1控制器: $v1_controllers"
    else
        log_warning "未检测到cgroup v1控制器"
    fi
    echo
    
    # 5. 检查systemd cgroup
    log_info "5. 检查systemd cgroup"
    if [ -d "/sys/fs/cgroup/systemd" ]; then
        log_info "检测到systemd cgroup"
        if systemctl --version >/dev/null 2>&1; then
            local systemd_cgroup=$(systemctl show --property=ControlGroup | cut -d'=' -f2)
            log_info "systemd cgroup路径: $systemd_cgroup"
        fi
    else
        log_warning "未检测到systemd cgroup"
    fi
    echo
    
    # 6. 检查legacy cgroup
    log_info "6. 检查legacy cgroup"
    if [ -d "/cgroup" ]; then
        log_info "检测到legacy cgroup路径: /cgroup"
        if [ -d "/cgroup/cpu" ]; then
            log_info "Legacy CPU控制器: 可用"
        fi
        if [ -d "/cgroup/memory" ]; then
            log_info "Legacy 内存控制器: 可用"
        fi
    else
        log_warning "未检测到legacy cgroup"
    fi
    echo
    
    # 7. 检查权限
    log_info "7. 检查cgroup权限"
    local cgroup_root="/sys/fs/cgroup"
    if [ -w "$cgroup_root" ]; then
        log_info "有cgroup目录的写权限: $cgroup_root"
    else
        log_warning "没有cgroup目录的写权限: $cgroup_root"
    fi
    echo
    
    # 8. 检查当前进程cgroup
    log_info "8. 检查当前进程cgroup"
    if [ -f "/proc/self/cgroup" ]; then
        local current_cgroup=$(cat /proc/self/cgroup 2>/dev/null || echo '无法获取')
        log_info "当前进程cgroup: $current_cgroup"
    else
        log_warning "无法获取当前进程cgroup信息"
    fi
    echo
    
    # 9. 检查内核支持
    log_info "9. 检查内核cgroup支持"
    log_info "内核版本: $(uname -r)"
    local cgroup_modules=$(lsmod | grep -i cgroup || echo "无相关模块")
    log_info "cgroup相关内核模块: $cgroup_modules"
    echo
    
    # 10. 确定cgroup版本
    log_info "10. 确定cgroup版本"
    local detected_version=""
    local detected_root=""
    
    if [ -d "/sys/fs/cgroup/unified" ] || ([ -d "/sys/fs/cgroup" ] && [ -f "/sys/fs/cgroup/cgroup.controllers" ]); then
        detected_version="v2"
        detected_root="/sys/fs/cgroup"
    elif [ -d "/sys/fs/cgroup/cpu" ] || [ -d "/sys/fs/cgroup/memory" ] || [ -d "/sys/fs/cgroup/cpu,cpuacct" ]; then
        detected_version="v1"
        detected_root="/sys/fs/cgroup"
    elif [ -d "/sys/fs/cgroup/unified" ] && ([ -d "/sys/fs/cgroup/cpu" ] || [ -d "/sys/fs/cgroup/memory" ]); then
        detected_version="hybrid"
        detected_root="/sys/fs/cgroup"
    elif [ -d "/sys/fs/cgroup/systemd" ]; then
        detected_version="systemd"
        detected_root="/sys/fs/cgroup"
    elif [ -d "/cgroup" ]; then
        detected_version="legacy"
        detected_root="/cgroup"
    else
        detected_version="none"
        detected_root=""
    fi
    
    if [ "$detected_version" != "none" ]; then
        log_info "检测到的cgroup版本: $detected_version"
        log_info "cgroup根目录: $detected_root"
    else
        log_error "未检测到cgroup支持"
    fi
}

# 运行测试
test_cgroup_detection

echo
echo "=== 测试完成 ===" 