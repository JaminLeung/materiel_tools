# TOML读取辅助函数使用说明

## 函数介绍

`read_toml_as_json` 是一个辅助函数，用于通过 `yj` 工具读取TOML文件并转换为JSON格式。

## 函数签名

```bash
read_toml_as_json <toml_file> [json_path]
```

### 参数说明

- `toml_file`: TOML文件路径（必需）
- `json_path`: JSON路径表达式（可选），用于提取特定值

## 使用示例

### 1. 读取完整JSON

```bash
# 读取整个TOML文件并转换为JSON
json_output=$(read_toml_as_json "/path/to/config.toml")
echo "$json_output"
```

### 2. 读取特定路径的值

```bash
# 读取dataway_url
dataway_url=$(read_toml_as_json "/path/to/config.toml" ".dataway.dataway_url[0]")

# 读取日志级别
log_level=$(read_toml_as_json "/path/to/config.toml" ".logging.level")

# 读取CPU限制
cpu_cores=$(read_toml_as_json "/path/to/config.toml" ".resource_limit.cpu_cores")

# 读取环境标签
env=$(read_toml_as_json "/path/to/config.toml" ".global_host_tags.env")
```

### 3. 在脚本中使用

```bash
#!/bin/bash

# 读取Datakit配置文件
datakit_conf="/usr/local/datakit/conf.d/datakit.conf"

# 检查当前配置
if current_dataway=$(read_toml_as_json "$datakit_conf" ".dataway.dataway_url[0]"); then
    echo "当前Dataway地址: $current_dataway"
else
    echo "无法读取Dataway配置"
fi

# 检查资源限制
if cpu_limit=$(read_toml_as_json "$datakit_conf" ".resource_limit.cpu_cores"); then
    echo "当前CPU限制: $cpu_limit"
else
    echo "无法读取CPU限制配置"
fi
```

## TOML文件示例

```toml
# Datakit配置文件示例
[dataway]
  dataway_url = ["https://openway.guance.com/v1/write/logging?token=test_token"]

[logging]
  level = "info"
  rotate = "32"

[resource_limit]
  cpu_cores = "1"
  mem_max_mb = "2048"

[global_host_tags]
  env = "prod"
  workspace = "test"
  global_source = "aws"
```

## JSON路径示例

| TOML路径 | JSON路径 | 说明 |
|---------|----------|------|
| `dataway.dataway_url[0]` | `.dataway.dataway_url[0]` | 数组第一个元素 |
| `logging.level` | `.logging.level` | 嵌套对象属性 |
| `resource_limit.cpu_cores` | `.resource_limit.cpu_cores` | 资源限制配置 |
| `global_host_tags.env` | `.global_host_tags.env` | 全局标签 |

## 错误处理

函数会返回以下退出码：

- `0`: 成功
- `1`: 失败（文件不存在、工具不可用、解析错误等）

### 常见错误

1. **文件不存在**
   ```
   [ERROR] TOML文件不存在: /path/to/file.toml
   ```

2. **yj工具不可用**
   ```
   [ERROR] yj工具不可用，请先安装yj
   ```

3. **jq工具不可用**（当指定JSON路径时）
   ```
   [ERROR] jq工具不可用，无法提取JSON路径
   ```

4. **JSON路径解析失败**
   ```
   [ERROR] jq解析JSON路径失败: .invalid.path
   ```

## 依赖工具

- `yj`: TOML到JSON转换工具
- `jq`: JSON处理工具（当使用JSON路径时）

## 安装依赖

```bash
# 安装yj
curl -L -o /usr/local/bin/yj https://github.com/sclevine/yj/releases/latest/download/yj-linux
chmod +x /usr/local/bin/yj

# 安装jq
# Ubuntu/Debian
apt-get update && apt-get install -y jq

# CentOS/RHEL
yum install -y jq
``` 