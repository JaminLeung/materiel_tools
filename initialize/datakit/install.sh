#! /bin/bash
# 初始化安装脚本
# 安装 datakit 并配置默认采集器 (aws)
# 获取业务可观测配置采集脚本并添加定时任务    app_init.sh
# 获取更新脚本并添加定时任务               upgrade_datakit.sh



######### customer config  start  #########

if [[ -z "$GLOBAL_CODE" || -z "$GLOBAL_ENV" ]]; then
    echo "Error: code and env must not be empty."
#     exit 1
fi

echo "Code: $GLOBAL_CODE"
echo "env: $GLOBAL_ENV"


GLOBAL_CODE="$(echo "$GLOBAL_CODE" | tr '[:upper:]' '[:lower:]')"
GLOBAL_ENV="$(echo "$GLOBAL_ENV" | tr '[:upper:]' '[:lower:]')"
# CUSOMER_SYSTEM="$(echo "$system" | tr '[:upper:]' '[:lower:]')"
# CUSOMER_OPS_ENV="$(echo "$ops_env" | tr '[:upper:]' '[:lower:]')"

WORKSPACE_URL=""
WORKSPACE_TOKEN=""
DK_DEF_INPUTS="${DK_DEF_INPUTS:-cpu,disk,diskio,mem,swap,system,hostobject,net,host_processes,container,dk,ebpf}"
DK_GLOBAL_HOST_TAGS="global_source=ec2,host=__datakit_hostname,host_ip=__datakit_ip,global_code=$GLOBAL_CODE,global_env=$GLOBAL_ENV"
DK_DATAWAY=''

## 是否安装 prom 配置
DK_INSTALL_PROM="${DK_INSTALL_PROM:-true}"
## 是否安装 pushgateway 配置
DK_INSTALL_PUSHGATEWAY="${DK_INSTALL_PUSHGATEWAY:-true}"
## 是否安装 otel 配置
DK_INSTALL_OTEL="${DK_INSTALL_OTEL:-true}"
## 是否安装 logging 配置
DK_INSTALL_LOGGING="${DK_INSTALL_LOGGING:-true}"

##  配置监听端口
DK_HTTP_LISTEN="${DK_HTTP_LISTEN:-0.0.0.0}"


## 是否安装 node_exporter
DK_INSTALL_NODE_EXPORTER="${DK_INSTALL_NODE_EXPORTER:-true}"
## 是否安装 dca
DK_DCA_ENABLE="${DK_DCA_ENABLE:-false}"

## 云厂商   
DK_CLOUD_PROVIDER="${DK_CLOUD_PROVIDER:-aws}"

## 是否安装 dca-agent
# DK_DCA_AGENT_ENABLE="${DK_DCA_AGENT_ENABLE:-true}"
# ## dca 白名单
# DK_DCA_WEBSOCKET_SERVER="${DK_DCA_WEBSOCKET_SERVER:-ws://dca.bingbon.dataflux.cn/ws}"

DK_HTTP_PUBLIC_APIS="${DK_HTTP_PUBLIC_APIS:-/v1/pushgateway,/otel/v1/trace,/metrics,/v1/write/rum}"


if [[ "$GLOBAL_CODE" == "ox" && "$GLOBAL_ENV" == "ops" ]]; then
    DK_DATAWAY="https://dataway.pre-guance.houtai.io?token=tkn_a9c417771c1349f4a15f5031806b03f5"
	# DK_DATAWAY="http://dataway.bingbon.dataflux.cn?token=tkn_7b01611e811d43d0bf2d0cea93e06b78"

elif [[ "$GLOBAL_CODE" == "ox" && "$GLOBAL_ENV" == "bigdata" ]]; then
    DK_DATAWAY="https://dataway.pre-guance.houtai.io?token=tkn_598a4f64d5e84b8b939a54a32c25e3d3"

elif [[ "$GLOBAL_CODE" == "ox" && "$GLOBAL_ENV" != "ops" ]]; then
    DK_DATAWAY="https://dataway.pre-guance.houtai.io?token=tkn_48c619fd1aee4d08abd2e2405e604cb5"
	# DK_DATAWAY="http://dataway.bingbon.dataflux.cn?token=tkn_cc5ee67b5a10451da643d2e9b7613c8c"

else
    echo "Invalid code or env values."
#     exit 1
fi

# Print the determined workspace URL
echo "Workspace URL: $workspace"


installer_base_url="https://static-api.pre-guance.houtai.io/guance/datakit"
DK_INSTALLER_BASE_URL="https://static-api.pre-guance.houtai.io/guance/datakit"


######### customer config end #########

errorf() {
  msg=$1
  shift
  printf "${RED}[E] $msg ${CLR}\n" "$@" >&2
}



arch=
case $(uname -m) in

	"x86_64")
		arch="amd64"
		;;

	"i386" | "i686")
		arch="386"
		;;

	"aarch64")
		arch="arm64"
		;;

	"arm" | "armv7l")
		arch="arm"
		;;

	"arm64")
		arch="arm64"
		;;

	*)
		# shellcheck disable=SC2059
		printf "${RED}[E] Unsupported arch $(uname -m) ${CLR}\n"
		exit 1
		;;
esac

os="linux"

if [[ "$OSTYPE" == "darwin"* ]]; then
	if [[ $arch != "amd64" ]] && [[ $arch != "arm64" ]]; then # Darwin only support amd64 and arm64
		# shellcheck disable=SC2059
		printf "${RED}[E] Darwin only support amd64/arm64.${CLR}\n"
		exit 1;
	fi

	os="darwin"

	# NOTE: under darwin, for arm64 and amd64, both use amd64
	arch="amd64"
fi

printf "* Detect OS/Arch ${os}/${arch}\n"

cmd=()


######### node_exporter install start #########

# 添加 node_exporter 安装逻辑
install_node_exporter() {
    printf "* Installing node_exporter...\n"
    
    # 设置版本和架构
    NODE_EXPORTER_VERSION="1.8.2"
    NODE_EXPORTER_DIR="/usr/local/node_exporter"
    
    # 根据系统架构选择下载文件
    case $arch in
        "amd64")
            NODE_EXPORTER_ARCH="amd64"
            ;;
        "386")
            NODE_EXPORTER_ARCH="386"
            ;;
        "arm64")
            NODE_EXPORTER_ARCH="arm64"
            ;;
        "arm")
            NODE_EXPORTER_ARCH="armv7"
            ;;
        *)
            errorf "Unsupported architecture for node_exporter: %s" "$arch"
            return 1
            ;;
    esac
    
    # 构建下载URL
    DOWNLOAD_URL="${DK_INSTALLER_BASE_URL}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}.tar.gz"
    TARBALL="/tmp/node_exporter.tar.gz"
    
    # 下载node_exporter
    if [ -n "$proxy" ]; then
        curl $verbose_mode -x "$proxy" --fail --progress-bar -L "$DOWNLOAD_URL" -o "$TARBALL"
    else
        curl $verbose_mode --fail --progress-bar -L "$DOWNLOAD_URL" -o "$TARBALL"
    fi
    
    # 创建安装目录
    $sudo_cmd mkdir -p $NODE_EXPORTER_DIR
    
    # 解压安装
    $sudo_cmd tar -xzf "$TARBALL" -C $NODE_EXPORTER_DIR
    
    # 创建服务文件
    cat << EOF | $sudo_cmd tee /lib/systemd/system/node_exporter.service > /dev/null
[Unit]
Description=node_exporter
Documentation=https://prometheus.io/
After=network.target

[Service]
Type=simple
ExecStart=$NODE_EXPORTER_DIR/node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}/node_exporter 
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载服务并启动
    $sudo_cmd systemctl daemon-reload
    $sudo_cmd systemctl enable node_exporter
    $sudo_cmd systemctl start node_exporter
    
    # 清理临时文件
    rm -f "$TARBALL"
    
    printf "* node_exporter installation completed\n"
}




# 在原有命令行参数中添加 node_exporter 选项
if [  "$DK_INSTALL_NODE_EXPORTER" = "true" ]; then
    install_node_exporter
    printf "* Set install_node_exporter => ON \n"
fi


######### node_exporter install start #########


updateHosts() {
	for n in "$@"
	do
		if [ "$n" != "$1" ]; then
			# echo $n
			ip_address=$1
			host_name=$n
			# find existing instances in the host file and save the line numbers
			matches_in_hosts="$(grep -n "$host_name" /etc/hosts | cut -f1 -d:)"
			host_entry="${ip_address} ${host_name}"

			if [ -n "$matches_in_hosts" ]
			then
				# iterate over the line numbers on which matches were found
				for line_number in $matches_in_hosts; do
					# replace the text of each line with the desired host entry
					if [[ "$OSTYPE" == "darwin"* ]]; then
						$sudo_cmd sed -i '' "${line_number}s/.*/${host_entry} /" /etc/hosts
					else
						$sudo_cmd sed -i "${line_number}s/.*/${host_entry} /" /etc/hosts
					fi
				done
			else
				echo "$host_entry" | $sudo_cmd tee -a /etc/hosts > /dev/null
			fi
		fi
	done
}

set -e



sudo_cmd=''
if type sudo >/dev/null 2>&1; then
	# detect root user
	if [ "$UID" != "0" ]; then
		sudo_cmd='sudo'
	fi
fi

##################
# colors
##################
RED="\033[31m"
CLR="\033[0m"


##################
# Set Variables
##################

# Detect OS/Arch







if [ -n "$DK_INSTALLER_BASE_URL" ]; then
	installer_base_url=$DK_INSTALLER_BASE_URL
	cmd+=("--installer_base_url=$DK_INSTALLER_BASE_URL")
	printf "* Set installer_base_url => $DK_INSTALLER_BASE_URL\n"
fi

installer_file="installer-${os}-${arch}"
printf "* Detect installer ${installer_file}\n"

installer_url="${installer_base_url}/${installer_file}"
installer=/tmp/dk-installer

verbose_mode=
if [ -n "$DK_VERBOSE" ]; then
	verbose_mode="-v"
	printf "* Set verbose_mode => ON\n"
fi

if [ -n "$DK_DATAWAY" ]; then
	cmd+=("--dataway=$DK_DATAWAY")
	printf "* Set dataway => $DK_DATAWAY\n"
fi

if [ -n "$DK_LITE" ]; then
	cmd+=("--lite=$DK_LITE")
	printf "* Set lite => ON\n"
fi

if [ -n "$DK_ELINKER" ]; then
	cmd+=("--elinker=$DK_ELINKER")
	printf "* Set elinker => $DK_ELINKER\n"
fi

if [ -n "$DK_APM_INSTRUMENTATION_ENABLED" ]; then
	cmd+=("--apm-instrumentation-enabled=$DK_APM_INSTRUMENTATION_ENABLED")
	printf "* Set apm-instrumentation-enabled => $DK_APM_INSTRUMENTATION_ENABLED\n"
fi

if [ -n "$DK_SINKER_GLOBAL_CUSTOMER_KEYS" ]; then
	cmd+=("--sinker-global-customer-keys=$DK_SINKER_GLOBAL_CUSTOMER_KEYS")
	printf "* Set global_customer_keys => ${DK_SINKER_GLOBAL_CUSTOMER_KEYS}\n"
fi

if [ -n "$DK_DATAWAY_ENABLE_SINKER" ]; then
	cmd+=("--enable-dataway-sinker=1")
	printf "* Set dataway_sinker => ON\n"
fi

upgrade=
if [ -n "$DK_UPGRADE" ]; then
	upgrade=$DK_UPGRADE
	cmd+=("--upgrade")
	printf "* Set upgrade => ON\n"
fi

if [ -n "$DK_UPGRADE_MANAGER" ]; then
	cmd+=("--upgrade-manager=$DK_UPGRADE_MANAGER")
	printf "* Set upgrade_manager => ON\n"
fi

if [ -n "$DK_UPGRADE_IP_WHITELIST" ]; then
	cmd+=("--upgrade-ip-whitelist=$DK_UPGRADE_IP_WHITELIST")
	printf "* Set upgrade_ip_whitelist => ${DK_UPGRADE_IP_WHITELIST} \n"
fi

if [ -n "$DK_UPGRADE_LISTEN" ]; then
	cmd+=("--upgrade-listen=$DK_UPGRADE_LISTEN")
	printf "* Set upgrade_listen => ${DK_UPGRADE_LISTEN} \n"
fi

if [ -n "$DK_DEF_INPUTS" ]; then
	cmd+=("--enable-inputs=$DK_DEF_INPUTS")
	printf "* Set def_inputs => ${DK_DEF_INPUTS} \n"
fi

if [ -n "$DK_INSTALL_RUM_SYMBOL_TOOLS" ]; then
	cmd+=("--install-rum-symbol-tools=1")
	printf "* Set install_rum_symbol_tools => ON\n"
fi

if [ -n "$DK_HTTP_PUBLIC_APIS" ]; then
	cmd+=("--http-public-apis=$DK_HTTP_PUBLIC_APIS")
	printf "* Set http_public_apis => ${DK_HTTP_PUBLIC_APIS} \n"
fi

if [ -n "$DK_GLOBAL_HOST_TAGS" ]; then
	cmd+=("--global-host-tags=$DK_GLOBAL_HOST_TAGS")
	printf "* Set global_host_tags => ${DK_GLOBAL_HOST_TAGS} \n"
fi

if [ -n "$DK_GLOBAL_ELECTION_TAGS" ]; then
	cmd+=("--global-election-tags=$DK_GLOBAL_ELECTION_TAGS")
	printf "* Set global_election_tags => ${DK_GLOBAL_ELECTION_TAGS} \n"
fi

if [ -n "$DK_CLOUD_PROVIDER" ]; then
	cmd+=("--cloud-provider=$DK_CLOUD_PROVIDER")
	printf "* Set cloud_provider => ${DK_CLOUD_PROVIDER} \n"
fi

if [ -n "$DK_NAMESPACE" ]; then
	cmd+=("--namespace=$DK_NAMESPACE")
	printf "* Set namespace => ${DK_NAMESPACE} \n"
fi

if [ -n "$DK_HTTP_LISTEN" ]; then
	cmd+=("--listen=$DK_HTTP_LISTEN")
	printf "* Set http_listen => ${DK_HTTP_LISTEN} \n"
fi

if [ -n "$DK_HTTP_PORT" ]; then
	cmd+=("--port=$DK_HTTP_PORT")
	printf "* Set http_port => ${DK_HTTP_PORT} \n"
fi

if [ -n "$DK_INSTALL_ONLY" ]; then
	cmd+=("--install-only=1")
	printf "* Set install_only => ON \n"
fi

if [ -n "$DK_DCA_WEBSOCKET_SERVER" ]; then
	cmd+=("--dca-websocket-server=$DK_DCA_WEBSOCKET_SERVER")
	printf "* Set dca_websocket_server => ${DK_DCA_WEBSOCKET_SERVER} \n"
fi

if [ -n "$DK_DCA_ENABLE" ]; then
	cmd+=("--dca-enable=$DK_DCA_ENABLE")
	printf "* Set dca_enable => ON \n"
fi

if [ -n "$DK_PPROF_LISTEN" ]; then
	cmd+=("--pprof-listen=$DK_PPROF_LISTEN")
	printf "* Set pprof_listen => ${DK_PPROF_LISTEN} \n"
fi

if [ -n "$DK_INSTALL_IPDB" ]; then
	cmd+=("--ipdb-type=$DK_INSTALL_IPDB")
	printf "* Set ipdb_type => ${DK_INSTALL_IPDB} \n"
fi

if [ -n "$DK_INSTALL_EXTERNALS" ]; then
	cmd+=("--install-externals=$DK_INSTALL_EXTERNALS")
	printf "* Set install_externals => ON \n"
fi


if [ -n "$HTTP_PROXY" ]; then
	proxy=$HTTP_PROXY
	printf "* Set HTTP proxy => $HTTP_PROXY \n"
fi

if [ -n "$HTTPS_PROXY" ]; then
	proxy=$HTTPS_PROXY
	printf "* Set HTTPS proxy => $HTTPS_PROXY \n"
fi

# check nginx proxy
proxy_type=""
if [ -n "$DK_PROXY_TYPE" ]; then
	proxy_type=$DK_PROXY_TYPE
	proxy_type=$(echo "$proxy_type" | tr '[:upper:]' '[:lower:]') # => lowercase
	cmd+=("--proxy-type=$proxy_type")
	printf "* Set proxy type => $proxy_type\n"

	if [ "$proxy_type" = "nginx" ]; then
		# env DK_NGINX_IP has the highest priority on proxy level
		if [ -n "$DK_NGINX_IP" ]; then
			proxy=$DK_NGINX_IP
			if [ "$proxy" != "" ]; then
				printf "* Set nginx proxy => $DK_NGINX_IP \n"   

				for i in $domain; do
					updateHosts "$proxy" "$i"
				done
			fi
			proxy=""
		fi
	fi
fi

if [ -n "$proxy" ]; then
	cmd+=("--proxy=$proxy")
fi

if [ -n "$DK_HOSTNAME" ]; then
	cmd+=("--env_hostname=$DK_HOSTNAME")
	printf "* Set env_hostname => $DK_HOSTNAME \n"
fi

if [ -n "$DK_LIMIT_CPUMAX" ]; then
	cmd+=("--limit-cpumax=$DK_LIMIT_CPUMAX")
	printf "* Set limit_cpumax => $DK_LIMIT_CPUMAX \n"
fi

if [ -n "$DK_LIMIT_MEMMAX" ]; then
	cmd+=("--limit-memmax=$DK_LIMIT_MEMMAX")
	printf "* Set limit_memmax => $DK_LIMIT_MEMMAX \n"
fi

if [ -n "$DK_LIMIT_DISABLED" ]; then
	cmd+=("--limit-disabled=1")
	printf "* Set limit_disabled => ON \n"
fi

if [ -n "$DK_INSTALL_LOG" ]; then
	cmd+=("--install-log=$DK_INSTALL_LOG")
	printf "* Set install_log => $DK_INSTALL_LOG \n"
fi

if [ -n "$DK_CONFD_BACKEND" ]; then
	cmd+=("--confd-backend=$DK_CONFD_BACKEND")
fi

if [ -n "$DK_CONFD_BASIC_AUTH" ]; then
	cmd+=("--confd-basic-auth=$DK_CONFD_BASIC_AUTH")
fi

if [ -n "$DK_CONFD_CLIENT_CA_KEYS" ]; then
	cmd+=("--confd-client-ca-keys=$DK_CONFD_CLIENT_CA_KEYS")
fi

if [ -n "$DK_CONFD_CLIENT_CERT" ]; then
	cmd+=("--confd-client-cert=$DK_CONFD_CLIENT_CERT")
fi

if [ -n "$DK_CONFD_CLIENT_KEY" ]; then
	cmd+=("--confd-client-key=$DK_CONFD_CLIENT_KEY")
fi

if [ -n "$DK_CONFD_BACKEND_NODES" ]; then
	cmd+=("--confd-backend-nodes=$DK_CONFD_BACKEND_NODES")
fi

if [ -n "$DK_CONFD_PASSWORD" ]; then
	cmd+=("--confd-password=$DK_CONFD_PASSWORD")
fi

if [ -n "$DK_CONFD_SCHEME" ]; then
	cmd+=("--confd-scheme=$DK_CONFD_SCHEME")
fi

if [ -n "$DK_CONFD_SEPARATOR" ]; then
	cmd+=("--confd-separator=$DK_CONFD_SEPARATOR")
fi

if [ -n "$DK_CONFD_USERNAME" ]; then
	cmd+=("--confd-username=$DK_CONFD_USERNAME")
fi

if [ -n "$DK_CONFD_ACCESS_KEY" ]; then
	cmd+=("--confd-access-key=$DK_CONFD_ACCESS_KEY")
fi

if [ -n "$DK_CONFD_SECRET_KEY" ]; then
	cmd+=("--confd-secret-key=$DK_CONFD_SECRET_KEY")
fi

if [ -n "$DK_CONFD_CIRCLE_INTERVAL" ]; then
	cmd+=("--confd-circle-interval=$DK_CONFD_CIRCLE_INTERVAL")
fi

if [ -n "$DK_CONFD_CONFD_NAMESPACE" ]; then
	cmd+=("--confd-confd-namespace=$DK_CONFD_CONFD_NAMESPACE")
fi

if [ -n "$DK_CONFD_PIPELINE_NAMESPACE" ]; then
	cmd+=("--confd-pipeline-namespace=$DK_CONFD_PIPELINE_NAMESPACE")
fi

if [ -n "$DK_CONFD_REGION" ]; then
	cmd+=("--confd-region=$DK_CONFD_REGION")
fi

if [ -n "$DK_GIT_URL" ]; then
	cmd+=("--git-url=$DK_GIT_URL")
	printf "* Set git_url => $DK_GIT_URL \n"
fi

if [ -n "$DK_GIT_KEY_PATH" ]; then
	cmd+=("--git-key-path=$DK_GIT_KEY_PATH")
	printf "* Set git_key_path => $DK_GIT_KEY_PATH \n"
fi

if [ -n "$DK_GIT_KEY_PW" ]; then
	cmd+=("--git-key-pw=$DK_GIT_KEY_PW")
	printf "* Set git_key_pw => $DK_GIT_KEY_PW \n"
fi

if [ -n "$DK_GIT_BRANCH" ]; then
	cmd+=("--git-branch=$DK_GIT_BRANCH")
	printf "* Set git_branch => $DK_GIT_BRANCH \n"
fi

if [ -n "$DK_GIT_INTERVAL" ]; then
	cmd+=("--git-pull-interval=$DK_GIT_INTERVAL")
	printf "* Set git_pull_interval => $DK_GIT_INTERVAL \n"
fi

if [ -n "$DK_ENABLE_ELECTION" ]; then
	cmd+=("--enable-election=$DK_ENABLE_ELECTION")
	printf "* Set enable_election => $DK_ENABLE_ELECTION \n"
fi

if [ -n "$DK_RUM_ORIGIN_IP_HEADER" ]; then
	cmd+=("--rum-origin-ip-header=$DK_RUM_ORIGIN_IP_HEADER")
	printf "* Set rum_origin_ip_header => $DK_RUM_ORIGIN_IP_HEADER \n"
fi

if [ -n "$DK_DISABLE_404PAGE" ]; then
	cmd+=("--disable-404page=$DK_DISABLE_404PAGE")
	printf "* Set disable_404page => $DK_DISABLE_404PAGE \n"
fi

if [ -n "$DK_LOG_LEVEL" ]; then
	cmd+=("--log-level=$DK_LOG_LEVEL")
	printf "* Set log_level => $DK_LOG_LEVEL \n"
fi

if [ -n "$DK_LOG" ]; then
	cmd+=("--log=$DK_LOG")
	printf "* Set log => $DK_LOG \n"
fi

if [ -n "$DK_GIN_LOG" ]; then
	cmd+=("--gin-log=$DK_GIN_LOG")
	printf "* Set gin_log => $DK_GIN_LOG \n"
fi

if [ -n "$DK_USER_NAME" ]; then
	cmd+=("--user-name=$DK_USER_NAME")
	printf "* Set user_name => $DK_USER_NAME \n"
fi

if [ -n "$DK_CRYPTO_AES_KEY" ]; then
	cmd+=("--crypto-aes_key=$DK_CRYPTO_AES_KEY")
	printf "* Set aes_key => $DK_CRYPTO_AES_KEY \n"
fi

if [ -n "$DK_CRYPTO_AES_KEY_FILE" ]; then
	cmd+=("--crypto-aes_key_file=$DK_CRYPTO_AES_KEY_FILE")
	printf "* Set aes_key_file => $DK_CRYPTO_AES_KEY_FILE \n"
fi






printf "* Apply all DK_* envs done.\n"

##################
# Try install...
##################
# shellcheck disable=SC2059
printf "* Downloading installer ${installer} from ${installer_url}\n"

rm -rf $installer

if [ "$proxy" ]; then # add proxy for curl
	# shellcheck disable=SC2086
	curl $verbose_mode -x "$proxy" --fail --progress-bar $installer_url > $installer
else
	# shellcheck disable=SC2086
	curl $verbose_mode --fail --progress-bar $installer_url > $installer
fi

# Set executable
chmod +x $installer

if [ "$upgrade" ]; then
	# shellcheck disable=SC2059
	printf "* Upgrading DataKit...\n"
else
	printf "* Installing DataKit...\n"
fi

$sudo_cmd $installer "${cmd[@]}" 

rm -rf $installer

# install completion
$sudo_cmd datakit tool --setup-completer-script 

install_prom_conf() {
    printf "* Installing Prometheus configuration...\n"
    
    # 创建配置目录
    PROM_CONF_DIR="/usr/local/datakit/conf.d/prom"
    $sudo_cmd mkdir -p $PROM_CONF_DIR

    # 创建配置文件
    PROM_CONF_FILE="${PROM_CONF_DIR}/prom_node_exporter.conf"

    # 检查配置文件是否已存在
    if [ -f "$PROM_CONF_FILE" ]; then
        printf "* Prometheus configuration file already exists, skipping installation\n"	
        return 0
    fi
    # 使用 cat 命令写入配置内容
    cat << 'EOF' | $sudo_cmd tee $PROM_CONF_FILE > /dev/null
# {"version": "1.63.1", "desc": "do NOT edit this line"}

[[inputs.prom]]
  ## Exporter URLs.
  urls = ["http://127.0.0.1:9100/metrics"]


  uds_path = ""

  ## Ignore URL request errors.
  ignore_req_err = false

  ## Collector alias.
  source = "prom"


  measurement_name = "node_exporter"

 
  keep_exist_metric_name = true

  election = true

  ## disable setting host tag for this input
  disable_host_tag = false

  ## disable setting instance tag for this input
  disable_instance_tag = false

  ## disable info tag for this input
  disable_info_tag = false

  [[inputs.prom.measurements]]
    prefix = "etcd_network_"
    name = "etcd_network"
    
  [[inputs.prom.measurements]]
    prefix = "etcd_server_"
    name = "etcd_server"

  ## Rename tag key in prom data.
  [inputs.prom.tags_rename]
    overwrite_exist_tags = false

  [inputs.prom.as_logging]
    enable = false
    service = "service_name"

  ## Customize tags.
  # [inputs.prom.tags]
    # some_tag = "some_value"
    # more_tag = "some_other_value"
  
  ## (Optional) Collect interval: (defaults to "30s").
  # interval = "30s"

  ## (Optional) Timeout: (defaults to "30s").
  # timeout = "30s"
EOF

    
    printf "* Prometheus configuration  completed\n"
}

install_otel_conf() {
    printf "* Installing Opentelemetry configuration...\n"
    
    # 创建配置目录
    OTEL_CONF_DIR="/usr/local/datakit/conf.d/opentelemetry"

    # 创建配置文件
    OTEL_CONF_FILE="${OTEL_CONF_DIR}/opentelemetry.conf"

    # 检查配置文件是否已存在
    if [ -f "$OTEL_CONF_FILE" ]; then
        printf "* Opentelemetry configuration file already exists, skipping installation\n"
        return 0
    fi
    # 使用 cat 命令写入配置内容
    cat << 'EOF' | $sudo_cmd tee $OTEL_CONF_FILE > /dev/null
# {"version": "1.64.1", "desc": "do NOT edit this line"}
[[inputs.opentelemetry]]
  [inputs.opentelemetry.http]
   enable = true
   http_status_ok = 200
   trace_api = "/otel/v1/trace"
   metric_api = "/otel/v1/metric"
   logs_api = "/otel/v1/logs"

  [inputs.opentelemetry.grpc]
   trace_enable = true
   metric_enable = true
   addr = "0.0.0.0:4317"
EOF


    printf "* Opentelemetry configuration  completed\n"
}

install_prom_pushgateway_conf() {
    printf "* Installing Prometheus Pushgateway configuration...\n"
    
    # 创建配置目录
    PROM_PUSHGATEWAY_CONF_DIR="/usr/local/datakit/conf.d/pushgateway"
    $sudo_cmd mkdir -p $PROM_PUSHGATEWAY_CONF_DIR

    # 创建配置文件
    PROM_PUSHGATEWAY_CONF_FILE="${PROM_PUSHGATEWAY_CONF_DIR}/pushgateway.conf"

    # 检查配置文件是否已存在
    if [ -f "$PROM_PUSHGATEWAY_CONF_FILE" ]; then
        printf "* Prometheus Pushgateway configuration file already exists, skipping installation\n"
        return 0
    fi
    # 使用 cat 命令写入配置内容
    cat << 'EOF' | $sudo_cmd tee $PROM_PUSHGATEWAY_CONF_FILE > /dev/null
[[inputs.pushgateway]]
  ## Prefix for the internal routes of web endpoints. Defaults to empty.
  route_prefix = "/v1/pushgateway"

  job_as_measurement = false
  keep_exist_metric_name = true
EOF

    # 下载配置文件
#     PROM_CONF_FILE="${PROM_CONF_DIR}/prom.conf"

#     wget -O $PROM_CONF_FILE "${DK_INSTALLER_BASE_URL}/prom_1_63_1.conf"

#     # 重启 DataKit 服务
#     printf "* Restarting DataKit service...\n"
#     $sudo_cmd datakit service -R
    
    printf "* Prometheus Pushgateway configuration  completed\n"
}




install_logging_conf() {
    printf "* Installing Logging configuration...\n"
    
    # 创建配置目录
    LOGGING_CONF_DIR="/usr/local/datakit/conf.d/log"
    $sudo_cmd mkdir -p $LOGGING_CONF_DIR
    
    # 创建配置文件
    LOGGING_CONF_FILE="${LOGGING_CONF_DIR}/logging.conf"

    # 检查配置文件是否已存在
    if [ -f "$LOGGING_CONF_FILE" ]; then
        printf "* Logging configuration file already exists, skipping installation\n"
        return 0
    fi

    # 创建采集目录
    $sudo_cmd mkdir -p /home/app/.guance/logs
    $sudo_cmd mkdir -p /var/log/aws-routed-eni
    $sudo_cmd mkdir -p /var/log/audit

    # 使用 cat 命令写入配置内容
    cat << 'EOF' | $sudo_cmd tee $LOGGING_CONF_FILE > /dev/null
[[inputs.logging]]
  logfiles = [
    "/var/log/syslog",
    "/var/log/messages",
    "/var/log/dmesg",
    "/var/log/aws-routed-eni/*",
    "/var/log/secure",
    "/var/log/audit/*",
    "/var/log/lastlog",
    "/opt/datakit/*.log",
    "/var/log/datakit/log"
  ]

  ignore = [""]

  source = ""

  service = ""

  pipeline = ""

  ignore_status = []

  character_encoding = ""

  auto_multiline_detection = true
  auto_multiline_extra_patterns = []

  remove_ansi_escape_codes = false

  ignore_dead_log = "12h"

  from_beginning = false

  [inputs.logging.tags]
EOF


#     # 重启 DataKit 服务
#     printf "* Restarting DataKit service...\n"
#     $sudo_cmd datakit service -R
    
    printf "* Logging configuration  completed\n"
}


# 安装依赖工具
install_jq_yj() {

    # 定义安装路径
    JQ_BIN_PATH="/usr/bin/jq"
    YJ_BIN_PATH="/usr/bin/yj"
    
    # jq 下载链接
    JQ_DOWNLOAD_URL="$installer_base_url/jq"
    
    # yj 下载链接
    YJ_DOWNLOAD_URL="$installer_base_url/yj"

    # 安装 jq
    if ! command -v jq &> /dev/null; then
        echo "Installing jq..."
        wget -q "$JQ_DOWNLOAD_URL" -O jq
        if [ $? -eq 0 ]; then
            chmod +x jq
            sudo mv jq "$JQ_BIN_PATH"
            echo "jq installed successfully."
        else
            echo "Error: Failed to download jq."
            return 1
        fi
    else
        echo "jq is already installed."
    fi

    # 安装 yj
    if ! command -v yj &> /dev/null; then
        echo "Installing yj..."
        wget -q "$YJ_DOWNLOAD_URL" -O yj
        if [ $? -eq 0 ]; then
            chmod +x yj
            sudo mv yj "$YJ_BIN_PATH"
            echo "yj installed successfully."
        else
            echo "Error: Failed to download yj."
            return 1
        fi
    else
        echo "yj is already installed."
    fi
}


get_app_init_script() {
    # 业务初始化脚本下载链接
    INIT_SCRIPT_DOWNLOAD_URL="$installer_base_url/app_init.sh"

    # 本地存放路径
    INIT_SCRIPT_DIR="/opt/datakit"
    INIT_SCRIPT_PATH="$INIT_SCRIPT_DIR/app_init.sh"

    if [ ! -d "$INIT_SCRIPT_DIR" ]; then
        mkdir -p "$INIT_SCRIPT_DIR"
        printf "* 目录 %s 不存在，已创建\n" "$INIT_SCRIPT_DIR"
    else
        printf "* 目录 %s 已存在\n" "$INIT_SCRIPT_DIR"
    fi
    # 下载脚本
    echo "Download app_init.sh ..."
    wget -q "$INIT_SCRIPT_DOWNLOAD_URL" -O $INIT_SCRIPT_PATH

    # 授权

    chmod +x $INIT_SCRIPT_PATH
    echo "app_init.sh Download successfully...."
}

get_upgrade_datakit_script() {
    # 业务初始化脚本下载链接
    UPGRADE_SCRIPT_DOWNLOAD_URL="$installer_base_url/upgrade_datakit.sh"

    # 本地存放路径
    UPGRADE_SCRIPT_DIR="/opt/datakit"
    UPGRADE_SCRIPT_PATH="/opt/datakit/upgrade_datakit.sh"

    if [ ! -d "$INIT_SCRIPT_DIR" ]; then
        mkdir -p "$UPGRADE_SCRIPT_DIR"
        printf "* 目录 %s 不存在，已创建\n" "$UPGRADE_SCRIPT_DIR"
    else
        printf "* 目录 %s 已存在\n" "$UPGRADE_SCRIPT_DIR"
    fi
    # 下载脚本
    echo "Download upgrade_datakit.sh ..."
    wget -q "$UPGRADE_SCRIPT_DOWNLOAD_URL" -O $UPGRADE_SCRIPT_PATH

    # 授权

    chmod +x $UPGRADE_SCRIPT_PATH
    echo "upgrade_datakit.sh Download successfully...."
}




# 设置定时任务
set_cron_job_app_init() {
    # 定义要执行的脚本路径
    APP_INIT_SCRIPT_PATH="/opt/datakit/app_init.sh"  # 请替换为实际的脚本路径

    # 检查脚本是否存在
    if [ ! -f "$APP_INIT_SCRIPT_PATH" ]; then
        echo "Error: Script $APP_INIT_SCRIPT_PATH does not exist."
        return 1
    fi

    # 检查是否已存在相同的 cron 任务
    if crontab -l 2>/dev/null | grep -q "$APP_INIT_SCRIPT_PATH"; then
        echo "Cron job for $APP_INIT_SCRIPT_PATH already exists. Exiting."
        return 0
    fi

    # 创建一个新的 cron 任务
    (crontab -l 2>/dev/null; echo "*/5 * * * * $APP_INIT_SCRIPT_PATH") | crontab -

    echo "Cron job set to execute $APP_INIT_SCRIPT_PATH every 5 minutes."

}


set_cron_job_upgrade_datakit() {
    # 定义要执行的脚本路径
    UPGRADE_DATAKIT_SCRIPT_PATH="/opt/datakit/upgrade_datakit.sh"  # 请替换为实际的脚本路径

    # 检查脚本是否存在
    if [ ! -f "$UPGRADE_DATAKIT_SCRIPT_PATH" ]; then
        echo "Error: Script $UPGRADE_DATAKIT_SCRIPT_PATH does not exist."
        return 1
    fi

    # 检查是否已存在相同的 cron 任务
    if crontab -l 2>/dev/null | grep -q "$UPGRADE_DATAKIT_SCRIPT_PATH"; then
        echo "Cron job for $UPGRADE_DATAKIT_SCRIPT_PATH already exists. Exiting."
        return 0
    fi

    # 创建一个新的 cron 任务
    (crontab -l 2>/dev/null; echo "*/30 * * * * $UPGRADE_DATAKIT_SCRIPT_PATH") | crontab -

    echo "Cron job set to execute $UPGRADE_DATAKIT_SCRIPT_PATH every 5 minutes."

}




restart_datakit() {
    printf "* 正在重启 DataKit 服务...\n"
    $sudo_cmd systemctl restart datakit
    printf "* DataKit 服务重启命令已执行\n"
}

check_port_and_restart() {
    local attempts=0
    local max_attempts=10
    local restart_count=0

    # 重启datakit
    restart_datakit

    while [ $attempts -lt $max_attempts ]; do
        if netstat -tuln | grep -q ":9529"; then
            printf "* DataKit 服务在 9529 端口运行\n"
            return 0
        fi
        sleep 2
        attempts=$((attempts + 1))
        printf "* 正在等待 9529 端口... (第 %d 次尝试/%d)\n" "$attempts" "$max_attempts"
    done

    while [ $restart_count -lt 3 ]; do
        restart_datakit
        attempts=0

        while [ $attempts -lt $max_attempts ]; do
            if netstat -tuln | grep -q ":9529"; then
                printf "* DataKit 服务已成功重启并在 9529 端口运行\n"
                return 0
            fi
            sleep 2
            attempts=$((attempts + 1))
            printf "* 正在等待 9529 端口... (第 %d 次尝试/%d)\n" "$attempts" "$max_attempts"
        done

        restart_count=$((restart_count + 1))
        printf "* 第 %d 次重启后，9529 端口仍未监听\n" "$restart_count"
    done

    echo "错误: 连续重启 DataKit 3 次后仍未能在 9529 端口监听，异常退出"
    return 1
}


# 在原有命令行参数中添加 prom 选项
if [ "$DK_INSTALL_PROM" == "true" ] && [ "$DK_UPGRADE" != "1" ]; then
    install_prom_conf
fi

# 在原有命令行参数中添加 otel 选项
if [ "$DK_INSTALL_OTEL" == "true" ] && [ "$DK_UPGRADE" != "1" ]; then
    install_otel_conf
fi

# 在原有命令行参数中添加 logging 选项
if [ "$DK_INSTALL_LOGGING" == "true" ] && [ "$DK_UPGRADE" != "1" ]; then
    install_logging_conf
fi

# 在原有命令行参数中添加 pushgateway 选项	
if [ "$DK_INSTALL_PUSHGATEWAY" == "true" ] && [ "$DK_UPGRADE" != "1" ]; then
    install_prom_pushgateway_conf
fi

# 安装依赖
# 
if [ "$DK_UPGRADE" != "1" ]; then
    install_jq_yj
fi

# 下载业务初始化文件
if [ "$DK_UPGRADE" != "1" ]; then
    get_app_init_script
    get_upgrade_datakit_script
fi


# 下发定时任务
if [ "$DK_UPGRADE" != "1" ]; then
    set_cron_job_app_init
    set_cron_job_upgrade_datakit
fi


# 重启 DataKit 服务
if [ "$DK_UPGRADE" != "1" ]; then
    check_port_and_restart
fi
