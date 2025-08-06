#!/usr/bin/env python3
"""
测试IP地址选择逻辑的脚本
"""

import boto3
import os

def test_ip_selection():
    """测试IP地址选择逻辑"""
    
    # 设置AWS凭证（使用环境变量或配置文件中的值）
    access_key = os.environ.get('AWS_ACCESS_KEY_ID', 'AWS_ACCESS_KEY_ID_PLACEHOLDER')
    secret_key = os.environ.get('AWS_SECRET_ACCESS_KEY', 'AWS_SECRET_ACCESS_KEY_PLACEHOLDER')
    region = os.environ.get('AWS_DEFAULT_REGION', 'ap-southeast-1')
    
    print("=== AWS IP地址选择测试 ===")
    print(f"Access Key: {access_key}")
    print(f"Region: {region}")
    print()
    
    try:
        # 创建EC2客户端
        ec2_client = boto3.client(
            'ec2',
            region_name=region,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key
        )
        
        # 获取所有实例
        response = ec2_client.describe_instances()
        
        print("实例IP地址信息:")
        print("-" * 80)
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                state = instance['State']['Name']
                private_ip = instance.get('PrivateIpAddress', '无')
                public_ip = instance.get('PublicIpAddress', '无')
                
                # 使用与主脚本相同的逻辑
                selected_ip = private_ip if private_ip != '无' else public_ip
                
                print(f"实例ID: {instance_id}")
                print(f"状态: {state}")
                print(f"私有IP: {private_ip}")
                print(f"公有IP: {public_ip}")
                print(f"选择的IP: {selected_ip}")
                print("-" * 40)
        
    except Exception as e:
        print(f"测试失败: {e}")

if __name__ == "__main__":
    test_ip_selection() 