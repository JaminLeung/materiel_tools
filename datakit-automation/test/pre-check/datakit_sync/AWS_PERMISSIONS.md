# AWS权限要求说明

## 概述

`datakit_sync`模块需要访问AWS S3存储服务，用于下载和上传Datakit安装包。本文档详细说明了所需的AWS权限配置。

## 所需权限

### 1. S3权限

#### 基本权限
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::guance"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::guance/datakit/*"
        }
    ]
}
```

#### 详细权限说明

| 权限 | 用途 | 资源 |
|------|------|------|
| `s3:GetBucketLocation` | 获取存储桶位置信息 | `arn:aws:s3:::guance` |
| `s3:ListBucket` | 列出存储桶内容 | `arn:aws:s3:::guance` |
| `s3:GetObject` | 下载文件 | `arn:aws:s3:::guance/datakit/*` |
| `s3:PutObject` | 上传文件 | `arn:aws:s3:::guance/datakit/*` |
| `s3:DeleteObject` | 删除文件（可选） | `arn:aws:s3:::guance/datakit/*` |

### 2. 最小权限策略

如果只需要基本的上传和下载功能，可以使用以下最小权限策略：

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

### 3. 完整权限策略（推荐）

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DatakitSyncS3Access",
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObjectVersion",
                "s3:PutObjectAcl"
            ],
            "Resource": [
                "arn:aws:s3:::guance",
                "arn:aws:s3:::guance/datakit/*"
            ]
        }
    ]
}
```

## 权限配置方法

### 方法1：IAM用户权限

1. 创建IAM用户
2. 创建访问密钥（Access Key）
3. 附加上述权限策略

```bash
# 创建IAM用户
aws iam create-user --user-name datakit-sync-user

# 创建访问密钥
aws iam create-access-key --user-name datakit-sync-user

# 创建权限策略
aws iam create-policy \
    --policy-name DatakitSyncS3Policy \
    --policy-document file://datakit-sync-policy.json

# 附加策略到用户
aws iam attach-user-policy \
    --user-name datakit-sync-user \
    --policy-arn arn:aws:iam::ACCOUNT-ID:policy/DatakitSyncS3Policy
```

### 方法2：IAM角色权限（推荐）

1. 创建IAM角色
2. 配置信任关系
3. 附加权限策略

```json
// 信任关系策略
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

### 方法3：临时凭证

使用AWS STS获取临时凭证：

```bash
# 获取临时凭证
aws sts assume-role \
    --role-arn arn:aws:iam::ACCOUNT-ID:role/DatakitSyncRole \
    --role-session-name DatakitSyncSession
```

## 安全最佳实践

### 1. 最小权限原则
- 只授予必要的权限
- 定期审查和更新权限
- 使用条件限制访问

### 2. 访问控制
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
            "Resource": "arn:aws:s3:::guance/datakit/*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestTag/Environment": "production"
                },
                "IpAddress": {
                    "aws:SourceIp": "192.168.1.0/24"
                }
            }
        }
    ]
}
```

### 3. 加密要求
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::guance/datakit/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                }
            }
        }
    ]
}
```

## 故障排查

### 常见权限错误

1. **Access Denied**
   - 检查IAM用户/角色权限
   - 验证存储桶名称和路径
   - 确认访问密钥有效

2. **NoSuchBucket**
   - 检查存储桶是否存在
   - 验证存储桶名称拼写
   - 确认区域设置正确

3. **InvalidAccessKeyId**
   - 检查访问密钥格式
   - 验证密钥是否有效
   - 确认密钥未过期

### 调试命令

```bash
# 测试S3访问
aws s3 ls s3://guance/datakit/ --endpoint-url https://your-s3-endpoint.com

# 检查权限
aws iam get-user
aws iam list-attached-user-policies --user-name datakit-sync-user

# 验证凭证
aws sts get-caller-identity
```

## 环境变量配置

```bash
# 设置环境变量
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=us-east-1
export S3_ENDPOINT=https://your-s3-endpoint.com
```

## 注意事项

1. **存储桶名称**：确保存储桶名称与代码中的`bucket_name`一致
2. **路径权限**：确保对`datakit/`目录有读写权限
3. **网络访问**：确保能够访问S3端点
4. **凭证安全**：不要在代码中硬编码访问密钥
5. **权限审计**：定期审查和更新权限策略 