# 单元测试模块

本目录包含 Datakit 自动化安装工具的单元测试。

## 📁 目录结构

```
tests/
├── README.md                    # 测试说明文档
├── run_tests.sh                 # 测试运行器
├── test_utils.sh                # 测试工具函数
├── core/                        # 核心模块测试
│   ├── test_utils.sh            # 工具函数测试
│   ├── test_logging.sh          # 日志系统测试
│   ├── test_validation.sh       # 验证系统测试
│   └── test_initialize.sh       # 初始化系统测试
├── mocks/                       # 模拟数据
│   ├── mock_config.sh           # 模拟配置
│   └── mock_environment.sh      # 模拟环境
└── results/                     # 测试结果
    ├── test_reports/            # 测试报告
    └── coverage/                # 覆盖率报告
```

## 🚀 快速开始

### 运行所有测试
```bash
./tests/run_tests.sh
```

### 运行特定模块测试
```bash
./tests/run_tests.sh core
./tests/run_tests.sh core/utils
./tests/run_tests.sh core/logging
```

### 运行单个测试文件
```bash
./tests/core/test_utils.sh
./tests/core/test_logging.sh
```
