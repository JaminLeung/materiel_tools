#!/usr/bin/env python3
"""
测试判断逻辑的脚本
"""

from aws_resource_check import AWSResourceChecker

def test_judgment_logic():
    """测试判断逻辑"""
    
    checker = AWSResourceChecker()
    
    # 测试用例
    test_cases = [
        {
            'name': '正常规格，低使用率',
            'instance_type': 'm5.large',  # 2C8G
            'cpu_usage': 30.0,
            'memory_usage': 40.0,
            'expected': '推荐'
        },
        {
            'name': '正常规格，高使用率',
            'instance_type': 'm5.large',  # 2C8G
            'cpu_usage': 85.0,
            'memory_usage': 80.0,
            'expected': '机器不符合'
        },
        {
            'name': '小规格，低使用率',
            'instance_type': 't3.small',  # 1C2G
            'cpu_usage': 20.0,
            'memory_usage': 30.0,
            'expected': '部分不符合安装'
        },
        {
            'name': '小规格，高使用率',
            'instance_type': 't3.small',  # 1C2G
            'cpu_usage': 85.0,
            'memory_usage': 80.0,
            'expected': '机器不符合'
        },
        {
            'name': '大规格，低使用率',
            'instance_type': 'm5.xlarge',  # 4C16G
            'cpu_usage': 20.0,
            'memory_usage': 25.0,
            'expected': '推荐'
        }
    ]
    
    print("=== 判断逻辑测试 ===")
    print()
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"测试用例 {i}: {test_case['name']}")
        print(f"实例类型: {test_case['instance_type']}")
        print(f"CPU使用率: {test_case['cpu_usage']}%")
        print(f"内存使用率: {test_case['memory_usage']}%")
        
        result = checker.calculate_resource_requirements(
            test_case['instance_type'],
            test_case['cpu_usage'],
            test_case['memory_usage']
        )
        
        print(f"实际结果: {result['recommendation']}")
        print(f"预期结果: {test_case['expected']}")
        print(f"可部署: {result['can_deploy']}")
        print(f"CPU+12.5%: {result['cpu_usage_with_datakit']:.1f}%")
        print(f"内存+12.5%: {result['memory_usage_with_datakit']:.1f}%")
        print(f"规格过小: {result['spec_too_small']}")
        print(f"使用率过高: {result['usage_too_high']}")
        print("-" * 50)
        print()

if __name__ == "__main__":
    test_judgment_logic() 