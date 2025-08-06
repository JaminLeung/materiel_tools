#!/usr/bin/env python3
"""
Datakit物料同步脚本
与AWS S3存储服务交互，下载和上传Datakit安装所需的物料文件
"""

import os
import sys
import json
import hashlib
import argparse
import requests
import tarfile
import glob
from typing import Dict, List, Optional
from urllib.parse import urlparse
import boto3
from botocore.exceptions import ClientError, NoCredentialsError

class DatakitSync:
    def __init__(self, endpoint_url: str, access_key: str, secret_key: str, bucket_name: str, datakit_dir: str, local_dir: str = "./datakit-offline", secure: bool = True):
        self.endpoint_url = endpoint_url
        self.access_key = access_key
        self.secret_key = secret_key
        self.secure = secure
        self.bucket_name = bucket_name
        self.datakit_dir = datakit_dir
        self.local_dir = local_dir
        os.makedirs(self.local_dir, exist_ok=True)
        self.s3_client = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            use_ssl=secure
        )
        self.pkg_url = {
            "installer": "https://static.guance.com/datakit/installer-{os_type}-{orch}-{version}",
            "datakit": "https://static.guance.com/datakit/datakit-{os_type}-{orch}-{version}.tar.gz",
            "datakit_lite": "https://static.guance.com/datakit/datakit_lite-{os_type}-{orch}-{version}.tar.gz",
            "datakit-apm-inject": "https://static.guance.com/datakit/datakit-apm-inject-{os_type}-{orch}-{version}.tar.gz",
            "upgrader": "https://static.guance.com/datakit/dk_upgrader-{os_type}-{orch}.tar.gz",
            "data.tar.gz": "https://static.guance.com/datakit/data.tar.gz",
            "node_exporter-1.8.2.linux-amd64.tar.gz": "https://guance-south.oss-cn-guangzhou.aliyuncs.com/liangjieming/bingx-prod/node_exporter-1.8.2.linux-amd64.tar.gz",
            "jq": "https://guance-south.oss-cn-guangzhou.aliyuncs.com/liangjieming/bingx-prod/jq",
            "yj": "https://guance-south.oss-cn-guangzhou.aliyuncs.com/liangjieming/bingx-prod/yj",
            "aws-cli": "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
        }
        self.os_type = "linux"
        self.orch = "amd64"
        self.version = "1.78.0"

    def validate_connection(self) -> bool:
        try:
            self.s3_client.head_bucket(Bucket=self.bucket_name)
            print(f"✅ S3连接验证成功，Bucket '{self.bucket_name}' 存在")
            return True
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == '404':
                print(f"❌ Bucket '{self.bucket_name}' 不存在")
            else:
                print(f"❌ S3连接验证失败: {e}")
            return False
        except NoCredentialsError:
            print("❌ 未找到AWS凭证")
            return False
        except Exception as e:
            print(f"❌ S3连接验证失败: {e}")
            return False

    def download_file(self, url: str, local_path: str) -> bool:
        try:
            print(f"📥 下载文件: {url}")
            response = requests.get(url, stream=True, timeout=300)
            response.raise_for_status()
            with open(local_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            print(f"✅ 文件下载完成: {local_path}")
            return True
        except requests.exceptions.RequestException as e:
            print(f"❌ 文件下载失败: {e}")
            return False

    def download_from_s3(self, s3_key: str, local_path: str) -> bool:
        try:
            print(f"📥 从S3下载文件: {s3_key}")
            self.s3_client.download_file(self.bucket_name, s3_key, local_path)
            print(f"✅ S3文件下载完成: {local_path}")
            return True
        except Exception as e:
            print(f"❌ S3文件下载失败: {e}")
            return False

    def calculate_md5(self, file_path: str) -> str:
        hash_md5 = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()

    def verify_md5(self, file_path: str, expected_md5: str) -> bool:
        actual_md5 = self.calculate_md5(file_path)
        if actual_md5 == expected_md5:
            print(f"✅ MD5验证成功: {file_path}")
            return True
        else:
            print(f"❌ MD5验证失败: {file_path}")
            print(f"   期望: {expected_md5}")
            print(f"   实际: {actual_md5}")
            return False

    def download_bundle_from_s3(self) -> bool:
        """从S3下载已打包的bundle文件和MD5文件"""
        bundle_name = f"datakit_bundle-{self.os_type}-{self.orch}-{self.version}.tar.gz"
        s3_bundle_key = f"{self.datakit_dir}/{bundle_name}"
        s3_md5_key = f"{self.datakit_dir}/{bundle_name}.md5"
        
        local_bundle_path = os.path.join(self.local_dir, bundle_name)
        local_md5_path = os.path.join(self.local_dir, f"{bundle_name}.md5")
        
        # 下载bundle文件
        if not self.download_from_s3(s3_bundle_key, local_bundle_path):
            return False
            
        # 下载MD5文件
        if not self.download_from_s3(s3_md5_key, local_md5_path):
            return False
            
        # 读取期望的MD5值
        try:
            with open(local_md5_path, 'r') as f:
                expected_md5 = f.read().strip()
        except Exception as e:
            print(f"❌ 读取MD5文件失败: {e}")
            return False
            
        # 验证MD5
        if not self.verify_md5(local_bundle_path, expected_md5):
            return False
            
        print(f"🎉 Bundle下载和验证完成: {local_bundle_path}")
        return True

    def download_all_packages(self) -> Dict[str, str]:
        print("🚀 开始下载Datakit安装包...")
        downloaded_files = {}
        for file_name, url_template in self.pkg_url.items():
            if "{os_type}" in url_template or "{orch}" in url_template or "{version}" in url_template:
                url = url_template.format(
                    os_type=self.os_type,
                    orch=self.orch,
                    version=self.version
                )
            else:
                url = url_template
            if file_name in ["installer", "datakit", "datakit_lite", "datakit-apm-inject"]:
                local_filename = f"{file_name}-{self.os_type}-{self.orch}-{self.version}"
                if file_name != "installer":
                    local_filename += ".tar.gz"
            elif file_name == "upgrader":
                local_filename = f"dk_upgrader-{self.os_type}-{self.orch}.tar.gz"
            else:
                local_filename = file_name
            local_path = os.path.join(self.local_dir, local_filename)
            if self.download_file(url, local_path):
                downloaded_files[file_name] = local_path
        print(f"✅ 下载完成，共下载 {len(downloaded_files)} 个文件")
        return downloaded_files

    def make_bundle_tar(self, files: dict, bundle_name: str) -> str:
        tar_path = os.path.join(self.local_dir, bundle_name)
        with tarfile.open(tar_path, "w:gz") as tar:
            for file_name, file_path in files.items():
                # 跳过已存在的bundle文件和md5文件，避免重复打包
                if os.path.basename(file_path) == bundle_name or file_path.endswith('.md5'):
                    continue
                print(f"📦 打包文件: {os.path.basename(file_path)}")
                tar.add(file_path, arcname=os.path.basename(file_path))
        print(f"📦 打包完成: {tar_path}")
        return tar_path

    def upload_file(self, local_path: str, s3_key: str) -> bool:
        try:
            print(f"📤 上传文件: {local_path} -> {s3_key}")
            file_size = os.path.getsize(local_path)
            self.s3_client.upload_file(
                local_path,
                self.bucket_name,
                s3_key,
                ExtraArgs={'ContentType': self._get_content_type(local_path)}
            )
            print(f"✅ 文件上传完成: {s3_key} ({file_size} bytes)")
            return True
        except Exception as e:
            print(f"❌ 文件上传失败: {e}")
            return False

    def _get_content_type(self, file_path: str) -> str:
        ext = os.path.splitext(file_path)[1].lower()
        content_types = {
            '.tar.gz': 'application/gzip',
            '.gz': 'application/gzip',
            '.sh': 'application/x-sh',
            '.conf': 'text/plain',
            '.json': 'application/json',
            '.yaml': 'text/yaml',
            '.yml': 'text/yaml'
        }
        return content_types.get(ext, 'application/octet-stream')

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

    def main_flow(self, args):
        # 检查是否指定了自定义本地目录
        if args.local_dir != "./datakit-offline":
            print(f"📁 使用自定义目录: {args.local_dir}")
            print("🔍 从S3下载已打包的bundle文件...")
            if self.download_bundle_from_s3():
                print("🎉 Bundle下载和验证完成！")
            else:
                print("❌ Bundle下载或验证失败")
                sys.exit(1)
        else:
            # 默认行为：下载所有文件并打包上传
            downloaded_files = self.download_all_packages()
            self.bundle_and_upload(downloaded_files)
            print("🎉 物料打包并上传完成！")


def main():
    parser = argparse.ArgumentParser(description="Datakit物料同步脚本（打包上传模式）")
    parser.add_argument("--endpoint", default="https://s3.ap-southeast-1.amazonaws.com", help="S3 endpoint URL")
    parser.add_argument("--access-key", default="AWS_ACCESS_KEY_ID_PLACEHOLDER", help="Access key")
    parser.add_argument("--secret-key", default="Qxkc7ZWvQogYXSrOaNmsBNw+5exVg8vjstz1m+p/", help="Secret key")
    parser.add_argument("--bucket", default="benjamin--test", help="S3 bucket name")
    parser.add_argument("--prefix", default="datakit", help="S3 object key prefix (default: datakit)")
    parser.add_argument("--local-dir", default="./datakit-offline", help="本地下载目录 (默认: ./datakit-offline)")
    parser.add_argument("--secure", action="store_true", default=True, help="Use HTTPS")
    parser.add_argument("--version", default="1.78.0", help="Datakit版本")
    parser.add_argument("--os-type", default="linux", help="操作系统类型")
    parser.add_argument("--orch", default="amd64", help="架构类型")
    args = parser.parse_args()
    sync = DatakitSync(
        endpoint_url=args.endpoint,
        access_key=args.access_key,
        secret_key=args.secret_key,
        bucket_name=args.bucket,
        datakit_dir=args.prefix,
        local_dir=args.local_dir,
        secure=args.secure
    )
    sync.version = args.version
    sync.os_type = args.os_type
    sync.orch = args.orch
    if not sync.validate_connection():
        sys.exit(1)
    sync.main_flow(args)

if __name__ == "__main__":
    main() 
    
    
    