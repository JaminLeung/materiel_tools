# Datakit 配置说明

## 📋 配置概述

Datakit 自动化安装工具支持多种配置方式，按优先级从高到低排列：

1. **环境变量** (最高优先级)
2. **配置文件** (中等优先级)
3. **默认值** (最低优先级)

## 🔧 配置方式

### 1. 环境变量配置 (推荐)

直接在命令行中设置环境变量：

```bash
export DATAKIT_VERSION=1.78.0
export S3_BUCKET=my-bucket
export S3_ACCESS_KEY=your-access-key
export S3_SECRET_KEY=your-secret-key
export DATAWAY_URL=https://dataway.example.com
export OPS_ADDR=http://ops.example.com:5000

./installer.sh existing-install
```

### 2. 配置文件

#### 生产环境配置
```bash
./installer.sh --config config/env/production.sh existing-install
```

#### 开发环境配置
```bash
./installer.sh --config config/env/development.sh existing-install
```

#### 自定义配置
```bash
# 复制示例配置
cp config/env/example.sh config/env/my-config.sh

# 编辑配置
vim config/env/my-config.sh

# 使用配置
./installer.sh --config config/env/my-config.sh existing-install
```

## 📊 配置参数详解

### 基础配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `DATAKIT_VERSION` | 必需 | `1.78.0` | Datakit版本号 |
| `LOG_LEVEL` | 可选 | `1` | 日志级别 (0-4) |
| `LOG_FILE` | 可选 | `/var/log/datakit_install.log` | 日志文件路径 |
| `DATAKIT_INSTALL_DIR` | 可选 | `/opt/datakit_install` | 安装目录 |

### S3 配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `S3_BUCKET` | 必需 | - | S3存储桶名称 |
| `S3_ACCESS_KEY` | 必需 | - | S3访问密钥 |
| `S3_SECRET_KEY` | 必需 | - | S3秘密密钥 |
| `S3_ENDPOINT` | 可选 | `https://s3.ap-southeast-1.amazonaws.com` | S3服务端点 |
| `S3_DATAKIT_DIR` | 可选 | `datakit` | S3中的Datakit目录 |

### Dataway 配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `DATAWAY_URL` | 必需 | - | Dataway服务地址 |

### 运维平台配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `OPS_ADDR` | 必需 | - | 运维平台地址 |
| `OPS_TOKEN` | 可选 | - | 运维平台令牌 |

### 生产环境配置

| 参数 | 类型 | 生产环境 | 开发环境 | 说明 |
|------|------|----------|----------|------|
| `LOCK_FILE` | 可选 | `/var/run/datakit_install.lock` | `/tmp/datakit_install.lock` | 锁文件路径 |
| `PID_FILE` | 可选 | `/var/run/datakit_install.pid` | `/tmp/datakit_install.pid` | PID文件路径 |
| `BACKUP_DIR` | 可选 | `/opt/datakit_backups` | `/tmp/datakit_backups` | 备份目录 |
| `MAX_BACKUP_COUNT` | 可选 | `5` | `3` | 最大备份数量 |
| `MAX_RETRY_ATTEMPTS` | 可选 | `3` | `2` | 最大重试次数 |
| `COMMAND_TIMEOUT` | 可选 | `300` | `60` | 命令超时时间(秒) |
| `HEALTH_CHECK_TIMEOUT` | 可选 | `60` | `30` | 健康检查超时(秒) |
| `DOWNLOAD_TIMEOUT` | 可选 | `600` | `120` | 下载超时时间(秒) |
| `INSTALL_TIMEOUT` | 可选 | `900` | `180` | 安装超时时间(秒) |

### 资源限制配置

| 参数 | 类型 | 生产环境 | 开发环境 | 说明 |
|------|------|----------|----------|------|
| `ENABLE_CGROUP` | 可选 | `true` | `false` | 是否启用CGroup限制 |
| `CPU_LIMIT_PERCENT` | 可选 | `50` | `80` | CPU限制百分比 |
| `MEMORY_LIMIT_PERCENT` | 可选 | `30` | `80` | 内存限制百分比 |

## 🔍 配置验证

### 1. 配置测试

```bash
# 测试当前配置
./config/tests/test_config.sh

# 测试指定配置文件
source config/env/production.sh && ./config/tests/test_config.sh
```

### 2. 配置查看

```bash
# 查看默认配置
./config/loader.sh --show

# 查看指定配置
./config/loader.sh --show config/env/production.sh
```

### 3. 配置验证规则

#### 必需参数验证
- `DATAKIT_VERSION`: 必须设置且格式为 x.y.z
- `S3_BUCKET`: 必须设置且不包含特殊字符
- `S3_ACCESS_KEY`: 必须设置且长度≥10
- `S3_SECRET_KEY`: 必须设置且长度≥10
- `DATAWAY_URL`: 必须设置且为有效URL
- `OPS_ADDR`: 必须设置且为有效URL

#### 格式验证
- 版本号: 必须符合 `x.y.z` 格式
- URL: 必须以 `http://` 或 `https://` 开头
- S3存储桶: 只能包含字母、数字、连字符和点号

## 📁 配置文件结构

```
config/
├── base/                    # 基础配置
│   ├── base_config.sh       # 基础配置
│   └── state_config.sh      # 状态配置
├── env/                     # 环境配置
│   ├── production.sh        # 生产环境配置
│   ├── development.sh       # 开发环境配置
│   └── example.sh           # 配置示例
├── loader.sh                # 配置加载器
└── tests/                   # 配置测试
    └── test_config.sh       # 配置验证脚本
```

## 🛠️ 配置调试

### 1. 启用调试模式

```bash
# 设置调试环境变量
export LOG_LEVEL=0
export ENABLE_DEBUG_MODE=true

# 运行安装
./installer.sh --debug existing-install
```

### 2. 详细输出

```bash
# 启用详细输出
./installer.sh --verbose existing-install
```

### 3. 配置检查

```bash
# 检查配置加载
./config/loader.sh --show config/env/production.sh

# 检查环境变量
env | grep -E "(DATAKIT|S3|DATAWAY|OPS)"
```

## 🔄 配置更新

### 1. 更新环境变量

```bash
# 更新版本
export DATAKIT_VERSION=1.79.0
./installer.sh version-upgrade
```

### 2. 更新配置文件

```bash
# 编辑配置文件
vim config/env/production.sh

# 重新加载配置
./installer.sh --config config/env/production.sh config-update
```

### 3. 配置热更新

```bash
# 仅更新配置
./installer.sh config-update
```

## 📞 配置支持

如遇到配置问题，请提供：

1. 配置文件内容 (脱敏后)
2. 环境变量列表 (脱敏后)
3. 错误日志
4. 配置测试结果 