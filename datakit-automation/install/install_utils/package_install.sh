#!/bin/bash

#=================================================
# 包安装工具模块
#=================================================
# 功能: 通用包安装、解压、工具安装
#=================================================

# 解压文件
extract_package() {
    local package_path="$1"
    local extract_dir="$2"
    
    log_info "解压文件: $package_path"
    
    if [ ! -f "$package_path" ]; then
        log_error "文件不存在: $package_path"
        return 1
    fi
    
    # 创建解压目录
    mkdir -p "$extract_dir"
    cd "$extract_dir"
    
    # 根据文件类型解压
    case "$package_path" in
        *.tar.gz|*.tgz)
            if tar -xzf "$package_path"; then
                log_success "解压成功: $package_path"
                return 0
            else
                log_error "解压失败: $package_path"
                return 1
            fi
            ;;
        *.tar)
            if tar -xf "$package_path"; then
                log_success "解压成功: $package_path"
                return 0
            else
                log_error "解压失败: $package_path"
                return 1
            fi
            ;;
        *.zip)
            if unzip -q "$package_path"; then
                log_success "解压成功: $package_path"
                return 0
            else
                log_error "解压失败: $package_path"
                return 1
            fi
            ;;
        *)
            log_error "不支持的文件格式: $package_path"
            return 1
            ;;
    esac
}

# 安装工具到系统目录
install_tools() {
    local tools_dir="$1"
    
    log_info "安装工具到系统目录..."
    
    if [ ! -d "$tools_dir" ]; then
        log_error "工具目录不存在: $tools_dir"
        return 1
    fi
    
    cd "$tools_dir"
    
    # 安装jq
    if [ -f "./jq" ]; then
        cp ./jq /usr/local/bin/ && chmod +x /usr/local/bin/jq
        log_info "jq工具安装完成"
    fi
    
    # 安装yj
    if [ -f "./yj" ]; then
        cp ./yj /usr/local/bin/ && chmod +x /usr/local/bin/yj
        log_info "yj工具安装完成"
    fi
    
    log_success "工具安装完成"
}

# 检查必需的工具
check_required_tools() {
    local missing_tools=()
    
    # 检查必需的工具
    local required_tools=("curl" "jq" "systemctl" "tar")
    
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必需的工具: ${missing_tools[*]}"
        return 1
    fi
    
    log_success "所有必需工具检查通过"
    return 0
}

# 创建备份
create_backup() {
    local source_path="$1"
    local backup_dir="$2"
    
    if [ ! -e "$source_path" ]; then
        log_info "源路径不存在，无需备份: $source_path"
        return 0
    fi
    
    # 创建备份目录
    mkdir -p "$backup_dir"
    
    # 生成备份文件名
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$source_path")
    local backup_path="$backup_dir/${basename}.backup.${timestamp}"
    
    # 执行备份
    if cp -r "$source_path" "$backup_path"; then
        log_success "备份创建成功: $backup_path"
        return 0
    else
        log_error "备份创建失败: $source_path"
        return 1
    fi
}

# 清理临时文件
cleanup_temp_files() {
    local temp_dir="$1"
    
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        log_info "清理临时文件: $temp_dir"
        rm -rf "$temp_dir"
        log_success "临时文件清理完成"
    fi
} 