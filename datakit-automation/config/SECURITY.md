# Datakit 配置安全指南

## 概述

本文档详细说明了如何使用 Datakit 配置系统的加解密功能来保护敏感配置信息，如 S3 访问密钥、数据库密码等。

## 🔐 安全架构

### 加密方案
- **加密算法**: AES-256-GCM（推荐）、AES-256-CBC、ChaCha20-Poly1305
- **密钥管理**: 文件存储 + 环境变量支持
- **加密格式**: Base64、Hex、Raw
- **IV生成**: 随机生成，每次加密都不同

### 文件结构
```
config/
├── tools/
│   └── encrypt_config.sh      # 加密工具（独立脚本）
├── core/
│   └── decrypt.sh             # 解密模块（集成到项目）
├── env/
│   ├── example.sh             # 明文配置文件
│   └── example.encrypted      # 加密配置文件示例
└── loader.sh                  # 配置加载器（自动解密）
```

## 🚀 快速开始

### 1. 生成加密密钥

```bash
# 使用默认位置 (~/.datakit_encryption_key)
./config/tools/encrypt_config.sh generate-key

# 使用自定义位置
./config/tools/encrypt_config.sh -k /path/to/my_key generate-key
```

### 2. 加密敏感配置

```bash
# 加密环境配置文件
./config/tools/encrypt_config.sh encrypt config/env/example.sh

# 使用自定义算法和格式
./config/tools/encrypt_config.sh -a aes-256-cbc -f hex encrypt config/env/example.sh
```

### 3. 在项目中使用

```bash
# 配置加载器会自动解密敏感配置
source ./config/loader.sh

# 或者指定环境
source ./config/loader.sh production
```

## 📖 详细使用说明

### 加密工具 (encrypt_config.sh)

#### 基本操作

```bash
# 生成密钥
./config/tools/encrypt_config.sh generate-key

# 加密文件
./config/tools/encrypt_config.sh encrypt <文件>

# 解密文件
./config/tools/encrypt_config.sh decrypt <文件>

# 轮换密钥
./config/tools/encrypt_config.sh rotate-key
```

#### 高级选项

```bash
# 指定密钥文件
./config/tools/encrypt_config.sh -k /path/to/key encrypt <文件>

# 选择加密算法
./config/tools/encrypt_config.sh -a aes-256-cbc encrypt <文件>

# 选择输出格式
./config/tools/encrypt_config.sh -f hex encrypt <文件>

# 详细输出
./config/tools/encrypt_config.sh -v encrypt <文件>
```

#### 支持的算法

| 算法 | 安全性 | 性能 | 推荐度 |
|------|--------|------|--------|
| AES-256-GCM | 最高 | 中等 | ⭐⭐⭐⭐⭐ |
| AES-256-CBC | 高 | 高 | ⭐⭐⭐⭐ |
| ChaCha20-Poly1305 | 高 | 高 | ⭐⭐⭐⭐ |

#### 支持的格式

| 格式 | 可读性 | 大小 | 用途 |
|------|--------|------|------|
| Base64 | 中等 | 中等 | 推荐，通用 |
| Hex | 高 | 大 | 调试，可读性要求高 |
| Raw | 无 | 小 | 性能要求高 |

### 解密模块 (decrypt.sh)

#### 自动解密

解密模块集成在配置加载器中，会在加载配置前自动执行：

```bash
# 自动解密流程
1. 加载解密模块
2. 扫描配置目录
3. 识别加密文件
4. 使用密钥解密
5. 替换原文件
6. 清理临时文件
```

#### 手动解密

```bash
# 解密单个文件
./config/core/decrypt.sh <配置目录> [密钥文件] [是否清理]

# 示例
./config/core/decrypt.sh ./config
./config/core/decrypt.sh ./config ~/.my_key
./config/core/decrypt.sh ./config ~/.my_key false
```

## 🔑 密钥管理

### 密钥存储位置

```bash
# 默认位置
~/.datakit_encryption_key

# 自定义位置
export ENCRYPTION_KEY_FILE="/path/to/my_key"

# 环境变量（不推荐用于生产）
export DATAKIT_ENCRYPTION_KEY="your_key_here"
```

### 密钥安全建议

1. **权限控制**: 密钥文件权限设置为 600
2. **存储位置**: 避免存储在版本控制系统中
3. **备份策略**: 安全备份密钥文件
4. **定期轮换**: 定期更换加密密钥
5. **访问控制**: 限制密钥文件的访问权限

### 密钥轮换流程

```bash
# 1. 生成新密钥
./config/tools/encrypt_config.sh rotate-key

# 2. 使用新密钥重新加密所有配置文件
./config/tools/encrypt_config.sh -k ~/.datakit_encryption_key.new encrypt config/env/example.sh

# 3. 替换旧密钥文件
mv ~/.datakit_encryption_key ~/.datakit_encryption_key.old
mv ~/.datakit_encryption_key.new ~/.datakit_encryption_key

# 4. 验证新配置
./config/loader.sh
```

## 📝 配置文件示例

### 明文配置文件 (example.sh)

```bash
#!/bin/bash

# 环境配置
ENV_NAME="example"
S3_REGION="ap-southeast-1"
S3_BUCKET="my-bucket"
S3_ACCESS_KEY="AWS_ACCESS_KEY_ID_PLACEHOLDER"
S3_SECRET_KEY="AWS_SECRET_ACCESS_KEY_PLACEHOLDER"
```

### 加密配置文件 (example.encrypted)

```bash
# Datakit 加密配置文件
# 算法: aes-256-gcm
# IV: 1234567890abcdef1234567890abcdef
# 创建时间: 2024-01-01 12:00:00 UTC
# 警告: 此文件包含加密数据，请勿手动编辑

U2FsdGVkX1+Q7Z8iBzQn9K8L2M4N6P8R0T2V4X6Z8A1C3E5G7I9K1M3O5Q7S9U1W3Y5
```

## 🛡️ 安全最佳实践

### 1. 配置分类

| 配置类型 | 加密建议 | 示例 |
|----------|----------|------|
| 敏感信息 | 必须加密 | API密钥、密码、访问令牌 |
| 环境标识 | 可选加密 | 环境名称、区域设置 |
| 公共配置 | 无需加密 | 版本号、路径配置 |

### 2. 加密策略

```bash
# 必须加密的配置
S3_SECRET_KEY
DATABASE_PASSWORD
API_TOKEN
PRIVATE_KEY

# 建议加密的配置
S3_ACCESS_KEY
OPS_ADDR
DATAWAY_URL

# 无需加密的配置
DATAKIT_VERSION
LOG_LEVEL
BACKUP_RETENTION_DAYS
```

### 3. 部署安全

```bash
# 生产环境
- 使用强随机密钥
- 密钥文件存储在安全位置
- 定期轮换密钥
- 监控密钥访问

# 开发环境
- 可以使用环境变量
- 密钥文件权限控制
- 避免提交到版本控制
```

## 🚨 故障排除

### 常见问题

#### 1. 加密失败

```bash
# 检查依赖
openssl version
base64 --version

# 检查密钥文件
ls -la ~/.datakit_encryption_key

# 检查文件权限
chmod 600 ~/.datakit_encryption_key
```

#### 2. 解密失败

```bash
# 检查密钥是否正确
cat ~/.datakit_encryption_key

# 检查加密文件完整性
head -10 config/env/example.encrypted

# 检查环境变量
echo $DATAKIT_ENCRYPTION_KEY
```

#### 3. 配置加载失败

```bash
# 检查解密模块
ls -la config/core/decrypt.sh

# 检查配置加载器
./config/loader.sh --help

# 查看详细日志
./config/loader.sh 2>&1 | grep -i decrypt
```

### 调试模式

```bash
# 启用详细输出
./config/tools/encrypt_config.sh -v encrypt <文件>

# 检查加密状态
./config/loader.sh
# 会显示加密状态信息
```

## 📚 相关文档

- [配置文件架构](README.md) - 整体配置架构说明
- [配置加载器](loader.sh) - 配置加载流程
- [状态管理](base/state_config.sh) - 运行时状态管理

## 🔄 版本历史

- **v1.0.0**: 初始版本，支持基本的加解密功能
- **v1.1.0**: 添加密钥轮换和多种加密算法支持
- **v1.2.0**: 集成到配置加载器，支持自动解密

## 📞 支持

如果您在使用过程中遇到问题，请：

1. 查看本文档的故障排除部分
2. 检查系统依赖是否完整
3. 验证密钥文件配置是否正确
4. 查看详细的错误日志信息 