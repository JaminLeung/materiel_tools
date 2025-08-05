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
    "data": {
        "env": "prod",
        "workspace": "业务工作空间",
        "global_tags": {
            "global_source": {
                "app": "datakit",
                "env": "production",
                "region": "ap-southeast-1",
                "service": "monitoring",
                "team": "ops11112222222222222222222"
            }
        },
        "dataway_url": "https://openway.guance.com",
        "workspace_token": "tkn_3a0052c9f6d3498c8ce9ca0988fd9c82",
        "datakit_config": {
            "enable": True,
            "global_config": [
                {
                    "key": "logging.level",
                    "value": "info",
                    "enable": True
                },
                                {
                    "key": "http_api.request_rate_limit",
                    "value": 50,
                    "enable": True
                },
                {
                    "key": "global_host_tags.sssss",
                    "value": "info111",
                    "enable": True
                }
            ],
            "input_config": [
                {
                    "input_name": "ddtrace",
                    "input_path": "/usr/local/datakit/conf.d/ddtrace/ddtrace.conf",
                    "key": "inputs.ddtrace[0].customer_tagstttaaaaaaaaaaaaaabbabbbb",
                    "value": ["sink_project", "custom_dd_tagaaaabbbbbbsssssaaaaaaaaa"],
                    "enable": True
                },
                {
                    "input_name": "ddtrace",
                    "input_path": "/usr/local/datakit/conf.d/ddtrace/ddtrace.conf",
                    "key": "inputs.ddtrace[0].customer_tagstttaaaaa1111bbbb",
                    "value": ["sink_project", "custom_dd_tagaaaa"],
                    "enable": True
                }
                
            ]
        }
    }
}

MOCK_METADATA_CONFIGS = {
    "data": [{
        "serviceA": {
            "logging": [
                {
                    "logfiles": [
                        "/home/app/bon-gateway-svr/logs/*access_normal.log",
                        "/home/app/bon-gateway-svr/logs/*access_normal11111eeeeeee.log",
                        # "/home/app/bon-gateway-svr/logs/*access_normal22222.log"
                    ],
                    "source": "ec2-java-logging",
                    "service": "bon-gateway-svr",
                    "tags": {
                        "logType": "accewwwwws",
                        "lang": "java",
                        "group_name": "gateway-groupqqqqq"
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
                        "group_name": "gateway-groupaaaa"
                    }
                }
            ],
            "metrics": [
                {
                    "urls": [
                        "http://172.31.16.4:9100/metricsaaaabbbb"
                    ],
                    "source": "ec2-java-metrics",
                    "measurement_name": "bon-gateway-svr",
                    "tags": {
                        "service": "bon-gateway-svraaaaa",
                        "group_name": "gateway-groupdddd",
                        # "group_name111": "gateway-group1111"
                    }
                }
            ],
            "health": [
                {
                    "http_urls": ["http://172.31.16.4:8080/healthnnnn"],
                    "expect_status": 200,
                    "tags": {
                        "service": "bon-gateway-svr",
                        "group_name": "gateway-grouaaaaaaaap",
                        # "group_name1111": "gateway-group1111"
                    }
                }
            ]
        },
        "serviceB": {
            "logging": [],
            "metrics": [],
            "health": []
        }
    }]
    
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
            "global_source": "global_source",
            "env": "env",
            "workspace": "workspace",
            "env111": "env",
            "workspace111": "workspaceaaaaa",
            "env222": "env",
            "workspace2": "workspaceaaaaa",
        },
        "dataway_url": "https://openway.guance.com",
        "workspace_token": "tkn_3a0052c9f6d3498c8ce9ca0988fd9c82",
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