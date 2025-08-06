#!/usr/bin/env python3
"""
AWS资源评估脚本
获取主机近7天平均CPU、内存使用率，判断是否满足Datakit部署需求
"""

import boto3
import json
import sys
import os
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from typing import List, Dict, Any

class AWSResourceChecker:
    def __init__(self, 
                 access_key_id=None, 
                 secret_access_key=None, 
                 region_name=None,
                 endpoint_url=None):
        """初始化AWS客户端"""
        # AWS凭证配置
        self.access_key_id = access_key_id or os.environ.get('AWS_ACCESS_KEY_ID')
        self.secret_access_key = secret_access_key or os.environ.get('AWS_SECRET_ACCESS_KEY')
        self.region_name = region_name or os.environ.get('AWS_DEFAULT_REGION')
        self.endpoint_url = endpoint_url
        
        # 创建AWS客户端
        self.ec2_client = boto3.client(
            'ec2', 
            region_name=self.region_name,
            aws_access_key_id=self.access_key_id,
            aws_secret_access_key=self.secret_access_key,
            endpoint_url=self.endpoint_url
        )
        
        self.cloudwatch_client = boto3.client(
            'cloudwatch', 
            region_name=self.region_name,
            aws_access_key_id=self.access_key_id,
            aws_secret_access_key=self.secret_access_key,
            endpoint_url=self.endpoint_url
        )
        
    def get_all_instances(self) -> List[str]:
        """获取所有EC2实例的IP地址"""
        try:
            response = self.ec2_client.describe_instances()
            all_ips = []
            
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    # 只获取运行中的实例
                    if instance['State']['Name'] == 'running':
                        # 优先使用私有IP地址
                        instance_ip = instance.get('PrivateIpAddress') or instance.get('PublicIpAddress')
                        if instance_ip:
                            all_ips.append(instance_ip)
            
            return all_ips
        except Exception as e:
            print(f"获取所有实例失败: {e}")
            return []
    
    def get_instance_info(self, ip_list: List[str]) -> Dict[str, Any]:
        """获取主机信息"""
        try:
            # 获取所有实例信息
            response = self.ec2_client.describe_instances()
            instances_info = {}
            
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    # 只处理运行中的实例
                    if instance['State']['Name'] != 'running':
                        continue
                        
                    # 优先使用私有IP地址
                    instance_ip = instance.get('PrivateIpAddress') or instance.get('PublicIpAddress')
                    if instance_ip and instance_ip in ip_list:
                        instances_info[instance_ip] = {
                            'instance_id': instance['InstanceId'],
                            'instance_type': instance['InstanceType'],
                            'platform': instance.get('Platform', 'linux'),
                            'architecture': instance['Architecture'],
                            'state': instance['State']['Name']
                        }
            
            return instances_info
        except Exception as e:
            print(f"获取实例信息失败: {e}")
            return {}
    
    def get_metrics(self, instance_id: str, metric_name: str, period: int = 86400) -> float:
        """获取指定实例的指标数据"""
        try:
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(days=7)
            
            response = self.cloudwatch_client.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'InstanceId',
                        'Value': instance_id
                    }
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=period,
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                # 计算7天平均值
                values = [point['Average'] for point in response['Datapoints']]
                return sum(values) / len(values)
            return 0.0
            
        except Exception as e:
            print(f"获取指标 {metric_name} 失败: {e}")
            return 0.0
    
    def calculate_resource_requirements(self, instance_type: str, cpu_usage: float, memory_usage: float) -> Dict[str, Any]:
        """计算资源需求和部署建议"""
        # 解析实例类型获取CPU和内存规格
        cpu_cores = self._parse_cpu_cores(instance_type)
        memory_gb = self._parse_memory_gb(instance_type)
        
        # 计算可用资源
        available_cpu = cpu_cores * (1 - cpu_usage / 100)
        available_memory = memory_gb * (1 - memory_usage / 100)
        
        # 判断条件1：CPU、内存使用率加12.5%是否超过90%
        cpu_usage_with_datakit = cpu_usage + 12.5
        memory_usage_with_datakit = memory_usage + 12.5
        usage_too_high = cpu_usage_with_datakit > 90 or memory_usage_with_datakit > 90
        
        # 判断条件2：机器规格是否小于2C4G
        spec_too_small = cpu_cores < 2 or memory_gb < 4
        
        # 根据规格确定Datakit资源限制
        if spec_too_small:
            # < 2C4G
            datakit_cpu = 1
            datakit_memory = 1
            recommendation = "部分不符合安装"
            risk_level = "高"
            can_deploy = False
        elif cpu_cores < 4 or memory_gb < 8:
            # 2C4G ~ 4C8G
            datakit_cpu = min(1.2, available_cpu * 0.6)
            datakit_memory = min(2.4, available_memory * 0.6)
            recommendation = "允许"
            risk_level = "中"
            can_deploy = True
        else:
            # ≥ 4C8G
            datakit_cpu = 1
            datakit_memory = 2
            recommendation = "推荐"
            risk_level = "低"
            can_deploy = True
        
        # 检查使用率条件
        if usage_too_high:
            recommendation = "机器不符合"
            risk_level = "极高"
            can_deploy = False
        
        # 检查是否满足最低要求
        if available_cpu < 0.5 or available_memory < 0.5:
            recommendation = "不推荐"
            risk_level = "极高"
            can_deploy = False
        
        return {
            'instance_type': instance_type,
            'cpu_cores': cpu_cores,
            'memory_gb': memory_gb,
            'cpu_usage_7d_avg': cpu_usage,
            'memory_usage_7d_avg': memory_usage,
            'cpu_usage_with_datakit': cpu_usage_with_datakit,
            'memory_usage_with_datakit': memory_usage_with_datakit,
            'available_cpu': available_cpu,
            'available_memory': available_memory,
            'datakit_cpu_limit': datakit_cpu,
            'datakit_memory_limit': datakit_memory,
            'recommendation': recommendation,
            'risk_level': risk_level,
            'can_deploy': can_deploy,
            'usage_too_high': usage_too_high,
            'spec_too_small': spec_too_small
        }
    
    def _parse_cpu_cores(self, instance_type: str) -> int:
        """解析实例类型获取CPU核心数"""
        # 简化解析逻辑，实际使用时需要完整的实例类型映射
        if 't2.nano' in instance_type or 't3.nano' in instance_type:
            return 1
        elif 't2.micro' in instance_type or 't3.micro' in instance_type:
            return 1
        elif 't2.small' in instance_type or 't3.small' in instance_type:
            return 1
        elif 't2.medium' in instance_type or 't3.medium' in instance_type:
            return 2
        elif 'm5.large' in instance_type:
            return 2
        elif 'm5.xlarge' in instance_type:
            return 4
        else:
            # 默认解析逻辑
            return 2
    
    def _parse_memory_gb(self, instance_type: str) -> int:
        """解析实例类型获取内存大小(GB)"""
        # 简化解析逻辑，实际使用时需要完整的实例类型映射
        if 'nano' in instance_type:
            return 1
        elif 'micro' in instance_type:
            return 1
        elif 'small' in instance_type:
            return 2
        elif 'medium' in instance_type:
            return 4
        elif 'large' in instance_type:
            return 8
        elif 'xlarge' in instance_type:
            return 16
        else:
            # 默认解析逻辑
            return 4
    
    def check_single_instance(self, ip: str, instances_info: Dict[str, Any]) -> tuple:
        """检查单个实例的资源使用情况"""
        if ip not in instances_info:
            return ip, {"error": "实例信息未找到"}
        
        instance_info = instances_info[ip]
        instance_id = instance_info['instance_id']
        
        print(f"检查实例 {instance_id} ({ip})...")
        
        try:
            # 获取CPU和内存使用率
            cpu_usage = self.get_metrics(instance_id, 'CPUUtilization')
            memory_usage = self.get_metrics(instance_id, 'MemoryUtilization')
            
            # 计算资源需求
            resource_analysis = self.calculate_resource_requirements(
                instance_info['instance_type'],
                cpu_usage,
                memory_usage
            )
            
            return ip, {
                'instance_info': instance_info,
                'resource_analysis': resource_analysis
            }
        except Exception as e:
            return ip, {"error": f"检查失败: {str(e)}"}
    
    def check_resources(self, ip_list: List[str], max_workers: int = 10) -> Dict[str, Any]:
        """主检查函数（多线程版本）"""
        print(f"开始检查 {len(ip_list)} 台主机的资源使用情况...")
        print(f"使用 {max_workers} 个线程并行处理...")
        
        # 获取实例信息
        instances_info = self.get_instance_info(ip_list)
        if not instances_info:
            return {"error": "无法获取实例信息"}
        
        results = {}
        
        # 使用线程池并行处理
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # 提交所有任务
            future_to_ip = {
                executor.submit(self.check_single_instance, ip, instances_info): ip 
                for ip in ip_list
            }
            
            # 收集结果并显示进度
            completed = 0
            total = len(ip_list)
            
            for future in as_completed(future_to_ip):
                ip, result = future.result()
                results[ip] = result
                completed += 1
                print(f"进度: {completed}/{total} ({completed/total*100:.1f}%)")
        
        return results

def main():
    """主函数"""
    import argparse
    
    # 创建命令行参数解析器
    parser = argparse.ArgumentParser(description='AWS资源评估脚本')
    parser.add_argument('ips', nargs='*', help='要检查的IP地址列表（不指定则检查所有实例）')
    parser.add_argument('--access-key', help='AWS Access Key ID')
    parser.add_argument('--secret-key', help='AWS Secret Access Key')
    parser.add_argument('--region', help='AWS区域 (默认: ap-southeast-1)')
    parser.add_argument('--endpoint', help='AWS服务端点URL')
    parser.add_argument('--config', help='配置文件路径')
    parser.add_argument('--all', action='store_true', help='检查所有运行中的实例')
    parser.add_argument('--threads', type=int, default=10, help='并行线程数 (默认: 10)')
    
    args = parser.parse_args()
    
    # 如果指定了配置文件，则加载配置
    if args.config:
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("config", args.config)
            config_module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(config_module)
            
            # 从配置文件获取配置
            aws_config = getattr(config_module, 'AWS_CONFIG', {})
            args.access_key = args.access_key or aws_config.get('access_key_id')
            args.secret_key = args.secret_key or aws_config.get('secret_access_key')
            args.region = args.region or aws_config.get('region_name')
            args.endpoint = args.endpoint or aws_config.get('endpoint_url')
            
            print(f"已加载配置文件: {args.config}")
        except Exception as e:
            print(f"加载配置文件失败: {e}")
            sys.exit(1)
    
    # 显示配置信息
    print("=== AWS配置信息 ===")
    print(f"Access Key ID: {args.access_key or os.environ.get('AWS_ACCESS_KEY_ID', '未设置')}")
    print(f"Secret Access Key: {'*' * 10 if args.secret_key or os.environ.get('AWS_SECRET_ACCESS_KEY') else '未设置'}")
    print(f"Region: {args.region or os.environ.get('AWS_DEFAULT_REGION', '未设置')}")
    print(f"Endpoint: {args.endpoint or '默认'}")
    print()
    
    # 创建检查器实例
    checker = AWSResourceChecker(
        access_key_id=args.access_key,
        secret_access_key=args.secret_key,
        region_name=args.region,
        endpoint_url=args.endpoint
    )
    
    # 确定要检查的IP列表
    if args.all or not args.ips:
        print("获取所有运行中的EC2实例...")
        ip_list = checker.get_all_instances()
        if not ip_list:
            print("未找到运行中的EC2实例")
            sys.exit(1)
        print(f"找到 {len(ip_list)} 个运行中的实例")
    else:
        ip_list = args.ips
    
    # 执行检查
    results = checker.check_resources(ip_list, max_workers=args.threads)
    
    # 输出结果
    print("\n=== 资源评估结果 ===")
    print(json.dumps(results, indent=2, ensure_ascii=False))
    
    # 统计结果
    deployable_count = 0
    usage_too_high_count = 0
    spec_too_small_count = 0
    other_reasons_count = 0
    deployable_ips = []
    usage_too_high_ips = []
    spec_too_small_ips = []
    other_reasons_ips = []
    
    for ip, result in results.items():
        if isinstance(result, dict) and 'resource_analysis' in result:
            analysis = result['resource_analysis']
            if analysis['can_deploy']:
                deployable_count += 1
                deployable_ips.append(ip)
            else:
                if analysis['usage_too_high']:
                    usage_too_high_count += 1
                    usage_too_high_ips.append(ip)
                elif analysis['spec_too_small']:
                    spec_too_small_count += 1
                    spec_too_small_ips.append(ip)
                else:
                    other_reasons_count += 1
                    other_reasons_ips.append(ip)
    
    print(f"\n=== 统计信息 ===")
    print(f"总检查主机数: {len(ip_list)}")
    print(f"可部署主机数: {deployable_count}")
    print(f"可部署主机列表: {', '.join(deployable_ips) if deployable_ips else '无'}")
    print(f"不可部署主机数: {len(ip_list) - deployable_count}")
    
    # 收集所有不可部署的主机
    non_deployable_ips = usage_too_high_ips + spec_too_small_ips + other_reasons_ips
    print(f"不可部署主机列表: {', '.join(non_deployable_ips) if non_deployable_ips else '无'}")
    print()

    print("=== 不可部署原因分析 ===")
    print(f"1. 机器不符合 (CPU/内存使用率+12.5% > 90%): {usage_too_high_count} 台")
    if usage_too_high_ips:
        print(f"   主机列表: {', '.join(usage_too_high_ips)}")
    print(f"2. 部分不符合安装 (机器规格 < 2C4G): {spec_too_small_count} 台")
    if spec_too_small_ips:
        print(f"   主机列表: {', '.join(spec_too_small_ips)}")
    print(f"3. 其他原因: {other_reasons_count} 台")
    if other_reasons_ips:
        print(f"   主机列表: {', '.join(other_reasons_ips)}")
    print()
    print("=== 判断条件说明 ===")
    print("条件1: CPU或内存使用率加12.5%后超过90%，认为机器不符合")
    print("条件2: 机器规格小于2C4G（2C4G可以安装），认为部分不符合安装")
    print("条件3: 可用资源不足（CPU < 0.5核 或 内存 < 0.5GB），认为不推荐安装")

if __name__ == "__main__":
    main() 