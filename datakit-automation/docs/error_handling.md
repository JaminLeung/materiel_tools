# 错误处理标准化系统

## 概述

datakit-automation 项目采用标准化的错误处理系统，提供统一的错误分类、错误恢复、错误追踪和错误统计功能。

## 核心特性

### 1. 错误分类系统

系统定义了17种标准错误类型，每种错误都有唯一的错误代码：

| 错误类型 | 错误代码 | 描述 |
|---------|---------|------|
| SUCCESS | 0 | 成功 |
| GENERAL_ERROR | 1 | 一般错误 |
| CONFIG_ERROR | 2 | 配置错误 |
| NETWORK_ERROR | 3 | 网络错误 |
| PERMISSION_ERROR | 4 | 权限错误 |
| RESOURCE_ERROR | 5 | 资源错误 |
| VALIDATION_ERROR | 6 | 验证错误 |
| SERVICE_ERROR | 7 | 服务错误 |
| TIMEOUT_ERROR | 8 | 超时错误 |
| DEPENDENCY_ERROR | 9 | 依赖错误 |
| FILE_ERROR | 10 | 文件错误 |
| COMMAND_ERROR | 11 | 命令错误 |
| API_ERROR | 12 | API错误 |
| DATABASE_ERROR | 13 | 数据库错误 |
| CRYPTO_ERROR | 14 | 加密错误 |
| BACKUP_ERROR | 15 | 备份错误 |
| ROLLBACK_ERROR | 16 | 回滚错误 |
| CLEANUP_ERROR | 17 | 清理错误 |

### 2. 错误严重程度

系统定义了4个错误严重程度级别：

| 严重程度 | 级别 | 描述 |
|---------|------|------|
| CRITICAL | 1 | 致命错误，必须立即退出 |
| ERROR | 2 | 严重错误，需要处理 |
| WARNING | 3 | 警告，可以继续执行 |
| INFO | 4 | 信息，不影响执行 |

### 3. 错误上下文追踪

系统提供完整的错误上下文追踪功能：

- **错误上下文栈**：记录错误发生的完整调用链
- **上下文链**：显示从根错误到当前错误的完整路径
- **错误定位**：精确定位错误发生的位置和原因

## 使用方法

### 1. 初始化错误处理器

```bash
# 在脚本开始时初始化
source "$CORE_DIR/error_handler.sh"
init_error_handler
```

### 2. 设置错误上下文

```bash
# 设置当前操作的上下文
set_error_context "配置文件处理"
set_error_context "读取TOML文件"

# 清除上下文（在操作完成后）
clear_error_context
```

### 3. 记录错误

```bash
# 记录一般错误
record_error "FILE_ERROR" "文件不存在" "ERROR" "配置文件处理"

# 记录致命错误（会自动退出）
record_error "CONFIG_ERROR" "配置验证失败" "CRITICAL" "配置验证"
```

### 4. 处理错误

```bash
# 处理错误并尝试恢复
handle_error "NETWORK_ERROR" "网络连接失败" "ERROR" "false"

# 处理错误并退出
handle_error "PERMISSION_ERROR" "权限不足" "CRITICAL" "true"
```

### 5. 使用断言函数

```bash
# 文件存在断言
assert_file_exists "/path/to/file" "配置文件不存在"

# 目录存在断言
assert_dir_exists "/path/to/dir" "目录不存在"

# 命令存在断言
assert_command_exists "curl" "curl命令不存在"

# 权限断言
assert_root_permission "需要root权限"

# 通用断言
assert "[[ -n \$VARIABLE ]]" "变量为空"
```

### 6. 使用标准化的die函数

```bash
# 使用默认错误类型
die "操作失败"

# 指定错误类型
die "网络连接失败" "NETWORK_ERROR"

# 指定错误类型和上下文
die "权限不足" "PERMISSION_ERROR" "服务启动"
```

### 7. 错误检查

```bash
# 检查命令执行结果
if ! some_command; then
    check_error $? "命令执行失败" "COMMAND_ERROR"
fi
```

## 错误恢复机制

### 1. 自动恢复策略

系统根据错误类型自动执行相应的恢复策略：

- **网络错误**：等待后检查网络连通性
- **服务错误**：尝试重启服务
- **文件错误**：检查磁盘空间
- **权限错误**：检查用户权限
- **资源错误**：检查系统资源
- **通用错误**：等待后清理临时文件

### 2. 自定义恢复函数

```bash
# 添加自定义恢复函数
add_error_recovery_function "my_recovery_function"

# 自定义恢复函数示例
my_recovery_function() {
    local error_code="$1"
    local error_message="$2"
    
    # 执行恢复逻辑
    log_info "执行自定义恢复..."
    
    # 返回恢复结果
    return 0  # 成功
}
```

### 3. 恢复尝试限制

系统限制最大恢复尝试次数（默认3次），避免无限重试：

```bash
# 检查恢复尝试次数
if [[ ${ERROR_STATE["RECOVERY_ATTEMPTS"]} -ge ${ERROR_STATE["MAX_RECOVERY_ATTEMPTS"]} ]]; then
    log_warning "已达到最大恢复尝试次数"
fi
```

## 错误统计和监控

### 1. 获取错误统计

```bash
# 显示错误统计信息
get_error_statistics
```

输出示例：
```
=== 错误统计 ===
总错误数: 5
致命错误数: 1
恢复尝试次数: 2
最后错误代码: 3
最后错误信息: 网络连接失败
最后错误上下文: 配置文件处理
```

### 2. 重置错误状态

```bash
# 重置所有错误状态
reset_error_state
```

## 集成到现有代码

### 1. 替换现有的die函数

**旧代码：**
```bash
die() {
    log_error "$1"
    exit 1
}
```

**新代码：**
```bash
# 使用标准化的die函数（已在error_handler.sh中定义）
die "错误消息" "ERROR_TYPE" "上下文"
```

### 2. 替换直接exit调用

**旧代码：**
```bash
if [[ ! -f "$file" ]]; then
    echo "文件不存在" >&2
    exit 1
fi
```

**新代码：**
```bash
assert_file_exists "$file" "文件不存在"
```

### 3. 替换错误检查

**旧代码：**
```bash
if ! command; then
    log_error "命令执行失败"
    return 1
fi
```

**新代码：**
```bash
set_error_context "命令执行"
if ! command; then
    handle_error "COMMAND_ERROR" "命令执行失败" "ERROR" "false"
fi
clear_error_context
```

## 最佳实践

### 1. 错误上下文管理

- 在每个主要操作开始时设置错误上下文
- 在操作完成后清除错误上下文
- 使用描述性的上下文名称

```bash
set_error_context "Datakit安装"
set_error_context "下载安装包"
# ... 执行下载操作
clear_error_context
set_error_context "安装Datakit"
# ... 执行安装操作
clear_error_context
```

### 2. 错误类型选择

- 选择最准确的错误类型
- 避免使用GENERAL_ERROR，除非确实无法分类
- 为API调用使用API_ERROR
- 为网络操作使用NETWORK_ERROR

### 3. 错误严重程度

- 使用CRITICAL表示必须立即退出的错误
- 使用ERROR表示需要处理的严重错误
- 使用WARNING表示可以继续执行的警告
- 使用INFO表示不影响执行的信息

### 4. 错误恢复

- 为可恢复的错误实现恢复策略
- 限制恢复尝试次数
- 记录恢复过程和结果
- 在恢复失败时提供清晰的错误信息

### 5. 测试错误处理

使用提供的测试脚本验证错误处理功能：

```bash
# 运行错误处理测试
./test/test_error_handling.sh
```

## 故障排除

### 1. 常见问题

**问题：错误处理器未初始化**
```
解决方案：确保在脚本开始时调用 init_error_handler
```

**问题：错误上下文未清除**
```
解决方案：在操作完成后调用 clear_error_context
```

**问题：恢复函数未执行**
```
解决方案：检查恢复函数是否正确注册，使用 add_error_recovery_function
```

### 2. 调试技巧

- 启用DEBUG模式查看详细错误信息
- 使用get_error_statistics查看错误统计
- 检查错误上下文链定位问题根源
- 查看日志文件中的错误记录

## 版本历史

- **v1.0.0**：初始版本，包含基本错误处理功能
- **v1.1.0**：添加错误恢复机制
- **v1.2.0**：添加错误上下文追踪
- **v1.3.0**：添加错误统计和监控
- **v2.0.0**：标准化错误处理系统，支持17种错误类型 