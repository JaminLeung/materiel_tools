# Core 核心模块

包含 Datakit 自动化安装工具的核心功能模块，一些公共的依赖也都在这里

## 目录结构

```
core/
├── README.md                    # 说明文档
├── utils.sh                     # 工具函数
├── logging.sh                   # 日志系统
├── validation.sh                # 验证相关
├── initialize.sh                # 初始化操作
├── datakit_service.sh           # Datakit 相关操作
```

## 模块功能详解

### 1. utils.sh - 工具函数模块

**功能**: 提供通用工具函数、文件操作、网络操作、系统操作等基础功能

**主要函数**:
- `dataway_log()` - Dataway日志上报函数
- `command_exists()` - 检查命令是否存在
- `file_exists()` - 检查文件是否存在
- `dir_exists()` - 检查目录是否存在
- `process_running()` - 检查进程是否运行
- `port_listening()` - 检查端口是否被监听
- `safe_execute()` - 安全执行命令并记录日志
- `retry_execute()` - 重试执行函数
- `timeout_execute()` - 超时执行命令
- `create_backup()` - 创建备份
- `cleanup_old_backups()` - 清理旧备份
- `cleanup_temp_files()` - 清理临时文件
- `cleanup_aws_credentials()` - 清理AWS凭证
- `get_host_ip()` - 获取本机IP地址
- `get_ops_config()` - 获取运维平台配置
- `get_host_info()` - 获取主机信息


**使用示例**:
```bash
source "core/utils.sh"

# 检查命令是否存在
if command_exists "curl"; then
    echo "curl 命令存在"
fi

# 安全执行命令
safe_execute "echo 'hello world'" "测试命令"

# 重试执行
retry_execute "curl -f http://example.com" 3 5 "网络请求"
```

### 2. logging.sh - 日志系统模块

**功能**: 提供多级别日志记录、结构化日志输出、日志轮转管理

**日志级别**:
- `DEBUG` (0) - 调试信息
- `INFO` (1) - 一般信息 (默认)
- `WARNING` (2) - 警告信息
- `ERROR` (3) - 错误信息
- `SUCCESS` (4) - 成功信息

**主要函数**:
- `log_debug()` - 记录调试日志
- `log_info()` - 记录一般信息
- `log_warning()` - 记录警告信息
- `log_error()` - 记录错误信息
- `log_success()` - 记录成功信息
- `record_script_start()` - 记录脚本启动
- `record_script_end()` - 记录脚本结束

**使用示例**:
```bash
source "core/logging.sh"

# 设置日志级别
export LOG_LEVEL=2  # WARNING级别

# 记录不同级别的日志
log_info "开始执行任务"
log_warning "发现潜在问题"
log_error "执行失败"
log_success "任务完成"

# 记录脚本执行信息
record_script_start
# ... 脚本执行 ...
record_script_end
```

### 3. validation.sh - 验证系统模块

**功能**: 环境变量验证、系统资源检查、网络连通性测试、配置文件验证

**主要函数**:
- `validate_required_commands()` - 验证必需的命令
- `validate_system_environment()` - 验证系统环境
- `validate_system_resources()` - 验证系统资源
- `validate_network_connectivity()` - 验证网络连通性
- `validate_environment_variables()` - 验证环境变量
- `validate_config_file()` - 验证配置文件

**验证内容**:
- 必需命令: curl, jq, systemctl
- 系统环境: root权限, systemd支持
- 系统资源: 磁盘空间, 内存, CPU负载
- 网络连通性: S3连接, Dataway连接, 运维平台连接

**使用示例**:
```bash
source "core/validation.sh"

# 验证系统环境
validate_system_environment || exit 1

# 验证系统资源
validate_system_resources || exit 1

# 验证网络连通性
validate_network_connectivity || exit 1
```

### 4. initialize.sh - 初始化系统模块

**功能**: 脚本初始化、进程管理、配置验证、环境准备

**主要函数**:
- `check_running_instance()` - 检查运行实例
- `create_backup_directory()` - 创建备份目录
- `check_current_user_permission()` - 检查用户权限
- `validate_system_resources()` - 验证系统资源
- `validate_config()` - 验证配置参数
- `validate_system_environment()` - 验证系统环境

**初始化流程**:
1. 检查运行实例 (防止重复运行)
2. 创建备份目录
3. 检查用户权限
4. 验证系统资源
5. 验证配置参数
6. 验证系统环境

**使用示例**:
```bash
source "core/initialize.sh"

# 执行完整初始化
check_running_instance
create_backup_directory
validate_config || exit 1
validate_system_environment || exit 1
```


### 5. datakit_service.sh - Datakit服务控制模块

**功能**: Datakit服务的启动、停止、重启、状态检查

**主要函数**:
- `check_datakit_status()` - 检查Datakit状态
- `start_datakit()` - 启动Datakit服务
- `stop_datakit()` - 停止Datakit服务
- `restart_datakit()` - 重启Datakit服务

**支持方式**:
- systemctl (systemd)
- datakit命令行工具
- 进程管理 (pkill)

**使用示例**:
```bash
source "core/datakit_service.sh"

# 检查服务状态
if check_datakit_status; then
    echo "Datakit服务正在运行"
fi

# 启动服务
start_datakit

# 重启服务
restart_datakit
```

