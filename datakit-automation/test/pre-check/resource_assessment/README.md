# AWS资源评估脚本

这个脚本用于评估AWS EC2实例的资源使用情况，判断是否满足Datakit部署需求。

## 功能特性

- 获取EC2实例近7天的平均CPU和内存使用率
- 根据实例规格和使用率计算资源需求
- 提供部署建议和风险评估
- 支持多种配置方式（命令行参数、环境变量、配置文件）
- 优先使用私有IPv4地址进行实例识别
- 多线程并行处理，提高检查速度

## 安装依赖

```bash
pip install boto3
```

## 配置方式

### 1. 检查指定IP地址

```bash
python aws_resource_check.py 172.31.16.4 172.31.16.5 \
    --access-key AWS_ACCESS_KEY_ID_PLACEHOLDER \
    --secret-key AWS_SECRET_ACCESS_KEY_PLACEHOLDER \
    --region ap-southeast-1
```

### 2. 检查所有实例

```bash
# 方法1：不指定IP参数
python aws_resource_check.py \
    --access-key AWS_ACCESS_KEY_ID_PLACEHOLDER \
    --secret-key AWS_SECRET_ACCESS_KEY_PLACEHOLDER \
    --region ap-southeast-1 \
    --threads 20

# 方法2：使用--all参数
python aws_resource_check.py --all \
    --access-key AWS_ACCESS_KEY_ID_PLACEHOLDER \
    --secret-key AWS_SECRET_ACCESS_KEY_PLACEHOLDER \
    --region ap-southeast-1 \
    --threads 20
```

### 3. 使用环境变量

```bash
export AWS_ACCESS_KEY_ID=AWS_ACCESS_KEY_ID_PLACEHOLDER
export AWS_SECRET_ACCESS_KEY=AWS_SECRET_ACCESS_KEY_PLACEHOLDER
export AWS_DEFAULT_REGION=ap-southeast-1

# 检查指定IP
python aws_resource_check.py 172.31.16.4 172.31.16.5

# 检查所有实例
python aws_resource_check.py
```

### 4. 使用配置文件

编辑 `config.py` 文件：

```python
AWS_CONFIG = {
    'access_key_id': 'AWS_ACCESS_KEY_ID_PLACEHOLDER',
    'secret_access_key': 'AWS_SECRET_ACCESS_KEY_PLACEHOLDER',
    'region_name': 'ap-southeast-1',
    'endpoint_url': None,
}
```

然后使用：

```bash
# 检查指定IP
python aws_resource_check.py 172.31.16.4 172.31.16.5 --config config.py

# 检查所有实例
python aws_resource_check.py --config config.py
```

## 参数说明

- `ips`: 要检查的IP地址列表（可选，不指定则检查所有实例）
- `--access-key`: AWS Access Key ID
- `--secret-key`: AWS Secret Access Key
- `--region`: AWS区域（默认: ap-southeast-1）
- `--endpoint`: AWS服务端点URL（可选）
- `--config`: 配置文件路径（可选）
- `--all`: 检查所有运行中的实例（与不指定IP参数效果相同）
- `--threads`: 并行线程数（默认: 10）

## 输出示例

```
=== AWS配置信息 ===
Access Key ID: AWS_ACCESS_KEY_ID_PLACEHOLDER
Secret Access Key: **********
Region: ap-southeast-1
Endpoint: 默认

开始检查 2 台主机的资源使用情况...
检查实例 i-1234567890abcdef0 (172.31.16.4)...
检查实例 i-0987654321fedcba0 (172.31.16.5)...

=== 资源评估结果 ===
{
  "172.31.16.4": {
    "instance_info": {
      "instance_id": "i-1234567890abcdef0",
      "instance_type": "t3.medium",
      "platform": "linux",
      "architecture": "x86_64"
    },
    "resource_analysis": {
      "instance_type": "t3.medium",
      "cpu_cores": 2,
      "memory_gb": 4,
      "cpu_usage_7d_avg": 25.5,
      "memory_usage_7d_avg": 30.2,
      "available_cpu": 1.49,
      "available_memory": 2.79,
      "datakit_cpu_limit": 1.2,
      "datakit_memory_limit": 1.67,
      "recommendation": "允许",
      "risk_level": "中",
      "can_deploy": true
    }
  }
}

=== 统计信息 ===
总检查主机数: 2
可部署主机数: 1
可部署主机列表: 172.31.16.4
不可部署主机数: 1
不可部署主机列表: 172.31.16.5

=== 不可部署原因分析 ===
1. 机器不符合 (CPU/内存使用率+12.5% > 90%): 0 台
2. 部分不符合安装 (机器规格 < 2C4G): 1 台
   主机列表: 172.31.16.5
3. 其他原因: 0 台

=== 判断条件说明 ===
条件1: CPU或内存使用率加12.5%后超过90%，认为机器不符合
条件2: 机器规格小于2C4G（2C4G可以安装），认为部分不符合安装
条件3: 可用资源不足（CPU < 0.5核 或 内存 < 0.5GB），认为不推荐安装
```

## 判断条件说明

脚本使用以下条件来判断主机是否适合部署Datakit：

### 条件1: 资源使用率检查
- **判断标准**: CPU或内存使用率加12.5%后超过90%
- **结果**: 机器不符合安装要求
- **原因**: 部署Datakit后可能导致资源不足

### 条件2: 机器规格检查
- **判断标准**: 机器规格小于2C4G（2C4G可以安装）
- **结果**: 部分不符合安装要求
- **原因**: 机器规格过小，可能影响稳定性

### 条件3: 可用资源检查
- **判断标准**: 可用CPU < 0.5核 或 可用内存 < 0.5GB
- **结果**: 不推荐安装
- **原因**: 可用资源不足

## 风险评估说明

- **低风险**: 推荐部署，资源充足
- **中风险**: 允许部署，需要监控资源使用
- **高风险**: 部分不符合安装，机器规格较小
- **极高风险**: 机器不符合或不推荐部署，资源不足

## 注意事项

1. 确保AWS凭证有足够的权限访问EC2和CloudWatch服务
2. 脚本需要访问CloudWatch指标数据，可能需要等待几分钟才能获取到完整的历史数据
3. 对于新创建的实例，可能无法获取到7天的历史数据
4. 建议在生产环境中使用IAM角色而不是Access Key
5. **IP地址选择**: 脚本优先使用私有IPv4地址识别实例，只有在没有私有IP时才使用公有IP地址
6. **多线程性能**: 
   - 默认使用10个线程并行处理
   - 可以根据网络带宽和AWS API限制调整线程数
   - 建议线程数不超过20，避免触发AWS API限制
   - 大量实例检查时，多线程可以显著提高处理速度 