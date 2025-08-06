#!/usr/bin/env python3
"""
AWS资源配置文件示例
"""

# AWS凭证配置
AWS_CONFIG = {
    # Access Key ID
    'access_key_id': 'AWS_ACCESS_KEY_ID_PLACEHOLDER',
    
    # Secret Access Key
    'secret_access_key': 'AWS_SECRET_ACCESS_KEY_PLACEHOLDER',
    
    # AWS区域
    'region_name': 'ap-east-1',
    
    # AWS服务端点（可选，用于私有云或特殊环境）
    'endpoint_url': None,  # 例如: 'https://s3.ap-southeast-1.amazonaws.com'
}

# 环境变量配置示例
ENV_VARS = {
    'AWS_ACCESS_KEY_ID': 'AWS_ACCESS_KEY_ID_PLACEHOLDER',
    'AWS_SECRET_ACCESS_KEY': 'AWS_SECRET_ACCESS_KEY_PLACEHOLDER',
    'AWS_DEFAULT_REGION': 'ap-east-1',
}

# 使用说明
USAGE_EXAMPLES = """
使用方法示例：

1. 使用命令行参数：
   python aws_resource_check.py 172.31.16.4 172.31.16.5 \\
       --access-key AWS_ACCESS_KEY_ID_PLACEHOLDER \\
       --secret-key AWS_SECRET_ACCESS_KEY_PLACEHOLDER \\
       --region ap-east-1

2. 使用环境变量：
   export AWS_ACCESS_KEY_ID=AWS_ACCESS_KEY_ID_PLACEHOLDER
   export AWS_SECRET_ACCESS_KEY=AWS_SECRET_ACCESS_KEY_PLACEHOLDER
   export AWS_DEFAULT_REGION=ap-east-1
   python aws_resource_check.py 172.31.16.4 172.31.16.5

3. 使用配置文件：
   python aws_resource_check.py 172.31.16.4 172.31.16.5 \\
       --config config.py
""" 