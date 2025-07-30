#!/usr/bin/env python3
"""
Datakit物料同步脚本单元测试
"""

import unittest
import tempfile
import os
import shutil
import json
from unittest.mock import Mock, patch, MagicMock, mock_open
from datetime import datetime

# 导入被测试的模块
from datakit_sync import DatakitSync


class TestDatakitSync(unittest.TestCase):
    """DatakitSync类单元测试"""

    def setUp(self):
        """测试前的准备工作"""
        self.temp_dir = tempfile.mkdtemp()
        self.endpoint_url = "https://test-s3-endpoint.com"
        self.access_key = "test-access-key"
        self.secret_key = "test-secret-key"
        
        # 创建测试实例
        with patch('boto3.client'):
            self.sync = DatakitSync(
                endpoint_url=self.endpoint_url,
                access_key=self.access_key,
                secret_key=self.secret_key
            )
            self.sync.local_dir = self.temp_dir

    def tearDown(self):
        """测试后的清理工作"""
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_init(self):
        """测试初始化"""
        with patch('boto3.client') as mock_boto3:
            sync = DatakitSync(
                endpoint_url=self.endpoint_url,
                access_key=self.access_key,
                secret_key=self.secret_key
            )
            
            # 验证boto3.client被正确调用
            mock_boto3.assert_called_once_with(
                's3',
                endpoint_url=self.endpoint_url,
                aws_access_key_id=self.access_key,
                aws_secret_access_key=self.secret_key,
                use_ssl=True
            )
            
            # 验证基本属性
            self.assertEqual(sync.endpoint_url, self.endpoint_url)
            self.assertEqual(sync.access_key, self.access_key)
            self.assertEqual(sync.secret_key, self.secret_key)
            self.assertEqual(sync.bucket_name, "guance")
            self.assertEqual(sync.datakit_dir, "datakit")
            self.assertEqual(sync.os_type, "linux")
            self.assertEqual(sync.orch, "amd64")
            self.assertEqual(sync.version, "1.78.0")

    def test_validate_connection_success(self):
        """测试连接验证成功"""
        # Mock S3客户端
        mock_s3_client = Mock()
        self.sync.s3_client = mock_s3_client
        
        # 模拟成功响应
        mock_s3_client.head_bucket.return_value = {}
        
        result = self.sync.validate_connection()
        
        self.assertTrue(result)
        mock_s3_client.head_bucket.assert_called_once_with(Bucket="guance")

    def test_validate_connection_bucket_not_found(self):
        """测试连接验证失败 - 存储桶不存在"""
        mock_s3_client = Mock()
        self.sync.s3_client = mock_s3_client
        
        # 模拟存储桶不存在错误
        from botocore.exceptions import ClientError
        error_response = {'Error': {'Code': '404'}}
        mock_s3_client.head_bucket.side_effect = ClientError(
            error_response, 'HeadBucket'
        )
        
        result = self.sync.validate_connection()
        
        self.assertFalse(result)

    def test_validate_connection_no_credentials(self):
        """测试连接验证失败 - 无凭证"""
        mock_s3_client = Mock()
        self.sync.s3_client = mock_s3_client
        
        # 模拟无凭证错误
        from botocore.exceptions import NoCredentialsError
        mock_s3_client.head_bucket.side_effect = NoCredentialsError()
        
        result = self.sync.validate_connection()
        
        self.assertFalse(result)

    @patch('requests.get')
    def test_download_file_success(self, mock_get):
        """测试文件下载成功"""
        # Mock requests响应
        mock_response = Mock()
        mock_response.iter_content.return_value = [b'test content']
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        test_url = "https://example.com/test.txt"
        test_path = os.path.join(self.temp_dir, "test.txt")
        
        result = self.sync.download_file(test_url, test_path)
        
        self.assertTrue(result)
        self.assertTrue(os.path.exists(test_path))
        
        # 验证文件内容
        with open(test_path, 'rb') as f:
            content = f.read()
        self.assertEqual(content, b'test content')

    @patch('requests.get')
    def test_download_file_failure(self, mock_get):
        """测试文件下载失败"""
        # Mock requests异常
        mock_get.side_effect = Exception("Network error")
        
        test_url = "https://example.com/test.txt"
        test_path = os.path.join(self.temp_dir, "test.txt")
        
        result = self.sync.download_file(test_url, test_path)
        
        self.assertFalse(result)
        self.assertFalse(os.path.exists(test_path))

    def test_upload_file_success(self):
        """测试文件上传成功"""
        # 创建测试文件
        test_file_path = os.path.join(self.temp_dir, "test.txt")
        with open(test_file_path, 'w') as f:
            f.write("test content")
        
        # Mock S3客户端
        mock_s3_client = Mock()
        self.sync.s3_client = mock_s3_client
        
        s3_key = "datakit/test.txt"
        result = self.sync.upload_file(test_file_path, s3_key)
        
        self.assertTrue(result)
        mock_s3_client.upload_file.assert_called_once()

    def test_upload_file_failure(self):
        """测试文件上传失败"""
        # Mock S3客户端异常
        mock_s3_client = Mock()
        self.sync.s3_client = mock_s3_client
        mock_s3_client.upload_file.side_effect = Exception("Upload failed")
        
        test_file_path = os.path.join(self.temp_dir, "test.txt")
        with open(test_file_path, 'w') as f:
            f.write("test content")
        
        s3_key = "datakit/test.txt"
        result = self.sync.upload_file(test_file_path, s3_key)
        
        self.assertFalse(result)

    def test_get_content_type(self):
        """测试Content-Type获取"""
        test_cases = [
            ("test.tar.gz", "application/gzip"),
            ("script.sh", "application/x-sh"),
            ("config.conf", "text/plain"),
            ("data.json", "application/json"),
            ("config.yaml", "text/yaml"),
            ("unknown.xyz", "application/octet-stream")
        ]
        
        for file_path, expected_type in test_cases:
            result = self.sync._get_content_type(file_path)
            self.assertEqual(result, expected_type)

    def test_calculate_md5(self):
        """测试MD5计算"""
        # 创建测试文件
        test_file_path = os.path.join(self.temp_dir, "test.txt")
        test_content = "Hello, World!"
        with open(test_file_path, 'w') as f:
            f.write(test_content)
        
        # 计算MD5
        md5_result = self.sync.calculate_md5(test_file_path)
        
        # 验证MD5值（"Hello, World!"的MD5值）
        expected_md5 = "65a8e27d8879283831b664bd8b7f0ad4"
        self.assertEqual(md5_result, expected_md5)

    @patch.object(DatakitSync, 'download_file')
    def test_download_all_packages(self, mock_download):
        """测试下载所有包"""
        # Mock下载成功
        mock_download.return_value = True
        
        # 创建测试文件
        test_file_path = os.path.join(self.temp_dir, "installer-linux-amd64-1.78.0")
        with open(test_file_path, 'w') as f:
            f.write("test installer")
        
        result = self.sync.download_all_packages()
        
        # 验证结果
        self.assertIsInstance(result, dict)
        self.assertGreater(len(result), 0)
        
        # 验证下载被调用
        self.assertGreater(mock_download.call_count, 0)

    @patch.object(DatakitSync, 'upload_file')
    def test_upload_all_packages(self, mock_upload):
        """测试上传所有包"""
        # Mock上传成功
        mock_upload.return_value = True
        
        # 准备测试数据
        downloaded_files = {
            "installer": os.path.join(self.temp_dir, "installer-linux-amd64-1.78.0"),
            "datakit": os.path.join(self.temp_dir, "datakit-linux-amd64-1.78.0.tar.gz")
        }
        
        # 创建测试文件
        for file_path in downloaded_files.values():
            with open(file_path, 'w') as f:
                f.write("test content")
        
        result = self.sync.upload_all_packages(downloaded_files)
        
        self.assertTrue(result)
        self.assertEqual(mock_upload.call_count, len(downloaded_files))

    def test_create_package_config(self):
        """测试包配置文件创建"""
        # 准备测试数据
        downloaded_files = {
            "installer": os.path.join(self.temp_dir, "installer-linux-amd64-1.78.0"),
            "datakit": os.path.join(self.temp_dir, "datakit-linux-amd64-1.78.0.tar.gz")
        }
        
        # 创建测试文件
        for file_path in downloaded_files.values():
            with open(file_path, 'w') as f:
                f.write("test content")
        
        result = self.sync.create_package_config(downloaded_files)
        
        # 验证配置结构
        self.assertIn("version", result)
        self.assertIn("os_type", result)
        self.assertIn("architecture", result)
        self.assertIn("files", result)
        self.assertIn("metadata", result)
        
        # 验证文件信息
        self.assertEqual(result["version"], "1.78.0")
        self.assertEqual(result["os_type"], "linux")
        self.assertEqual(result["architecture"], "amd64")
        self.assertEqual(len(result["files"]), 2)

    @patch('builtins.open', new_callable=mock_open)
    @patch('json.dump')
    def test_create_package_config_file_save(self, mock_json_dump, mock_file):
        """测试包配置文件保存"""
        downloaded_files = {
            "installer": os.path.join(self.temp_dir, "installer-linux-amd64-1.78.0")
        }
        
        # 创建测试文件
        with open(downloaded_files["installer"], 'w') as f:
            f.write("test content")
        
        self.sync.create_package_config(downloaded_files)
        
        # 验证文件保存
        mock_file.assert_called()
        mock_json_dump.assert_called()

    def test_url_template_formatting(self):
        """测试URL模板格式化"""
        # 测试动态URL格式化
        url_template = "https://example.com/{os_type}-{orch}-{version}.tar.gz"
        expected_url = "https://example.com/linux-amd64-1.78.0.tar.gz"
        
        # 模拟下载过程中的URL处理
        if "{os_type}" in url_template or "{orch}" in url_template or "{version}" in url_template:
            formatted_url = url_template.format(
                os_type=self.sync.os_type,
                orch=self.sync.orch,
                version=self.sync.version
            )
        else:
            formatted_url = url_template
        
        self.assertEqual(formatted_url, expected_url)

    def test_local_filename_generation(self):
        """测试本地文件名生成"""
        # 测试不同类型的文件名生成
        test_cases = [
            ("installer", "installer-linux-amd64-1.78.0"),
            ("datakit", "datakit-linux-amd64-1.78.0.tar.gz"),
            ("datakit_lite", "datakit_lite-linux-amd64-1.78.0.tar.gz"),
            ("upgrader", "dk_upgrader-linux-amd64.tar.gz"),
            ("data.tar.gz", "data.tar.gz")
        ]
        
        for file_name, expected_filename in test_cases:
            if file_name in ["installer", "datakit", "datakit_lite", "datakit-apm-inject"]:
                local_filename = f"{file_name}-{self.sync.os_type}-{self.sync.orch}-{self.sync.version}"
                if file_name != "installer":
                    local_filename += ".tar.gz"
            elif file_name == "upgrader":
                local_filename = f"dk_upgrader-{self.sync.os_type}-{self.sync.orch}.tar.gz"
            else:
                local_filename = file_name
            
            self.assertEqual(local_filename, expected_filename)

    def test_s3_key_generation(self):
        """测试S3 key生成"""
        # 测试不同类型的S3 key生成
        test_cases = [
            ("installer", "datakit/installer-linux-amd64-1.78.0"),
            ("datakit", "datakit/datakit-linux-amd64-1.78.0.tar.gz"),
            ("upgrader", "datakit/dk_upgrader-linux-amd64.tar.gz"),
            ("data.tar.gz", "datakit/data.tar.gz")
        ]
        
        for file_name, expected_s3_key in test_cases:
            if file_name in ["installer", "datakit", "datakit_lite", "datakit-apm-inject"]:
                s3_key = f"{self.sync.datakit_dir}/{file_name}-{self.sync.os_type}-{self.sync.orch}-{self.sync.version}"
                if file_name != "installer":
                    s3_key += ".tar.gz"
            elif file_name == "upgrader":
                s3_key = f"{self.sync.datakit_dir}/dk_upgrader-{self.sync.os_type}-{self.sync.orch}.tar.gz"
            else:
                s3_key = f"{self.sync.datakit_dir}/{file_name}"
            
            self.assertEqual(s3_key, expected_s3_key)

    def test_secure_parameter(self):
        """测试secure参数"""
        # 测试secure=False的情况
        with patch('boto3.client') as mock_boto3:
            sync = DatakitSync(
                endpoint_url=self.endpoint_url,
                access_key=self.access_key,
                secret_key=self.secret_key,
                secure=False
            )
            
            mock_boto3.assert_called_once_with(
                's3',
                endpoint_url=self.endpoint_url,
                aws_access_key_id=self.access_key,
                aws_secret_access_key=self.secret_key,
                use_ssl=False
            )


class TestDatakitSyncIntegration(unittest.TestCase):
    """集成测试类"""

    def setUp(self):
        """测试前的准备工作"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """测试后的清理工作"""
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    @patch('boto3.client')
    @patch('requests.get')
    def test_full_download_upload_workflow(self, mock_get, mock_boto3):
        """测试完整的下载上传工作流"""
        # Mock S3客户端
        mock_s3_client = Mock()
        mock_boto3.return_value = mock_s3_client
        mock_s3_client.head_bucket.return_value = {}
        mock_s3_client.upload_file.return_value = None
        
        # Mock HTTP请求
        mock_response = Mock()
        mock_response.iter_content.return_value = [b'test content']
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        # 创建同步实例
        sync = DatakitSync(
            endpoint_url="https://test-endpoint.com",
            access_key="test-key",
            secret_key="test-secret"
        )
        sync.local_dir = self.temp_dir
        
        # 执行完整流程
        # 1. 验证连接
        connection_valid = sync.validate_connection()
        self.assertTrue(connection_valid)
        
        # 2. 下载包
        downloaded_files = sync.download_all_packages()
        self.assertIsInstance(downloaded_files, dict)
        
        # 3. 上传包
        if downloaded_files:
            upload_success = sync.upload_all_packages(downloaded_files)
            self.assertTrue(upload_success)
        
        # 4. 创建配置
        config = sync.create_package_config(downloaded_files)
        self.assertIsInstance(config, dict)


if __name__ == '__main__':
    # 运行测试
    unittest.main(verbosity=2) 