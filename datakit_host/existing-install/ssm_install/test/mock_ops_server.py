#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CMDB Observation Agent API Server
实现两个接口：
1. /api/v2/cmdb/observation-agent - 返回Datakit安装/运行配置
2. /api/v2/cmdb/observation-metadata - 返回业务采集配置
"""

from flask import Flask, request, jsonify
import json
import logging
from typing import Dict, List, Any
import os

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# 模拟数据库或配置存储
# 在实际应用中，这些数据应该从数据库或配置文件中读取
MOCK_SERVER_CONFIGS = {
    "127.0.0.1": {
        "env": "prod",
        "workspace": "业务工作空间",
        "global_tags": {
            "global_source": "ec2"
        },
        "dataway_url": "https://dataway.prod-guance.houtai.io",
        "workspace_token": "abcdef123456",
        "datakit_config": {
            "enable": True,
            "global_config": [
                {
                    "key": "log_level",
                    "value": "info",
                    "enable": True
                }
            ],
            "input_config": [
                {
                    "input_name": "ebpf",
                    "input_path": "/usr/local/datakit/conf.d/network/ebpf.conf",
                    "key": "inputs.ebpf.interval",
                    "value": "60s",
                    "enable": True
                }
            ]
        }
    },
    "192.168.1.100": {
        "env": "test",
        "workspace": "测试工作空间",
        "global_tags": {
            "global_source": "vm"
        },
        "dataway_url": "https://dataway.test-guance.houtai.io",
        "workspace_token": "test123456",
        "datakit_config": {
            "enable": True,
            "global_config": [],
            "input_config": []
        }
    }
}

MOCK_METADATA_CONFIGS = {
    "127.0.0.1": {
        "serviceA": {
            "logging": [
                {
                    "logfiles": [
                        "/home/app/bon-gateway-svr/logs/*access_normal.log"
                    ],
                    "source": "ec2-java-logging",
                    "service": "bon-gateway-svr",
                    "tags": {
                        "logType": "access",
                        "lang": "java",
                        "group_name": "gateway-group"
                    }
                },
                {
                    "logfiles": [
                        "/home/app/bon-gateway-svr/logs/*other_normal.log"
                    ],
                    "source": "ec2-java-logging",
                    "service": "bon-gateway-svr",
                    "tags": {
                        "logType": "other",
                        "lang": "java",
                        "group_name": "gateway-group"
                    }
                }
            ],
            "metrics": [
                {
                    "urls": [
                        "http://127.0.0.1:9100/metrics"
                    ],
                    "source": "ec2-java-metrics",
                    "measurement_name": "bon-gateway-svr",
                    "tags": {
                        "service": "bon-gateway-svr",
                        "group_name": "gateway-group"
                    }
                }
            ],
            "health": [
                {
                    "http_urls": ["http://127.0.0.1:8080/health"],
                    "expect_status": 200,
                    "tags": {
                        "service": "bon-gateway-svr",
                        "group_name": "gateway-group"
                    }
                }
            ]
        },
        "serviceB": {
            "logging": [],
            "metrics": [],
            "health": []
        }
    },
    "192.168.1.100": {
        "serviceC": {
            "logging": [
                {
                    "logfiles": [
                        "/var/log/nginx/access.log"
                    ],
                    "source": "ec2-nginx-logging",
                    "service": "web-service",
                    "tags": {
                        "logType": "access",
                        "lang": "nginx",
                        "group_name": "web-group"
                    }
                }
            ],
            "metrics": [
                {
                    "urls": [
                        "http://192.168.1.100:9090/metrics"
                    ],
                    "source": "ec2-nginx-metrics",
                    "measurement_name": "web-service",
                    "tags": {
                        "service": "web-service",
                        "group_name": "web-group"
                    }
                }
            ],
            "health": [
                {
                    "http_urls": ["http://192.168.1.100:80/health"],
                    "expect_status": 200,
                    "tags": {
                        "service": "web-service",
                        "group_name": "web-group"
                    }
                }
            ]
        }
    }
}


def get_server_config(server_ip: str) -> Dict[str, Any]:
    """
    根据服务器IP获取配置信息
    在实际应用中，这里应该查询数据库或配置文件
    """
    return MOCK_SERVER_CONFIGS.get(server_ip, {
        "env": "prod",
        "workspace": "默认工作空间",
        "global_tags": {
            "global_source": "unknown"
        },
        "dataway_url": "https://dataway.prod-guance.houtai.io",
        "workspace_token": "default123456",
        "datakit_config": {
            "enable": True,
            "global_config": [],
            "input_config": []
        }
    })


def get_metadata_config(server_ip: str) -> Dict[str, Any]:
    """
    根据服务器IP获取元数据配置信息
    在实际应用中，这里应该查询数据库或配置文件
    """
    return MOCK_METADATA_CONFIGS.get(server_ip, {})


@app.route('/api/v2/cmdb/observation-agent', methods=['POST'])
def observation_agent():
    """
    接口：根据目标主机 IP 返回用于 Datakit 安装/运行中所需的配置项
    """
    try:
        # 获取请求数据
        data = request.get_json()
        
        if not data:
            return jsonify({
                "error": "请求数据不能为空",
                "code": 400
            }), 400
        
        server_ip = data.get('server_ip')
        
        if not server_ip:
            return jsonify({
                "error": "server_ip 参数不能为空",
                "code": 400
            }), 400
        
        logger.info(f"收到 observation-agent 请求，server_ip: {server_ip}")
        
        # 获取配置信息
        config = get_server_config(server_ip)
        
        logger.info(f"返回配置信息: {json.dumps(config, ensure_ascii=False)}")
        
        return jsonify(config)
        
    except Exception as e:
        logger.error(f"observation-agent 接口异常: {str(e)}")
        return jsonify({
            "error": f"服务器内部错误: {str(e)}",
            "code": 500
        }), 500


@app.route('/api/v2/cmdb/observation-metadata', methods=['POST'])
def observation_metadata():
    """
    接口：根据目标主机 IP 返回用于 Datakit 业务采集所需的配置项
    """
    try:
        # 获取请求数据
        data = request.get_json()
        
        if not data:
            return jsonify({
                "error": "请求数据不能为空",
                "code": 400
            }), 400
        
        server_ip = data.get('server_ip')
        
        if not server_ip:
            return jsonify({
                "error": "server_ip 参数不能为空",
                "code": 400
            }), 400
        
        logger.info(f"收到 observation-metadata 请求，server_ip: {server_ip}")
        
        # 获取元数据配置信息
        metadata_config = get_metadata_config(server_ip)
        
        logger.info(f"返回元数据配置信息: {json.dumps(metadata_config, ensure_ascii=False)}")
        
        return jsonify(metadata_config)
        
    except Exception as e:
        logger.error(f"observation-metadata 接口异常: {str(e)}")
        return jsonify({
            "error": f"服务器内部错误: {str(e)}",
            "code": 500
        }), 500


@app.route('/health', methods=['GET'])
def health_check():
    """
    健康检查接口
    """
    return jsonify({
        "status": "healthy",
        "message": "CMDB Observation Agent API Server is running"
    })


@app.route('/', methods=['GET'])
def index():
    """
    根路径，返回API信息
    """
    return jsonify({
        "name": "CMDB Observation Agent API Server",
        "version": "1.0.0",
        "endpoints": {
            "observation-agent": "/api/v2/cmdb/observation-agent",
            "observation-metadata": "/api/v2/cmdb/observation-metadata",
            "health": "/health"
        }
    })


if __name__ == '__main__':
    # 从环境变量获取端口，默认为5000
    port = int(os.environ.get('PORT', 5000))
    host = os.environ.get('HOST', '0.0.0.0')
    
    logger.info(f"启动 CMDB Observation Agent API Server，监听地址: {host}:{port}")
    
    app.run(
        host=host,
        port=port,
        debug=os.environ.get('DEBUG', 'false').lower() == 'true'
    ) 