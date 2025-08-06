#!/usr/bin/env python3
"""
性能测试脚本 - 比较单线程和多线程的性能差异
"""

import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from aws_resource_check import AWSResourceChecker

def simulate_work(work_id: int, delay: float = 0.5) -> dict:
    """模拟工作负载"""
    time.sleep(delay)  # 模拟网络请求延迟
    return {
        'work_id': work_id,
        'result': f'Work {work_id} completed',
        'timestamp': time.time()
    }

def single_thread_test(work_count: int, delay: float = 0.5) -> float:
    """单线程测试"""
    print(f"单线程测试: {work_count} 个任务")
    start_time = time.time()
    
    results = []
    for i in range(work_count):
        result = simulate_work(i, delay)
        results.append(result)
    
    end_time = time.time()
    elapsed_time = end_time - start_time
    print(f"单线程完成时间: {elapsed_time:.2f} 秒")
    return elapsed_time

def multi_thread_test(work_count: int, max_workers: int, delay: float = 0.5) -> float:
    """多线程测试"""
    print(f"多线程测试: {work_count} 个任务, {max_workers} 个线程")
    start_time = time.time()
    
    results = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # 提交所有任务
        future_to_id = {
            executor.submit(simulate_work, i, delay): i 
            for i in range(work_count)
        }
        
        # 收集结果
        for future in as_completed(future_to_id):
            result = future.result()
            results.append(result)
    
    end_time = time.time()
    elapsed_time = end_time - start_time
    print(f"多线程完成时间: {elapsed_time:.2f} 秒")
    return elapsed_time

def performance_comparison():
    """性能对比测试"""
    print("=== 多线程性能测试 ===")
    print()
    
    # 测试参数
    work_counts = [10, 20, 50]
    thread_counts = [5, 10, 20]
    delay = 0.5  # 模拟网络延迟
    
    for work_count in work_counts:
        print(f"\n--- 测试 {work_count} 个任务 ---")
        
        # 单线程测试
        single_time = single_thread_test(work_count, delay)
        
        # 多线程测试
        for thread_count in thread_counts:
            multi_time = multi_thread_test(work_count, thread_count, delay)
            speedup = single_time / multi_time
            print(f"加速比 ({thread_count} 线程): {speedup:.2f}x")
        
        print("-" * 40)

def aws_api_simulation():
    """模拟AWS API调用性能"""
    print("\n=== AWS API 调用性能模拟 ===")
    print()
    
    # 模拟不同数量的实例
    instance_counts = [5, 10, 20, 50]
    
    for count in instance_counts:
        print(f"\n--- 检查 {count} 个实例 ---")
        
        # 模拟单线程（串行）
        single_time = count * 2.0  # 假设每个实例检查需要2秒
        print(f"单线程预估时间: {single_time:.1f} 秒")
        
        # 模拟多线程（并行）
        for thread_count in [5, 10, 20]:
            # 考虑线程开销和AWS API限制
            overhead = 0.1  # 10% 的线程开销
            api_limit_factor = min(1.0, thread_count / 10)  # API限制因子
            
            multi_time = (count * 2.0 / thread_count) * (1 + overhead) / api_limit_factor
            speedup = single_time / multi_time
            print(f"{thread_count} 线程预估时间: {multi_time:.1f} 秒 (加速比: {speedup:.2f}x)")

if __name__ == "__main__":
    performance_comparison()
    aws_api_simulation()
    
    print("\n=== 性能优化建议 ===")
    print("1. 对于少量实例（<10个），单线程和多线程差异不大")
    print("2. 对于大量实例（>20个），多线程可以显著提高性能")
    print("3. 建议线程数设置为 10-20，平衡性能和API限制")
    print("4. 网络延迟越高，多线程优势越明显") 