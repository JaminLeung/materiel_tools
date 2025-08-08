## 概述

datakit-automation 项目采用标准化的错误处理系统，提供统一的错误分类、错误恢复、错误追踪和错误统计功能。该系统兼容旧版本 bash，使用普通数组替代关联数组以提高兼容性。

## 核心特性

### 1. 错误分类系统

系统定义了18种标准错误类型，每种错误都有唯一的错误代码：

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


## 核心函数

实际开发中最常用的3个核心函数：

### record_error - 错误记录函数

**用途：** 记录错误信息到日志，不退出程序

**语法：**
```bash
record_error "错误代码" "错误消息" "严重程度"
```

**参数说明：**
- `错误代码` - 18种标准错误类型之一（如 NETWORK_ERROR、FILE_ERROR）
- `错误消息` - 具体的错误描述
- `严重程度` - ERROR（默认）、WARNING、INFO、CRITICAL

**使用场景：**
- 记录操作过程中的错误信息
- 配合其他函数使用
- 记录警告和信息性消息

**示例：**
```bash
# 记录网络错误
record_error "NETWORK_ERROR" "无法连接到API服务器" "ERROR"

# 记录警告信息
record_error "CONFIG_ERROR" "使用默认配置文件" "WARNING"

# 记录信息性消息
record_error "INFO" "配置加载完成" "INFO"
```

### handle_error - 错误处理函数

**用途：** 处理错误并决定是否退出程序

**语法：**
```bash
handle_error "错误代码" "错误消息" "严重程度" "是否退出程序"
```

**参数说明：**
- `错误代码` - 18种标准错误类型之一
- `错误消息` - 具体的错误描述
- `严重程度` - ERROR（默认）、WARNING、INFO、CRITICAL
- `是否退出程序` - "true"（退出程序）或 "false"（只退出函数，默认）

**重要说明：**
- `CRITICAL` 严重程度会立即退出程序，无论 `是否退出程序` 参数如何设置
- `WARNING` 和 `INFO` 严重程度不会退出程序，返回成功状态码（0）

**使用场景：**
- 处理可恢复的错误（不退出程序）
- 处理致命错误（退出程序）
- 条件判断中的错误处理

**示例：**
```bash
# 处理错误但不退出程序（推荐）
if [[ ! -f "$config_file" ]]; then
    handle_error "FILE_ERROR" "配置文件不存在: $config_file" "ERROR" "false"
    return 1  # 退出当前函数
fi

# 处理错误并退出程序
if [[ $EUID -ne 0 ]]; then
    handle_error "PERMISSION_ERROR" "需要root权限" "CRITICAL" "true"
    # 程序会在这里终止
fi

# 处理警告（不退出程序）
handle_error "CONFIG_ERROR" "使用默认配置" "WARNING" "false"
# 继续执行后续代码

# CRITICAL 会自动退出程序
handle_error "NETWORK_ERROR" "网络连接失败" "CRITICAL" "false"
# 程序会立即退出，不会执行到这里
```

### check_error - 命令结果检查函数

**用途：** 检查命令执行结果，失败时记录错误

**语法：**
```bash
check_error $? "错误消息" "错误代码"
```

**参数说明：**
- `$?` - 上一个命令的退出码
- `错误消息` - 命令失败时的描述
- `错误代码` - 18种标准错误类型之一（可选，默认 COMMAND_ERROR）

**使用场景：**
- 检查命令执行是否成功
- 检查文件操作结果
- 检查网络请求结果

**说明**
- 总是使用 "ERROR" 严重程度
- 总是使用 "false" 作为退出参数（不退出程序）
- 不中断程序：只记录错误，不退出程序

**示例：**
```bash
# 检查命令执行结果
curl -s "$url" > "$output_file"
check_error $? "下载文件失败" "NETWORK_ERROR"

# 检查文件操作
cp "$source" "$target"
check_error $? "文件复制失败" "FILE_ERROR"

# 检查服务状态
systemctl is-active datakit
check_error $? "Datakit服务未运行" "SERVICE_ERROR"

# 使用默认错误类型
some_command
check_error $? "命令执行失败"  # 默认使用 COMMAND_ERROR
```
