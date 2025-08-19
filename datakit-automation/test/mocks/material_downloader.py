#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Datakit 物料下载器
功能：从远程仓库拉取项目并下载Datakit物料包
"""

import os
import sys
import json
import shutil
import hashlib
import argparse
import subprocess
from pathlib import Path
import logging

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class MaterialDownloader:
    def __init__(self, config_file=None):
        self.config = self._load_config(config_file)
        self.project_root = Path(__file__).parent.parent.parent
        self.package_dir = self.project_root / "package"
        self.package_dir.mkdir(exist_ok=True)
        
        logger.info(f"项目根目录: {self.project_root}")
        logger.info(f"物料包目录: {self.package_dir}")
    
    def _load_config(self, config_file=None):
        default_config = {
            "git_repo": "https://github.com/your-org/datakit-automation.git",
            "git_branch": "main",
            "s3_bucket": "your-bucket",
            "s3_region": "ap-southeast-1",
            "datakit_versions": ["1.78.0", "1.77.0"]
        }
        
        if config_file and os.path.exists(config_file):
            try:
                with open(config_file, 'r', encoding='utf-8') as f:
                    user_config = json.load(f)
                default_config.update(user_config)
            except Exception as e:
                logger.warning(f"加载配置文件失败: {e}")
        
        return default_config
    
    def clone_repository(self):
        try:
            repo_url = self.config["git_repo"]
            branch = self.config["git_branch"]
            
            logger.info(f"克隆仓库: {repo_url}")
            
            cmd = ["git", "clone", "--branch", branch, "--depth", "1", repo_url, str(self.project_root)]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("仓库克隆成功")
                return True
            else:
                logger.error(f"仓库克隆失败: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"克隆仓库时发生错误: {e}")
            return False
    
    def download_datakit_materials(self, version):
        try:
            logger.info(f"开始下载Datakit版本: {version}")
            
            bundle_name = f"datakit_bundle-linux-amd64-{version}.tar.gz"
            md5_name = f"datakit_bundle-linux-amd64-{version}.tar.gz.md5"
            
            s3_prefix = f"datakit/{version}/"
            bundle_key = s3_prefix + bundle_name
            md5_key = s3_prefix + md5_name
            
            # 下载MD5文件
            md5_file = self.package_dir / md5_name
            if not self._download_from_s3(md5_key, md5_file):
                return False
            
            # 读取期望的MD5值
            with open(md5_file, 'r') as f:
                expected_md5 = f.read().strip()
            
            # 下载bundle文件
            bundle_file = self.package_dir / bundle_name
            if not self._download_from_s3(bundle_key, bundle_file):
                return False
            
            # 验证MD5
            if not self._verify_md5(bundle_file, expected_md5):
                logger.error(f"MD5校验失败: {bundle_name}")
                return False
            
            logger.info(f"Datakit物料下载成功: {bundle_name}")
            return True
            
        except Exception as e:
            logger.error(f"下载Datakit物料时发生错误: {e}")
            return False
    
    def _download_from_s3(self, key, local_path):
        try:
            cmd = [
                "aws", "s3", "cp",
                f"s3://{self.config['s3_bucket']}/{key}",
                str(local_path),
                "--region", self.config["s3_region"]
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"文件下载成功: {local_path}")
                return True
            else:
                logger.error(f"文件下载失败: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"从S3下载文件时发生错误: {e}")
            return False
    
    def _verify_md5(self, file_path, expected_md5):
        try:
            with open(file_path, 'rb') as f:
                file_md5 = hashlib.md5(f.read()).hexdigest()
            return file_md5 == expected_md5
        except Exception as e:
            logger.error(f"验证MD5时发生错误: {e}")
            return False
    
    def download_all_versions(self):
        success_count = 0
        total_count = len(self.config["datakit_versions"])
        
        logger.info(f"开始下载 {total_count} 个版本的Datakit物料")
        
        for version in self.config["datakit_versions"]:
            if self.download_datakit_materials(version):
                success_count += 1
            else:
                logger.error(f"版本 {version} 下载失败")
        
        logger.info(f"下载完成: {success_count}/{total_count} 个版本成功")
        return success_count == total_count
    
    def list_downloaded_materials(self):
        materials = []
        for file_path in self.package_dir.glob("datakit_bundle-linux-amd64-*.tar.gz"):
            materials.append(file_path.name)
        return sorted(materials)


def main():
    parser = argparse.ArgumentParser(description="Datakit物料下载器")
    parser.add_argument("--config", "-c", help="配置文件路径")
    parser.add_argument("--clone", action="store_true", help="克隆远程仓库")
    parser.add_argument("--version", "-v", help="指定下载的版本")
    parser.add_argument("--all", action="store_true", help="下载所有配置的版本")
    parser.add_argument("--list", action="store_true", help="列出已下载的物料")
    
    args = parser.parse_args()
    
    downloader = MaterialDownloader(args.config)
    
    try:
        if args.clone:
            if not downloader.clone_repository():
                sys.exit(1)
        
        if args.version:
            if not downloader.download_datakit_materials(args.version):
                sys.exit(1)
        
        elif args.all:
            if not downloader.download_all_versions():
                sys.exit(1)
        
        elif args.list:
            materials = downloader.list_downloaded_materials()
            if materials:
                logger.info("已下载的物料:")
                for material in materials:
                    logger.info(f"  - {material}")
            else:
                logger.info("暂无已下载的物料")
        
        else:
            parser.print_help()
            
    except KeyboardInterrupt:
        logger.info("用户中断操作")
        sys.exit(1)
    except Exception as e:
        logger.error(f"程序执行时发生错误: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
