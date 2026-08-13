#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Datakit 自动化工具构建脚本
用于构建 datakit-apm-inject 包和最终的安装包
"""

import os
import sys
import json
import hashlib
import tarfile
import subprocess
import requests
import tempfile
import shutil
from pathlib import Path
from typing import List, Dict, Optional
import argparse
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('build.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

class DatakitBuilder:
    def __init__(self, config_file: str = "build_config.json", env: Optional[str] = None):
        self.config_file = config_file
        self.config = self.load_config()
        self.work_dir = Path.cwd()
        self.work_dir = Path.cwd()
        self.datakit_version = "2.8.0"
        self.installer_version = "1.0.16_2.8.0"
        self.env = env


    def load_config(self) -> Dict:
        """加载构建配置"""
        if not os.path.exists(self.config_file):
            default_config = {
                "git_repo": "https://github.com/JaminLeung/materiel_tools.git",
                "datakit_version": self.datakit_version,
                "installer_version": "1.0.16_2.8.0",
                "git_branch": "dev_2.8.0",
                "binary_urls": [
                    f"https://static.guance.com/datakit-v2/installer-linux-amd64-{self.datakit_version}",
                    f"https://static.guance.com/datakit-v2/datakit-apm-inject-linux-amd64-{self.datakit_version}.tar.gz",
                    f"https://static.guance.com/datakit-v2/datakit-linux-amd64-{self.datakit_version}.tar.gz",
                    f"https://static.guance.com/datakit-v2/datakit_lite-linux-amd64-{self.datakit_version}.tar.gz",
                    f"https://static.guance.com/datakit-v2/datakit-apm-inject-linux-amd64-{self.datakit_version}.tar.gz",
                    f"https://static.guance.com/datakit-v2/dk_upgrader-linux-amd64-{self.datakit_version}.tar.gz",
                    "https://static.guance.com/datakit-v2/data.tar.gz",
                    "https://guance-south.oss-cn-guangzhou.aliyuncs.com/liangjieming/bingx-prod/yj",
                    "https://guance-south.oss-cn-guangzhou.aliyuncs.com/liangjieming/bingx-prod/jq",
                    "https://guance-south.oss-cn-guangzhou.aliyuncs.com/liangjieming/bingx-prod/node_exporter-1.8.2.linux-amd64.tar.gz"
                ],
                "package_name": "datakit_bundle-linux-amd64",
                "final_package_name": "datakit-automation-all"
            }
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(default_config, f, indent=2, ensure_ascii=False)
            logger.info(f"创建默认配置文件: {self.config_file}")
            return default_config

        with open(self.config_file, 'r', encoding='utf-8') as f:
            config = json.load(f)
        logger.info(f"加载配置文件: {self.config_file}")
        print(f"{config}")
        return config

    def run_command(self, cmd: List[str], cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
        """执行命令"""
        logger.info(f"执行命令: {' '.join(cmd)}")
        if cwd:
            logger.info(f"工作目录: {cwd}")

        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding='utf-8'
        )

        if result.returncode != 0:
            logger.error(f"命令执行失败: {result.stderr}")
            raise subprocess.CalledProcessError(result.returncode, cmd, result.stdout, result.stderr)

        logger.info(f"命令执行成功: {result.stdout}")
        return result

    def git_clone(self) -> Path:
        """克隆代码仓库"""
        logger.info("开始克隆代码仓库...")

        repo_url = self.config["git_repo"]
        repo_name = repo_url.split('/')[-1].replace('.git', '')
        clone_dir = self.work_dir / repo_name

        if clone_dir.exists():
            logger.info(f"目录已存在，删除: {clone_dir}")
            shutil.rmtree(clone_dir)

        git_branch = self.config.get("git_branch")
        clone_cmd = ["git", "clone", "--depth", "1"]
        if git_branch:
            clone_cmd.extend(["-b", git_branch])
        clone_cmd.append(repo_url)
        self.run_command(clone_cmd)

        if not clone_dir.exists():
            raise FileNotFoundError(f"克隆失败，目录不存在: {clone_dir}")

        logger.info(f"代码克隆完成: {clone_dir}")
        print(type(clone_dir))
        return clone_dir / "datakit-automation"

    def get_versions(self, code_dir: Path) -> Dict[str, str]:
        """获取版本信息"""
        logger.info("获取版本信息...")

        versions = {
            "datakit_version": self.datakit_version,
            "installer_version": self.installer_version
        }

        # # 尝试从changelog.md获取installer版本
        # changelog_file = code_dir / "changelog.md"
        # if changelog_file.exists():
        #     with open(changelog_file, 'r', encoding='utf-8') as f:
        #         content = f.read()
        #         import re
        #         version_match = re.search(r'\[(\d+\.\d+\.\d+)\]', content)
        #         if version_match:
        #             versions["installer_version"] = version_match.group(1)

        # # 尝试从installer脚本获取datakit版本
        # installer_file = code_dir / "datakit_auto_installer.sh"
        # if installer_file.exists():
        #     with open(installer_file, 'r', encoding='utf-8') as f:
        #         content = f.read()
        #         import re
        #         datakit_match = re.search(r'DATAKIT_VERSION="([^"]+)"', content)
        #         if datakit_match:
        #             versions["datakit_version"] = datakit_match.group(1)

        logger.info(f"版本信息: {versions}")
        return versions

    def create_package_dir(self, code_dir: Path) -> Path:
        """创建package目录"""
        package_dir = code_dir / "package"
        package_dir.mkdir(exist_ok=True)
        logger.info(f"创建package目录: {package_dir}")
        return package_dir

    def download_binary(self, url: str, target_dir: Path) -> Path:
        """下载二进制文件"""
        logger.info(f"下载文件: {url}")

        filename = url.split('/')[-1]
        target_path = target_dir / filename

        try:
            response = requests.get(url, stream=True, timeout=30)
            response.raise_for_status()

            with open(target_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)

            logger.info(f"下载完成: {target_path}")
            return target_path

        except Exception as e:
            logger.error(f"下载失败: {url}, 错误: {e}")
            raise

    def download_binaries(self, package_dir: Path) -> List[Path]:
        """下载所有二进制文件"""
        logger.info("开始下载二进制文件...")

        downloaded_files = []
        for url in self.config["binary_urls"]:
            try:
                file_path = self.download_binary(url, package_dir)
                downloaded_files.append(file_path)
            except Exception as e:
                logger.error(f"下载失败: {url}")
                raise

        logger.info(f"所有文件下载完成，共 {len(downloaded_files)} 个文件")
        return downloaded_files

    def create_tar_package(self, package_dir: Path, datakit_version: str) -> Path:
        """创建tar.gz包"""
        logger.info("开始创建tar.gz包...")

        package_name = self.config["package_name"]
        tar_filename = f"{package_name}-{datakit_version}.tar.gz"
        tar_path = package_dir / tar_filename

        with tarfile.open(tar_path, 'w:gz') as tar:
            # 添加package目录下的所有文件
            for file_path in package_dir.glob("*"):
                if file_path.is_file() and file_path.name != tar_filename:
                    arcname = file_path.name
                    tar.add(file_path, arcname=arcname)
                    logger.info(f"添加文件到tar包: {arcname}")

        logger.info(f"tar.gz包创建完成: {tar_path}")
        return tar_path

    def calculate_md5(self, file_path: Path) -> str:
        """计算文件MD5值"""
        logger.info(f"计算MD5值: {file_path}")

        md5_hash = hashlib.md5()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                md5_hash.update(chunk)

        md5_value = md5_hash.hexdigest()
        logger.info(f"MD5值: {md5_value}")
        return md5_value

    def create_md5_file(self, tar_path: Path, md5_value: str) -> Path:
        """创建MD5文件"""
        md5_file_path = tar_path.with_suffix('.gz.md5')

        with open(md5_file_path, 'w', encoding='utf-8') as f:
            f.write(f"{md5_value}  {tar_path.name}\n")

        logger.info(f"MD5文件创建完成: {md5_file_path}")
        return md5_file_path

    def create_final_package(self, code_dir: Path, installer_version: str) -> Path:
        """创建最终的安装包"""
        logger.info("开始创建最终安装包...")

        final_package_name = self.config["final_package_name"]
        final_filename = f"{final_package_name}_{installer_version}_{self.env}.tgz"
        final_path = self.work_dir / final_filename

        with tarfile.open(final_path, 'w:gz') as tar:
            # 添加整个代码目录
            tar.add(code_dir, arcname=code_dir.name)
            logger.info(f"添加目录到最终包: {code_dir.name}")

        logger.info(f"最终安装包创建完成: {final_path}")
        return final_path

    def cleanup_downloaded_files(self, downloaded_files: List[Path]):
        """清理下载的物料文件"""
        logger.info("开始清理下载的物料文件...")

        cleaned_count = 0
        for file_path in downloaded_files:
            try:
                if file_path.exists():
                    file_path.unlink()
                    logger.info(f"删除文件: {file_path}")
                    cleaned_count += 1
                else:
                    logger.warning(f"文件不存在，跳过删除: {file_path}")
            except Exception as e:
                logger.error(f"删除文件失败: {file_path}, 错误: {e}")

        logger.info(f"清理完成，共删除 {cleaned_count} 个文件")

    def create_tools_package(self, code_dir: Path, installer_version: str) -> Optional[Path]:
        """将 tools 目录下的所有 bash 脚本（*.sh）打包为独立的 tgz 包"""
        logger.info("开始创建 tools 脚本独立包...")

        tools_dir = code_dir / "tools"
        if not tools_dir.exists() or not tools_dir.is_dir():
            logger.warning(f"tools 目录不存在，跳过: {tools_dir}")
            return None

        # 仅包含 tools 目录下的 .sh 文件（不递归）
        sh_files = list(tools_dir.glob("*.sh"))
        if not sh_files:
            logger.warning("未发现任何 .sh 脚本，跳过 tools 包创建")
            return None

        final_package_name = self.config["final_package_name"]
        tools_filename = f"{final_package_name}_tools_{installer_version}.tgz"
        tools_tar_path = self.work_dir / tools_filename

        with tarfile.open(tools_tar_path, 'w:gz') as tar:
            for file_path in sh_files:
                # 归档名保持在 tools/ 子目录下
                arcname = f"tools/{file_path.name}"
                tar.add(file_path, arcname=arcname)
                logger.info(f"添加脚本到tools包: {arcname}")

        logger.info(f"tools 包创建完成: {tools_tar_path}")
        return tools_tar_path

    def cleanup_env_config(self, code_dir: Path):
        """清理环境配置文件，只保留指定环境的配置文件"""
        if not self.env:
            logger.info("未指定环境参数，跳过环境配置文件清理")
            return

        logger.info(f"开始清理环境配置文件，保留环境: {self.env}")

        env_config_dir = code_dir / "config" / "env"

        # 检查目录是否存在
        if not env_config_dir.exists() or not env_config_dir.is_dir():
            logger.warning(f"环境配置目录不存在，跳过: {env_config_dir}")
            return

        # 构建目标文件名
        target_file = env_config_dir / f"{self.env}.sh"

        # 校验目标文件是否存在
        if not target_file.exists():
            error_msg = f"环境配置文件不存在: {target_file}"
            logger.error(error_msg)
            raise FileNotFoundError(error_msg)

        logger.info(f"找到目标环境配置文件: {target_file}")

        # 获取所有 .sh 文件
        all_sh_files = list(env_config_dir.glob("*.sh"))

        if not all_sh_files:
            logger.warning("未发现任何环境配置文件")
            return

        # 删除其他环境的配置文件
        deleted_count = 0
        for file_path in all_sh_files:
            if file_path.name != f"{self.env}.sh":
                try:
                    file_path.unlink()
                    logger.info(f"删除环境配置文件: {file_path.name}")
                    deleted_count += 1
                except Exception as e:
                    logger.error(f"删除文件失败: {file_path}, 错误: {e}")
                    raise

        logger.info(f"环境配置文件清理完成，保留: {target_file.name}，删除: {deleted_count} 个文件")

    def build(self):
        """执行完整的构建流程"""
        logger.info("开始构建流程...")

        try:
            # 1. 克隆代码
            code_dir = self.git_clone()

            # 2. 清理环境配置文件（如果指定了环境参数）
            self.cleanup_env_config(code_dir)

            # 3. 获取版本信息
            versions = self.get_versions(code_dir)
            datakit_version = versions["datakit_version"]
            installer_version = versions["installer_version"]

            # 4. 创建package目录
            package_dir = self.create_package_dir(code_dir)

            # 5. 下载二进制文件
            downloaded_files = self.download_binaries(package_dir)

            # 6. 创建tar.gz包
            tar_path = self.create_tar_package(package_dir, datakit_version)

            # 7. 计算MD5值并创建MD5文件
            md5_value = self.calculate_md5(tar_path)
            md5_file_path = self.create_md5_file(tar_path, md5_value)

            # 8.清理打包前物料清理
            self.cleanup_downloaded_files(downloaded_files)

            # 9. 创建最终安装包
            final_package_path = self.create_final_package(code_dir, installer_version)

            # 10. 额外创建 tools 脚本独立包（默认启用）
            tools_package_path = self.create_tools_package(code_dir, installer_version)

            logger.info("构建流程完成!")
            logger.info(f"最终安装包: {final_package_path}")
            if tools_package_path:
                logger.info(f"Tools脚本包: {tools_package_path}")
            logger.info(f"Datakit版本: {datakit_version}")
            logger.info(f"Installer版本: {installer_version}")

        except Exception as e:
            logger.error(f"构建失败: {e}")
            raise

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="Datakit 自动化工具构建脚本")
    parser.add_argument(
        "--config", 
        default="build_config.json",
        help="配置文件路径 (默认: build_config.json)"
    )
    parser.add_argument(
        "--verbose", 
        action="store_true",
        help="详细输出"
    )
    parser.add_argument(
        "--env",
        type=str,
        help="指定环境（如: prod, test, pre），将清理其他环境的配置文件，只保留指定环境的配置文件"
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        builder = DatakitBuilder(args.config, env=args.env)
        builder.build()
    except Exception as e:
        logger.error(f"构建失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
