# Datakit物料同步脚本

## 功能说明

本脚本用于与AWS S3存储服务交互，下载和上传Datakit安装所需的物料文件，支持离线安装包的同步管理。

## 主要功能

1. **AWS S3交互**：封装了与S3服务器交互的核心操作
2. **离线安装包下载**：从官方源下载Datakit相关文件
3. **文件上传管理**：将下载的文件上传到S3存储
4. **MD5校验**：自动计算和保存文件MD5值
5. **配置文件生成**：创建包配置文件记录元数据

## 支持的文件类型

### 核心安装文件
- `installer-{os_type}-{orch}-{version}` - 安装器
- `datakit-{os_type}-{orch}-{version}.tar.gz` - Datakit主程序
- `datakit_lite-{os_type}-{orch}-{version}.tar.gz` - Datakit Lite版本
- `datakit-apm-inject-{os_type}-{orch}-{version}.tar.gz` - APM注入器
- `dk_upgrader-{os_type}-{orch}.tar.gz` - 升级器

### 数据文件
- `data.tar.gz` - 数据文件包

### 工具文件
- `node_exporter-1.8.2.linux-amd64.tar.gz` - Node Exporter
- `jq` - JSON处理工具
- `yj` - YAML处理工具

## 使用方法

### 基本用法

```bash
# 安装依赖
pip install boto3 requests

# 完整同步（下载后上传）
python datakit_sync.py \
    --endpoint https://your-s3-endpoint.com \
    --access-key YOUR_ACCESS_KEY \
    --secret-key YOUR_SECRET_KEY \
    --version 1.82.0

# 仅下载
python datakit_sync.py \
    --endpoint https://your-s3-endpoint.com \
    --access-key YOUR_ACCESS_KEY \
    --secret-key YOUR_SECRET_KEY \
    --only-download

# 仅上传
python datakit_sync.py \
    --endpoint https://your-s3-endpoint.com \
    --access-key YOUR_ACCESS_KEY \
    --secret-key YOUR_SECRET_KEY \
    --only-upload

# 仅上传安装脚本
python datakit_sync.py \
    --endpoint https://your-s3-endpoint.com \
    --access-key YOUR_ACCESS_KEY \
    --secret-key YOUR_SECRET_KEY \
    --only-upload-install-sh
```

### 参数说明

- `--endpoint`: S3 endpoint URL（必需）
- `--access-key`: 访问密钥（必需）
- `--secret-key`: 秘密密钥（必需）
- `--secure`: 使用HTTPS（默认：true）
- `--only-upload`: 仅上传模式
- `--only-download`: 仅下载模式
- `--only-upload-install-sh`: 仅上传安装脚本
- `--version`: Datakit版本（默认：1.82.0）

## 文件结构

```
datakit-offline/
├── installer-linux-amd64-1.82.0
├── installer-linux-amd64-1.82.0.md5
├── datakit-linux-amd64-1.82.0.tar.gz
├── datakit-linux-amd64-1.82.0.tar.gz.md5
├── datakit_lite-linux-amd64-1.82.0.tar.gz
├── datakit_lite-linux-amd64-1.82.0.tar.gz.md5
├── datakit-apm-inject-linux-amd64-1.82.0.tar.gz
├── datakit-apm-inject-linux-amd64-1.82.0.tar.gz.md5
├── dk_upgrader-linux-amd64.tar.gz
├── dk_upgrader-linux-amd64.tar.gz.md5
├── data.tar.gz
├── data.tar.gz.md5
├── node_exporter-1.8.2.linux-amd64.tar.gz
├── node_exporter-1.8.2.linux-amd64.tar.gz.md5
├── jq
├── jq.md5
├── yj
├── yj.md5
├── install.sh
└── package_config.json
```

## S3存储结构

```
guance/
└── datakit/
    ├── installer-linux-amd64-1.82.0
    ├── installer-linux-amd64-1.82.0.md5
    ├── datakit-linux-amd64-1.82.0.tar.gz
    ├── datakit-linux-amd64-1.82.0.tar.gz.md5
    ├── datakit_lite-linux-amd64-1.82.0.tar.gz
    ├── datakit_lite-linux-amd64-1.82.0.tar.gz.md5
    ├── datakit-apm-inject-linux-amd64-1.82.0.tar.gz
    ├── datakit-apm-inject-linux-amd64-1.82.0.tar.gz.md5
    ├── dk_upgrader-linux-amd64.tar.gz
    ├── dk_upgrader-linux-amd64.tar.gz.md5
    ├── data.tar.gz
    ├── data.tar.gz.md5
    ├── node_exporter-1.8.2.linux-amd64.tar.gz
    ├── node_exporter-1.8.2.linux-amd64.tar.gz.md5
    ├── jq
    ├── jq.md5
    ├── yj
    ├── yj.md5
    └── install.sh
```

## 配置文件格式

生成的`package_config.json`文件包含以下信息：

```json
{
  "version": "1.82.0",
  "os_type": "linux",
  "architecture": "amd64",
  "files": {
    "installer": {
      "local_path": "./datakit-offline/installer-linux-amd64-1.82.0",
      "size": 1234567,
      "md5": "abcdef1234567890",
      "s3_key": "datakit/installer-linux-amd64-1.82.0"
    }
  },
  "metadata": {
    "created_at": "2024-01-01 12:00:00",
    "total_files": 9
  }
}
```

## 错误处理

脚本包含完善的错误处理机制：
- S3连接验证
- 文件下载失败重试
- MD5校验失败处理
- 网络超时处理
- 权限验证

## AWS权限要求

详细的AWS权限配置请参考 [AWS_PERMISSIONS.md](AWS_PERMISSIONS.md) 文档。

### 最小权限要求
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::guance/datakit/*"
        }
    ]
}
```

## 测试

### 运行测试
```bash
# 运行所有测试
chmod +x run_tests.sh
./run_tests.sh

# 运行特定测试
./run_tests.sh --unit        # 单元测试
./run_tests.sh --pytest      # pytest测试
./run_tests.sh --coverage    # 覆盖率报告
./run_tests.sh --performance # 性能测试
```

### 测试覆盖率
- 目标覆盖率：80%以上
- 生成HTML报告：`htmlcov/index.html`
- 支持多种测试框架：unittest、pytest

### 测试类型
- **单元测试**：测试各个方法的功能
- **集成测试**：测试完整的工作流程
- **性能测试**：测试下载和上传性能
- **Mock测试**：模拟外部依赖

## 注意事项

1. **网络要求**：需要能够访问Guance官方源和S3存储
2. **存储空间**：确保有足够的本地存储空间
3. **权限要求**：需要S3的读写权限
4. **版本管理**：支持指定Datakit版本进行同步
5. **断点续传**：支持重新运行跳过已下载的文件
6. **测试环境**：建议在虚拟环境中运行测试 

---

## 1. 主要实现思路

1. **下载所有物料**到本地目录（如 `./datakit-offline`）。
2. **打包**：将所有下载的物料文件（不含旧的 tar 包和 md5）打包成一个 tar.gz（如 `datakit_bundle-linux-amd64-1.82.0.tar.gz`）。
3. **计算 md5**：对 tar.gz 包计算 md5，生成同名 `.md5` 文件。
4. **上传**：只上传 tar.gz 和 md5 文件到 S3。
5. **不再分文件上传**。

---

## 2. 代码修改建议

### 新增/修改方法

#### 1. 打包方法

```python
import tarfile

def make_bundle_tar(self, files: dict, bundle_name: str) -> str:
    tar_path = os.path.join(self.local_dir, bundle_name)
    with tarfile.open(tar_path, "w:gz") as tar:
        for f in files.values():
            tar.add(f, arcname=os.path.basename(f))
    return tar_path
```

#### 2. 主流程调整

- 下载后，调用 `make_bundle_tar` 打包。
- 计算 md5，生成 md5 文件。
- 上传 tar.gz 和 md5 到 S3。

#### 3. 上传方法

```python
def upload_bundle(self, tar_path: str, md5_path: str, s3_key: str):
    self.upload_file(tar_path, s3_key)
    self.upload_file(md5_path, s3_key + ".md5")
```

#### 4. 主流程伪代码

```python
downloaded_files = self.download_all_packages()
bundle_name = f"datakit_bundle-{self.os_type}-{self.orch}-{self.version}.tar.gz"
tar_path = self.make_bundle_tar(downloaded_files, bundle_name)
md5_path = tar_path + ".md5"
with open(md5_path, "w") as f:
    f.write(self.calculate_md5(tar_path))
s3_key = f"{self.datakit_dir}/{bundle_name}"
self.upload_bundle(tar_path, md5_path, s3_key)
```

---

## 3. 伪代码集成示例

你可以在 datakit_sync.py 里增加如下方法和主流程：

```python
import tarfile

def make_bundle_tar(self, files: dict, bundle_name: str) -> str:
    tar_path = os.path.join(self.local_dir, bundle_name)
    with tarfile.open(tar_path, "w:gz") as tar:
        for f in files.values():
            tar.add(f, arcname=os.path.basename(f))
    return tar_path

def upload_bundle(self, tar_path: str, md5_path: str, s3_key: str):
    print(f"上传打包文件: {tar_path} -> {s3_key}")
    self.upload_file(tar_path, s3_key)
    print(f"上传MD5文件: {md5_path} -> {s3_key}.md5")
    self.upload_file(md5_path, s3_key + ".md5")

def bundle_and_upload(self, downloaded_files: dict):
    bundle_name = f"datakit_bundle-{self.os_type}-{self.orch}-{self.version}.tar.gz"
    tar_path = self.make_bundle_tar(downloaded_files, bundle_name)
    md5_path = tar_path + ".md5"
    with open(md5_path, "w") as f:
        f.write(self.calculate_md5(tar_path))
    s3_key = f"{self.datakit_dir}/{bundle_name}"
    self.upload_bundle(tar_path, md5_path, s3_key)
```

在主流程里调用：

```python
<code_block_to_apply_changes_from>
```

---

## 4. 其他注意事项

- **打包时不要包含旧的 tar.gz 和 md5 文件**，只打包原始物料。
- S3 路径和桶名可通过参数或配置指定。
- 上传后可在 S3 控制台看到只有 bundle 和 md5 文件。

---

## 5. 如需完整代码替换，请告知你的 datakit_sync.py 结构（或让我直接补全/替换相关方法）。

你也可以指定 bundle 文件名格式或 S3 路径规则，我会帮你补全！ 