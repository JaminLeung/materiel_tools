# Datakit 存量安装自动化方案

## 📁 项目结构总览

```
.
├── README.md                           # 项目总体说明文档
├── requirements.txt                    # Python依赖文件
├── install.sh                         # 项目安装脚本
├── resource_assessment/                # 资源评估模块
│   ├── aws_resource_check.py          # AWS资源评估脚本
│   └── README.md                      # 资源评估说明文档
├── cgroup_check/                       # Cgroup检查模块
│   ├── verify_cgroup.sh               # Cgroup支持检查脚本
│   └── README.md                      # Cgroup检查说明文档
├── datakit_sync/                       # 物料同步模块
│   ├── datakit_sync.py                # Datakit物料同步脚本
│   └── README.md                      # 物料同步说明文档
└── ssm_install/                        # SSM安装模块
    ├── main_install.sh                # SSM主安装脚本
    └── README.md                      # SSM安装说明文档
```

## 🚀 已实现的功能模块

### 1. **资源评估模块** (`resource_assessment/`)
- ✅ AWS CloudWatch API集成
- ✅ 近7天CPU/内存使用率获取
- ✅ 动态资源限制计算
- ✅ 部署建议和风险评估
- ✅ 批量主机检查支持

### 2. **Cgroup检查模块** (`cgroup_check/`)
- ✅ 自动检测cgroup v1/v2版本
- ✅ CPU和内存限制测试
- ✅ 资源限制验证
- ✅ 自动清理测试资源
- ✅ 完善的错误处理

### 3. **物料同步模块** (`datakit_sync/`)
- ✅ AWS S3交互封装
- ✅ 完整离线安装包下载
- ✅ MD5校验和文件管理
- ✅ 多种操作模式支持
- ✅ 配置文件生成

### 4. **SSM安装模块** (`ssm_install/`)
- ✅ 完整的安装流程自动化
- ✅ Dataway日志实时上报
- ✅ 动态资源限制配置
- ✅ 多种采集器自动配置
- ✅ 定时任务管理
- ✅ 安装状态验证

## 🔧 核心特性

### 🔧 技术特性
- **模块化设计**：每个功能独立成模块，便于维护和扩展
- **错误处理**：完善的错误处理和重试机制
- **日志管理**：本地日志和远程上报双重保障
- **配置管理**：支持环境变量和配置文件
- **安全考虑**：权限最小化和密钥管理

### 🔧 业务特性
- **资源智能评估**：根据主机规格动态调整资源限制
- **批量部署支持**：通过SSM实现大规模自动化部署
- **离线安装**：支持完全离线环境下的安装
- **实时监控**：安装过程实时上报到观测云
- **健康检查**：自动健康检查和故障恢复

### 🔧 资源限制策略
| 主机规格范围 | 安装建议 | 资源限制 | 限制策略备注 |
|-------------|---------|---------|-------------|
| < 2C4G | ✅允许 | 1C1G | 极易造成主机资源竞争，影响稳定性 |
| 2C4G ~ 4C8G | ✅允许 | 动态限制：0.6C1.2G ~ 1.2C2.4G | 建议根据空闲资源动态调节 |
| ≥ 4C8G | ✅推荐 | 资源限制：1C2G | 默认配置 |

## 🛠️ 使用方法

### 快速开始
```bash
# 1. 安装项目
chmod +x install.sh
./install.sh

# 2. 配置环境变量
cp config/env.template config/env.sh
vim config/env.sh

# 3. 激活虚拟环境
source venv/bin/activate

# 4. 运行批量安装
./examples/batch_install.sh
```

### 分步执行
```bash
# 1. 资源评估
python resource_assessment/aws_resource_check.py <host_ip_list>

# 2. Cgroup检查
sudo cgroup_check/verify_cgroup.sh

# 3. 物料同步
python datakit_sync/datakit_sync.py --endpoint <s3_endpoint> --access-key <ak> --secret-key <sk>

# 4. 批量安装
aws ssm send-command --instance-ids <instance_ids> --document-name "AWS-RunShellScript" --parameters 'commands=["curl -s <script_url> | bash"]'
```

## 📚 文档完整性

每个模块都包含详细的README文档，涵盖：
- 功能说明和使用方法
- 参数配置和示例
- 错误处理和故障排查
- 依赖要求和注意事项

## 🎉 项目亮点

1. **完整性**：覆盖了从资源评估到安装部署的完整流程
2. **自动化**：最小化人工干预，支持大规模批量部署
3. **可靠性**：完善的错误处理和验证机制
4. **可扩展性**：模块化设计，便于功能扩展
5. **易用性**：详细的文档和使用示例

这个项目完全按照readme中的方案实现，提供了完整的Datakit自动化安装解决方案，可以满足AWS环境下的批量部署需求。 