#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CMDB Observation Agent API Server
实现两个接口：
1. /api/v2/cmdb/observation-agent - 返回Datakit安装/运行配置
2. /api/v2/cmdb/observation-app-metadata - 返回业务采集配置
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
    "data": {
        "env": "prod",
        "workspace": "业务工作空间aaaaa",
        "global_tags": {
            "global_source": {
                "app": "datakit",
                "env1": "production",
                "region1": "ap-southeast-sssss1",
                "service1": "monitoringaaaaaaaaaaaaadsdsa",
                "team1": "ops"
            }
        },
        "dataway_url": "https://openway.guance.com",
        "workspace_token": "tkn_3a0052c9f6d3498c8ce9ca0988fd9c82",
        "datakit_config": {
            "enable": True,
            "global_config": [
                {
                    "key": "logging.levellll",
                    "value": "info",
                    "enable": False
                },
                                {
                    "key": "http_api.request_rate_limit",
                    "value": 51,
                    "enable": True
                },
                {
                    "key": "global_host_tags.sssssaaaabbbaaaaaaccc",
                    "value": "info",
                    "enable": True
                }
            ],
            "input_config": [
                {
                    "input_name": "ddtrace",
                    "input_path": "/usr/local/datakit/conf.d/ddtrace/ddtrace.conf",
                    "key": "inputs.ddtrace[0].customer_tags",
                    "value": ["sink_project", "custom_dd_tagaaasaadddddaasaadd"],
                    "enable": True
                },
                {
                    "input_name": "ddtrace",
                    "input_path": "/usr/local/datakit/conf.d/ddtrace/ddtrace.conf",
                    "key": "inputs.ddtrace[0].customer_tagstttaaaaa111aaaaaaa1bbbcccbbbbsc",
                    "value": ["sink_project", "custom_dd_tagaaaa"],
                    "enable": True
                }
                
            ]
        }
    }
}

MOCK_METADATA_CONFIGS = {
    "message": "",
    "status": 200,
    "data": [
        {
            "cswap-account-0-0": {
                "logging": [
                    {
                        "logType": "access",
                        "logfiles": [
                            "/data/processLog/*process.log"
                        ],
                        "source": "ec2-golang-logging",
                        "service": "cswap-account-0-0"
                    },
                    {
                        "logType": "access",
                        "logfiles": [
                            "/data/processLog/*process.log",
                            "/data/processLog/access/*processaaaaa.log"
                        ],
                        "source": "ec2-golang-logging",
                        "service": "cswap-account-0-0"
                    },
                    {
                        "logType": "access",
                        "logfiles": [
                            "/data/processLog/*process.log"
                        ],
                        "source": "ec2-golang-logging",
                        "service": "cswap-account-0-0",
                        "tags":{
                            "sink_project": "cswap-account-0-0",
                            "service": "cswap-account-0-0"
                        }
                    },
                    {
                        "logType": "metric",
                        "logfiles": [
                            "/data/invokeLog/*invoke.log"
                        ],
                        "source": "ec2-golang-logging",
                        "service": "cswap-account-0-0",
                        "tags":{
                            "sink_project": "cswap-account-0-0",
                            "service": "cswap-account-0-0"
                        }
                    },
                    {
                        "logType": "event",
                        "logfiles": [
                            "/data/probeLog/*probe.log",
                            "/data/probeLog/event/*probe.log"
                        ],
                        "source": "ec2-golang-logging",
                        "service": "cswap-account-0-0"
                    },
                    {
                        "logType": "other",
                        "logfiles": [
                            "/home/app/bon-swap/cswap-account-0-0/log/*",
                            "/home/app/bon-swap/log/*"
                        ],
                        "source": "ec2-golang-logging",
                        "service": "cswap-account-0-0"
                    }
                ],
                "metrics": [
                    {
                        "urls": [
                            "http://127.0.0.1:16888//monitor/prometheus"
                        ],
                        "interval": 60,
                        "source": "ec2-golang-metrics",
                        "measurement_name": "cswap-account-0-0"
                    }
                ],
                "health": []
            }
        },
        {
            "cswap-account-1-0": {
                "logging": [],
                "metrics": [],
                "health": []
            }
        }
    ]
}

def get_server_config(server_ip: str) -> Dict[str, Any]:
    """
    根据服务器IP获取配置信息
    在实际应用中，这里应该查询数据库或配置文件
    """
    # 对于所有IP都返回相同的服务器配置
    return MOCK_SERVER_CONFIGS


def get_metadata_config(server_ip: str) -> Dict[str, Any]:
    """
    根据服务器IP获取元数据配置信息
    在实际应用中，这里应该查询数据库或配置文件
    """
    # 对于所有IP都返回相同的元数据配置
    return MOCK_METADATA_CONFIGS


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


@app.route('/api/v2/cmdb/observation-app-metadata', methods=['POST'])
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
        
        logger.info(f"收到 observation-app-metadata 请求，server_ip: {server_ip}")
        
        # 获取元数据配置信息
        metadata_config = get_metadata_config(server_ip)
        
        logger.info(f"返回元数据配置信息: {json.dumps(metadata_config, ensure_ascii=False)}")
        
        return jsonify(metadata_config)
        
    except Exception as e:
        logger.error(f"observation-app-metadata 接口异常: {str(e)}")
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
            "observation-app-metadata": "/api/v2/cmdb/observation-app-metadata",
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