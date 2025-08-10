#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Datakit物料包下载工具
功能：从S3下载Datakit安装所需的物料包
"""

import os
import sys
import argparse
import hashlib
import logging
import requests
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from typing import Optional, Tuple
import time

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DatakitMaterialDownloader:
    """Datakit物料包下载器"""
    
    def __init__(self, 
                 s3_bucket: str = "benjamin--test",
                 s3_region: str = "ap-southeast-1",
                 s3_access_key: str = "AWS_ACCESS_KEY_ID_PLACEHOLDER",
                 s3_secret_key: str = "AWS_SECRET_ACCESS_KEY_PLACEHOLDER",
                 datakit_version: str = "1.78.0",
                 s3_datakit_dir: str = "datakit"):
        """
        初始化下载器
        
        Args:
            s3_bucket: S3存储桶名称
            s3_region: S3区域
            s3_access_key: AWS访问密钥
            s3_secret_key: AWS秘密密钥
            datakit_version: Datakit版本号
            s3_datakit_dir: S3中的Datakit目录
        """
        self.s3_bucket = s3_bucket
        self.s3_region = s3_region
        self.s3_access_key = s3_access_key
        self.s3_secret_key = s3_secret_key
        self.datakit_version = datakit_version
        self.s3_datakit_dir = s3_datakit_dir
        
        # 构建文件名
        self.bundle_name = f"datakit_bundle-linux-amd64-{datakit_version}.tar.gz"
        self.md5_name = f"{self.bundle_name}.md5"
        
        # 构建S3键
        self.bundle_key = f"{s3_datakit_dir}/{self.bundle_name}"
        self.md5_key = f"{s3_datakit_dir}/{self.md5_name}"
        
        # 初始化S3客户端
        self.s3_client = None
        self._init_s3_client()
    
    def _init_s3_client(self):
        """初始化S3客户端"""
        try:
            self.s3_client = boto3.client(
                's3',
                region_name=self.s3_region,
                aws_access_key_id=self.s3_access_key,
                aws_secret_access_key=self.s3_secret_key
            )
            logger.info(f"S3客户端初始化成功，区域: {self.s3_region}")
        except Exception as e:
            logger.error(f"S3客户端初始化失败: {e}")
            self.s3_client = None
    
    def download_file(self, s3_key: str, local_path: str) -> bool:
        """
        从S3下载单个文件
        
        Args:
            s3_key: S3对象键
            local_path: 本地文件路径
            
        Returns:
            bool: 下载是否成功
        """
        if not self.s3_client:
            logger.error("S3客户端未初始化")
            return False
        
        try:
            logger.info(f"开始下载: {s3_key} -> {local_path}")
            
            # 确保目标目录存在
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            
            # 下载文件
            self.s3_client.download_file(self.s3_bucket, s3_key, local_path)
            
            # 检查文件大小
            file_size = os.path.getsize(local_path)
            if file_size == 0:
                logger.error(f"下载的文件大小为0: {local_path}")
                return False
            
            logger.info(f"下载成功: {local_path} ({file_size} bytes)")
            return True
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'NoSuchKey':
                logger.error(f"S3对象不存在: {s3_key}")
            elif error_code == 'NoSuchBucket':
                logger.error(f"S3存储桶不存在: {self.s3_bucket}")
            else:
                logger.error(f"S3下载失败: {e}")
            return False
        except Exception as e:
            logger.error(f"下载过程中发生错误: {e}")
            return False
    
    def calculate_md5(self, file_path: str) -> str:
        """
        计算文件的MD5值
        
        Args:
            file_path: 文件路径
            
        Returns:
            str: MD5哈希值
        """
        hash_md5 = hashlib.md5()
        try:
            with open(file_path, "rb") as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    hash_md5.update(chunk)
            return hash_md5.hexdigest()
        except Exception as e:
            logger.error(f"计算MD5失败: {e}")
            return ""
    
    def verify_md5(self, file_path: str, expected_md5: str) -> bool:
        """
        验证文件的MD5值
        
        Args:
            file_path: 文件路径
            expected_md5: 期望的MD5值
            
        Returns:
            bool: MD5验证是否通过
        """
        actual_md5 = self.calculate_md5(file_path)
        if not actual_md5:
            return False
        
        is_valid = actual_md5 == expected_md5
        if is_valid:
            logger.info(f"MD5验证通过: {file_path}")
        else:
            logger.error(f"MD5验证失败: {file_path}")
            logger.error(f"期望: {expected_md5}")
            logger.error(f"实际: {actual_md5}")
        
        return is_valid
    
    def download_materials(self, download_dir: str = "/opt/datakit_install") -> bool:
        """
        下载所有物料包
        
        Args:
            download_dir: 下载目录
            
        Returns:
            bool: 下载是否成功
        """
        logger.info(f"开始下载Datakit物料包到: {download_dir}")
        logger.info(f"Datakit版本: {self.datakit_version}")
        logger.info(f"S3存储桶: {self.s3_bucket}")
        logger.info(f"S3区域: {self.s3_region}")
        
        # 确保下载目录存在
        os.makedirs(download_dir, exist_ok=True)
        
        # 构建本地文件路径
        bundle_path = os.path.join(download_dir, self.bundle_name)
        md5_path = os.path.join(download_dir, self.md5_name)
        
        # 检查本地是否已存在文件且MD5正确
        if os.path.exists(bundle_path) and os.path.exists(md5_path):
            logger.info("本地已存在文件，进行MD5验证...")
            try:
                with open(md5_path, 'r') as f:
                    expected_md5 = f.read().strip()
                
                if self.verify_md5(bundle_path, expected_md5):
                    logger.info("本地文件MD5验证通过，跳过下载")
                    return True
                else:
                    logger.warning("本地文件MD5验证失败，将重新下载")
            except Exception as e:
                logger.warning(f"读取本地MD5文件失败: {e}")
        
        # 下载MD5文件
        logger.info("下载MD5文件...")
        if not self.download_file(self.md5_key, md5_path):
            logger.error("MD5文件下载失败")
            return False
        
        # 读取期望的MD5值
        try:
            with open(md5_path, 'r') as f:
                expected_md5 = f.read().strip()
            logger.info(f"期望的MD5值: {expected_md5}")
        except Exception as e:
            logger.error(f"读取MD5文件失败: {e}")
            return False
        
        # 下载bundle文件
        logger.info("下载bundle文件...")
        if not self.download_file(self.bundle_key, bundle_path):
            logger.error("bundle文件下载失败")
            return False
        
        # 验证下载文件的MD5
        logger.info("验证下载文件的MD5...")
        if not self.verify_md5(bundle_path, expected_md5):
            logger.error("bundle文件MD5验证失败")
            # 清理下载的文件
            for file_path in [bundle_path, md5_path]:
                if os.path.exists(file_path):
                    os.remove(file_path)
            return False
        
        logger.info("所有物料包下载和验证完成")
        return True
    
    def list_downloaded_files(self, download_dir: str = "/opt/datakit_install") -> None:
        """
        列出已下载的文件
        
        Args:
            download_dir: 下载目录
        """
        logger.info(f"检查下载目录: {download_dir}")
        
        if not os.path.exists(download_dir):
            logger.warning("下载目录不存在")
            return
        
        files = os.listdir(download_dir)
        if not files:
            logger.info("下载目录为空")
            return
        
        logger.info("已下载的文件:")
        for file in files:
            file_path = os.path.join(download_dir, file)
            if os.path.isfile(file_path):
                file_size = os.path.getsize(file_path)
                logger.info(f"  - {file} ({file_size} bytes)")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="下载Datakit物料包")
    parser.add_argument(
        "--download-dir", 
        default="/opt/datakit_install",
        help="下载目录 (默认: /opt/datakit_install)"
    )
    parser.add_argument(
        "--s3-bucket",
        default="benjamin--test",
        help="S3存储桶名称 (默认: benjamin--test)"
    )
    parser.add_argument(
        "--s3-region",
        default="ap-southeast-1",
        help="S3区域 (默认: ap-southeast-1)"
    )
    parser.add_argument(
        "--s3-access-key",
        help="AWS访问密钥"
    )
    parser.add_argument(
        "--s3-secret-key",
        help="AWS秘密密钥"
    )
    parser.add_argument(
        "--aksk",
        help="AKSK格式的访问密钥，格式: access_key:secret_key"
    )
    parser.add_argument(
        "--datakit-version",
        default="1.78.0",
        help="Datakit版本号 (默认: 1.78.0)"
    )
    parser.add_argument(
        "--s3-datakit-dir",
        default="datakit",
        help="S3中的Datakit目录 (默认: datakit)"
    )
    parser.add_argument(
        "--list-only",
        action="store_true",
        help="仅列出已下载的文件，不进行下载"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="详细输出"
    )
    
    args = parser.parse_args()
    
    # 设置日志级别
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # 处理AKSK参数
    s3_access_key = args.s3_access_key
    s3_secret_key = args.s3_secret_key
    
    if args.aksk:
        try:
            if ':' not in args.aksk:
                logger.error("AKSK格式错误，应为: access_key:secret_key")
                sys.exit(1)
            s3_access_key, s3_secret_key = args.aksk.split(':', 1)
            logger.info("已从AKSK参数解析访问密钥")
        except Exception as e:
            logger.error(f"解析AKSK参数失败: {e}")
            sys.exit(1)
    
    # 创建下载器
    downloader = DatakitMaterialDownloader(
        s3_bucket=args.s3_bucket,
        s3_region=args.s3_region,
        s3_access_key=s3_access_key,
        s3_secret_key=s3_secret_key,
        datakit_version=args.datakit_version,
        s3_datakit_dir=args.s3_datakit_dir
    )
    
    try:
        if args.list_only:
            # 仅列出文件
            downloader.list_downloaded_files(args.download_dir)
        else:
            # 下载物料包
            success = downloader.download_materials(args.download_dir)
            if success:
                logger.info("物料包下载完成")
                # 列出下载的文件
                downloader.list_downloaded_files(args.download_dir)
                sys.exit(0)
            else:
                logger.error("物料包下载失败")
                sys.exit(1)
    
    except KeyboardInterrupt:
        logger.info("用户中断下载")
        sys.exit(1)
    except Exception as e:
        logger.error(f"下载过程中发生错误: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main() 