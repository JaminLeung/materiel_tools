# AKSK参数使用说明

## 概述

`download_materials.py` 工具现在支持使用 `--aksk` 参数来简化AWS访问密钥的输入。

## 使用方法

### 基本语法

```bash
python3 download_materials.py --aksk "access_key:secret_key"
```

### 参数格式

- **格式**: `access_key:secret_key`
- **分隔符**: 使用冒号(`:`)分隔访问密钥和秘密密钥
- **示例**: `AWS_ACCESS_KEY_ID_PLACEHOLDER:AWS_SECRET_ACCESS_KEY_PLACEHOLDER`

### 使用示例

#### 1. 基本下载
```bash
# 使用AKSK参数下载物料包
python3 download_materials.py --aksk "your_access_key:your_secret_key"
```

#### 2. 指定下载目录
```bash
# 下载到指定目录
python3 download_materials.py --aksk "your_access_key:your_secret_key" --download-dir /tmp/datakit
```

#### 3. 指定版本
```bash
# 下载指定版本的物料包
python3 download_materials.py --aksk "your_access_key:your_secret_key" --datakit-version 1.78.0
```

#### 4. 仅列出文件
```bash
# 检查已下载的文件
python3 download_materials.py --aksk "your_access_key:your_secret_key" --list-only
```

#### 5. 详细输出
```bash
# 查看详细下载日志
python3 download_materials.py --aksk "your_access_key:your_secret_key" --verbose
```

#### 6. 组合使用
```bash
# 完整参数示例
python3 download_materials.py \
  --aksk "your_access_key:your_secret_key" \
  --download-dir /opt/datakit_install \
  --datakit-version 1.78.0 \
  --s3-bucket your-bucket \
  --s3-region ap-southeast-1 \
  --verbose
```

## 参数优先级

当同时使用 `--aksk` 和其他密钥参数时：

1. `--aksk` 参数会覆盖 `--s3-access-key` 和 `--s3-secret-key`
2. 如果 `--aksk` 格式错误，程序会报错并退出

## 错误处理

### 格式错误
```bash
$ python3 download_materials.py --aksk "invalid_format"
2025-08-05 11:11:17,946 - ERROR - AKSK格式错误，应为: access_key:secret_key
```

### 解析错误
```bash
$ python3 download_materials.py --aksk "key1:key2:key3"
2025-08-05 11:11:17,946 - ERROR - 解析AKSK参数失败: too many values to unpack (expected 2)
```

## 安全注意事项

1. **不要在命令行历史中留下密钥**: 使用AKSK参数时，密钥会出现在命令行历史中
2. **使用环境变量**: 建议使用环境变量来存储敏感信息
3. **定期轮换密钥**: 定期更新AWS访问密钥
4. **最小权限原则**: 确保使用的密钥具有最小必要的权限

## 环境变量替代方案

如果担心命令行历史安全问题，可以使用环境变量：

```bash
# 设置环境变量
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"

# 使用环境变量（不需要指定密钥参数）
python3 download_materials.py --list-only
```

## 兼容性

- 支持原有的 `--s3-access-key` 和 `--s3-secret-key` 参数
- 新增的 `--aksk` 参数为可选参数
- 向后兼容，不影响现有脚本 