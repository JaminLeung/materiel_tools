#!/bin/bash

# 脚本名称：datakit_install_init.sh
# 作用：下载并执行安装脚本，同时传递环境变量
# 支持新旧两种部署方式

# 全局变量
DEPLOY_VERSION="new"  # 默认使用新版本
INSTALLER_VERSION="1.0.0"       # 安装器版本号
DATAKIT_VERSION=""              # datakit版本号
DATAKIT_ENV=""                  # datakit环境变量
INSTALL_PATH="/usr/local/datakit"  # 默认安装路径


# 显示使用说明
show_usage() {
    echo "用法: $0 [选项] [参数...]"
    echo ""
    echo "选项:"
    echo "  -v, --version <version>    指定部署版本 (legacy|new)"
    echo "  --datakit-version <ver>    指定datakit版本号 (仅新版本有效)"
    echo "  --datakit-env <env>        指定datakit环境变量 (仅新版本有效)"
    echo "  --install-path <path>      指定安装路径 (仅新版本有效)"
    echo "  -h, --help                 显示此帮助信息"
    echo ""
    echo "参数:"
    echo "  旧版本部署 (legacy):"
    echo "    <code> <env> <ops_env> <system>    # 4个必需参数"
    echo "  新版本部署 (new):"
    echo "    [参数...]                         # 参数数量灵活"
    echo ""
    echo "示例:"
    echo "  $0 code env ops_env system                                    # 使用旧版本部署（默认）"
    echo "  $0 --version legacy code env ops_env system                   # 明确指定旧版本"
    echo "  $0 --version new                                              # 使用新版本部署（默认版本）"
    echo "  $0 --version new --datakit-version 1.5.0                     # 使用新版本部署指定版本"
    echo "  $0 --version new --datakit-env production                     # 指定datakit环境"
    echo "  $0 --version new --install-path /opt/datakit                  # 指定安装路径"
    echo "  $0 --version new --datakit-version 1.5.0 --datakit-env production --install-path /opt/datakit"
    echo "  $0 --help                                                     # 显示帮助"
}

# 设置全局环境变量（仅用于旧版本）
set_global_env() {
    local code="$1"
    local env="$2"
    local ops_env="$3"
    local system="$4"

    # 打印日志
    echo "========= 参数接收开始 ========="
    echo "Code: $code"
    echo "Environment: $env"
    echo "Ops Environment: $ops_env"
    echo "System: $system"
    echo "Deploy Version: $DEPLOY_VERSION"
    echo "========= 参数接收结束 ========="

    # 设置环境变量
    export ACCOUNT_NAME="$code"
    export GLOBAL_ENV="$env"
    export GLOBAL_OPS_ENV="$ops_env"
    export GLOBAL_SYSTEM="$system"

    echo "已设置以下环境变量："
    echo "ACCOUNT_NAME=$ACCOUNT_NAME"
    echo "GLOBAL_ENV=$GLOBAL_ENV"
    echo "GLOBAL_OPS_ENV=$GLOBAL_OPS_ENV"
    echo "GLOBAL_SYSTEM=$GLOBAL_SYSTEM"
}

# 初始化安装环境函数
init_install_env() {
    local install_type="$1"

    # 设置默认安装类型
    if [[ -z "$install_type" ]]; then
        install_type="unknown"
    fi

    echo "========= 开始初始化安装环境 ========="
    echo "安装类型: $install_type"
    echo "安装路径: $INSTALL_PATH"

    # 检查datakit进程是否存在
    if pgrep -f "datakit" > /dev/null; then
        echo "datakit进程已存在，进行停止datakit操作"

        # 停止datakit进程
        if systemctl stop datakit; then
            echo "datakit进程已停止"
        else
            echo "datakit进程停止失败，请手动停止"
        fi
    else
        echo "datakit进程不存在，跳过停止操作"
    fi

    # 备份datakit配置文件
    if [ -d "/usr/local/datakit/conf.d" ]; then
        echo "备份datakit配置文件"
        local backup_name="datakit_${install_type}_backup_$(date +%Y%m%d%H%M%S)"
        mv "/usr/local/datakit/conf.d" "/tmp/$backup_name"
        echo "配置文件已备份到: /tmp/$backup_name"
    else
        echo "datakit配置文件不存在，跳过备份"
    fi

    # 删除相关的定时任务
    local task_pattern="app_init\.sh|app-init\.sh|datakit_auto_install\.sh"

    # 检查是否存在相关定时任务
    if crontab -l 2>/dev/null | grep -q -E "$task_pattern"; then
        echo "发现相关定时任务，正在删除..."
        crontab -l 2>/dev/null | grep -v -E "$task_pattern" | crontab -
        echo "定时任务删除完成"
    else
        echo "未发现相关定时任务，跳过删除"
    fi

    echo "========= 初始化安装环境完成 ========="
}


# 旧版本部署方式
deploy_legacy() {

    local install_script_url="https://static-api.pre-guance.houtai.io/guance/datakit/install.sh"
    echo "========= 开始旧版本部署 ========="

    # 初始化安装环境（停止进程、备份配置、清理定时任务）
    init_install_env "legacy"


    # 下载安装脚本
    echo "正在下载安装脚本：$INSTALL_SCRIPT_URL..."
    wget -q "$INSTALL_SCRIPT_URL" -O install.sh

    # 检查下载是否成功
    if [[ $? -ne 0 ]]; then
        echo "错误: 无法下载安装脚本，请检查网络连接或 URL 是否正确。"
        return 2
    fi

    echo "安装脚本下载完成。"

    # 修改脚本权限
    chmod +x install.sh

    # 执行安装脚本
    echo "正在执行安装脚本..."
    ./install.sh

    # 检查 install.sh 是否执行成功
    if [[ $? -eq 0 ]]; then
        echo "旧版本安装成功！"
        return 0
    else
        echo "旧版本安装失败，请检查日志了解详情。"
        return 3
    fi
}



# 新版本部署方式
deploy_new() {
    echo "========= 开始新版本部署 ========="

    # local install_script_url="https://static-api.pre-guance.houtai.io/guance/datakit/datakit-automation-all_${INSTALLER_VERSION}.tgz"
    local install_script_url="https://guance-south.oss-cn-guangzhou.aliyuncs.com/liangjieming/bingx-prod/datakit-automation-all_${INSTALLER_VERSION}.tgz"




    # 进入安装路径
    cd $INSTALL_PATH

    # 显示部署信息
    echo "安装脚本URL: $install_script_url"
    echo "安装路径: $INSTALL_PATH"

    # 初始化安装环境（停止进程、备份配置、清理定时任务）
    init_install_env "new"

    # 显示版本和环境信息
    if [[ -n "$DATAKIT_VERSION" ]]; then
        echo "指定安装 datakit 版本: $DATAKIT_VERSION"
    else
        echo "使用默认 datakit 版本"
    fi

    if [[ -n "$DATAKIT_ENV" ]]; then
        echo "指定 datakit 环境: $DATAKIT_ENV"
    else
        echo "使用默认 datakit 环境"
    fi

    # 下载安装包
    echo "正在下载安装包：$install_script_url..."
    wget -q "$install_script_url" -O $INSTALL_PATH/datakit-automation-all_${INSTALLER_VERSION}.tgz


    # 解压安装包
    echo "正在解压安装包：$INSTALL_PATH/datakit-automation-all_${INSTALLER_VERSION}.tgz..."
    tar -xf $INSTALL_PATH/datakit-automation-all_${INSTALLER_VERSION}.tgz -C $INSTALL_PATH

    # 进入安装包目录
    cd $INSTALL_PATH/datakit-automation

    # 执行安装脚本
    echo "正在执行安装脚本..."
    DATAKIT_ENV=$DATAKIT_ENV ./datakit_auto_installer.sh existing-install

    # 检查安装是否成功
    if [[ $? -eq 0 ]]; then
        echo "新版本安装成功！"
        return 0
    else
        echo "新版本安装失败，请检查日志了解详情。"
        return 3
    fi

}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                if [[ -n "$2" && "$2" != -* ]]; then
                    DEPLOY_VERSION="$2"
                    shift 2
                else
                    echo "错误: --version 需要一个参数"
                    show_usage
                    exit 1
                fi
                ;;
            --datakit-version)
                if [[ -n "$2" && "$2" != -* ]]; then
                    DATAKIT_VERSION="$2"
                    shift 2
                else
                    echo "错误: --datakit-version 需要一个参数"
                    show_usage
                    exit 1
                fi
                ;;
            --datakit-env)
                if [[ -n "$2" && "$2" != -* ]]; then
                    DATAKIT_ENV="$2"
                    shift 2
                else
                    echo "错误: --datakit-env 需要一个参数"
                    show_usage
                    exit 1
                fi
                ;;
            --install-path)
                if [[ -n "$2" && "$2" != -* ]]; then
                    INSTALL_PATH="$2"
                    shift 2
                else
                    echo "错误: --install-path 需要一个参数"
                    show_usage
                    exit 1
                fi
                ;;

            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo "错误: 未知选项 $1"
                show_usage
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done

    # 根据版本选择部署方式
    case "$DEPLOY_VERSION" in
        legacy)
            # 旧版本需要4个必需参数
            if [[ $# -ne 4 ]]; then
                echo "错误: 旧版本部署需要提供4个必需参数"
                show_usage
                exit 1
            fi
            # 设置环境变量
            set_global_env "$1" "$2" "$3" "$4"
            deploy_legacy
            exit_code=$?
            ;;
        new)
            # 新版本不需要手动设置环境变量，参数数量可以灵活
            echo "新版本部署：参数数量检查已跳过"

            # 验证版本号格式（如果指定了版本号）
            if [[ -n "$DATAKIT_VERSION" ]]; then
                if [[ ! "$DATAKIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo "错误: 无效的版本号格式 '$DATAKIT_VERSION'，应为 x.y.z 格式"
                    exit 1
                fi
            fi

            # 验证环境变量（如果指定了环境变量）
            if [[ -n "$DATAKIT_ENV" ]]; then
                # 这里可以添加环境变量的验证逻辑
                # 例如：检查是否为有效的环境值（production, staging, development等）
                echo "指定 datakit 环境: $DATAKIT_ENV"
            fi

            # 校验是否为合法路径格式
            if [[ ! "$INSTALL_PATH" =~ ^/.*$ ]]; then
                echo "错误: 安装路径格式不合法，应为绝对路径"
                exit 1
            fi

            # 检查安装路径是否存在
            if [[ ! -d "$INSTALL_PATH" ]]; then
                echo "安装路径不存在，创建安装路径"
                mkdir -p "$INSTALL_PATH"
            fi



            deploy_new
            exit_code=$?
            ;;
        *)
            echo "错误: 不支持的部署版本 '$DEPLOY_VERSION'"
            echo "支持的版本: legacy, new"
            exit 1
            ;;
    esac

    exit $exit_code
}

# 执行主函数
main "$@"