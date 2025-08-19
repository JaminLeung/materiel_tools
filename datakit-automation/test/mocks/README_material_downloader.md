# Datakit 物料下载器使用说明

## 功能概述

这个Python脚本用于从远程仓库拉取项目并下载Datakit物料包，支持以下功能：

- 从Git仓库克隆项目
- 从S3下载指定版本的Datakit物料包
- 自动验证文件完整性（MD5校验）
- 支持批量下载多个版本
- 列出已下载的物料

## 安装依赖

```bash
# 安装Python依赖
pip install requests pathlib

# 确保已安装AWS CLI
aws --version
```

## 配置文件

创建配置文件 `material_config.json`：

```json
{
    "git_repo": "https://github.com/your-org/datakit-automation.git",
    "git_branch": "main",
    "s3_bucket": "your-bucket",
    "s3_region": "ap-southeast-1",
    "s3_endpoint": "https://s3.ap-southeast-1.amazonaws.com",
    "s3_access_key": "your-access-key",
    "s3_secret_key": "your-secret-key",
    "datakit_versions": ["1.78.0", "1.77.0", "1.76.0"],
    "download_timeout": 300,
    "retry_count": 3
}
```

## 使用方法

### 1. 克隆远程仓库

```bash
python material_downloader.py --clone --config material_config.json
```

### 2. 下载指定版本

```bash
python material_downloader.py --version 1.78.0 --config material_config.json
```

### 3. 下载所有配置的版本

```bash
python material_downloader.py --all --config material_config.json
```

### 4. 列出已下载的物料

```bash
python material_downloader.py --list
```

### 5. 完整流程（克隆+下载）

```bash
# 克隆仓库并下载所有版本
python material_downloader.py --clone --all --config material_config.json
```

## 目录结构

下载完成后，物料将保存在 `package/` 目录中：

```
package/
├── datakit_bundle-linux-amd64-1.78.0.tar.gz
├── datakit_bundle-linux-amd64-1.78.0.tar.gz.md5
├── datakit_bundle-linux-amd64-1.77.0.tar.gz
├── datakit_bundle-linux-amd64-1.77.0.tar.gz.md5
└── ...
```

## 错误处理

- 如果下载失败，脚本会记录错误日志
- 如果MD5校验失败，会删除损坏的文件
- 支持断点续传（跳过已存在的文件）

## 注意事项

1. 确保有足够的磁盘空间
2. 确保网络连接正常
3. 确保AWS凭证配置正确
4. 建议在测试环境中先验证配置
