#!/bin/bash
# singbox一键安装脚本
# Author: Slotheve<https://slotheve.com>


RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

CONFIG_FILE="/usr/local/etc/sing-box/config.json"
OS=`hostnamectl | grep -i system | cut -d: -f2`

IP=`curl -sL -4 ip.sb`
VMESS="false"
VLESS="false"
TROJAN="false"

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        result=$(id | awk '{print $1}')
	if [[ $result != "用户id=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
	fi
    fi

    res=`which yum 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        res=`which apt 2>/dev/null`
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
    fi
    res=`which systemctl 2>/dev/null`
    if [[ "$?" != "0" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

config() {
    local conf=`grep wsSettings $CONFIG_FILE`
    if [[ -z "$conf" ]]; then
        echo no
        return
    fi
    echo yes
}

status() {
    if [[ ! -f /usr/local/bin/sing-box ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep port $CONFIG_FILE| head -n 1| cut -d: -f2| tr -d \",' '`
    res=`ss -nutlp| grep ${port} | grep -i sing-box`
    if [[ -z "$res" ]]; then
        echo 2
        return
    fi
    
    if [[ `config` != "yes" ]]; then
        echo 3
    fi
}

statusText() {
    res=`status`
    case $res in
        2)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

normalizeVersion() {
    if [ -n "$1" ]; then
        case "$1" in
            v*)
                echo "$1"
            ;;
            http*)
                echo "v1.2.5"
            ;;
            *)
                echo "v$1"
            ;;
        esac
    else
        echo ""
    fi
}

# 1: new Xray. 0: no. 1: yes. 2: not installed. 3: check failed.
getVersion() {
    VER=v`/usr/local/bin/sing-box version|head -n1 | awk '{print $3}'`
    RETVAL=$?
    CUR_VER="$(normalizeVersion "$(echo "$VER" | head -n 1 | cut -d " " -f2)")"
    TAG_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    NEW_VER_V="$(normalizeVersion "$(curl -s "${TAG_URL}" --connect-timeout 10| grep -Eo '\"tag_name\"(.*?)\",' | cut -d\" -f4)")"
	NEW_VER=`curl -s "${TAG_URL}" --connect-timeout 10| grep -Eo '\"tag_name\"(.*?)\",' | cut -d\" -f4 | awk -F 'v' '{print $2}'`

    if [[ $? -ne 0 ]] || [[ $NEW_VER_V == "" ]]; then
        colorEcho $RED " 检查Sing-Box版本信息失败，请检查网络"
        return 3
    elif [[ $RETVAL -ne 0 ]];then
        return 2
    elif [[ $NEW_VER_V != $CUR_VER ]];then
        return 1
    fi
    return 0
}

getData() {
    read -p " 请输入SingBox监听端口[100-65535的一个数字]：" PORT
    [[ -z "${PORT}" ]] && PORT=`shuf -i200-65000 -n1`
    if [[ "${PORT:0:1}" = "0" ]]; then
	colorEcho ${RED}  " 端口不能以0开头"
	exit 1
    fi
    colorEcho ${BLUE}  " SingBox端口：$PORT"
    if [[ "$TROJAN" = "true" ]]; then
        echo ""
        read -p " 请设置trojan密码（不输则随机生成）:" PASSWORD
        [[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
        colorEcho $BLUE " 密码：$PASSWORD"
	echo ""
	read -p " 请设置ws路径（格式'/xx'）:" WS
        if [[ -z "$WS" ]]; then
                colorEcho $RED " 请输入路径"
        fi
        colorEcho $BLUE " 路径：$WS"
    elif [[ "$VLESS" = "true" ]]; then
        echo ""
	read -p " 请设置vless的UUID（不输则随机生成）:" UUID
	[[ -z "$UUID" ]] && UUID="$(cat '/proc/sys/kernel/random/uuid')"
	colorEcho $BLUE " UUID：$UUID"
	echo ""
	read -p " 请设置ws路径（格式'/xx'）:" WS
	if [[ -z "$WS" ]]; then
		colorEcho $RED " 请输入路径"
	fi
	colorEcho $BLUE " 路径：$WS"
    elif [[ "$VMESS" = "true" ]]; then
	echo ""
	read -p " 请设置vmess的UUID（不输则随机生成）:" UUID
	[[ -z "$UUID" ]] && UUID="$(cat '/proc/sys/kernel/random/uuid')"
	colorEcho $BLUE " UUID：$UUID"
	echo ""
	read -p " 请设置ws路径（格式'/xx'）:" WS
	if [[ -z "$WS" ]]; then
			colorEcho $RED " 请输入路径"
	fi
	colorEcho $BLUE " 路径：$WS"
    fi
}

setSelinux() {
    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

archAffix() {
    case "$(uname -m)" in
      x86_64|amd64)
        ARCH="amd64"
	CPU="x86_64"
        ;;
      armv8|aarch64)
        ARCH="arm64"
	CPU="aarch64"
        ;;
      *)
        colorEcho $RED " 不支持的CPU架构！"
        exit 1
        ;;
    esac
    return 0
}

installSingBox() {
	archAffix
    rm -rf /tmp/sing-box
    mkdir -p /tmp/sing-box
    DOWNLOAD_LINK="https://github.com/SagerNet/sing-box/releases/download/${NEW_VER_V}/sing-box-${NEW_VER}-linux-${ARCH}.tar.gz"
    colorEcho $BLUE " 下载SingBox: ${DOWNLOAD_LINK}"
    wget -O /tmp/sing-box/sing-box.tar.gz ${DOWNLOAD_LINK}
    if [ $? != 0 ];then
        colorEcho $RED " 下载SingBox文件失败，请检查服务器网络设置"
        exit 1
    fi
    systemctl stop sing-box
    mkdir -p /usr/local/etc/sing-box /usr/local/share/sing-box && \
    tar -xvf /tmp/sing-box/sing-box.tar.gz -C /tmp/sing-box
    cp /tmp/sing-box/sing-box-${NEW_VER}-linux-${ARCH}/sing-box /usr/local/bin
    chmod +x /usr/local/bin/sing-box || {
	colorEcho $RED " SingBox安装失败"
	exit 1
    }

    cat >/etc/systemd/system/sing-box.service<<-EOF
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=30s
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
	chmod 644 ${CONFIG_FILE}
	systemctl daemon-reload
	systemctl enable sing-box.service
}

vmessConfig() {
	cat > $CONFIG_FILE<<-EOF
{
    "inbounds": [
	    {
            "type": "vmess",
            "listen": "0.0.0.0",
            "listen_port": $PORT,
            "domain_strategy": "prefer_ipv4",
            "users": [{
              "uuid": "$UUID",
              "alterId": 0
            }],
            "transport": {
              "type": "ws",
              "path": "$WS"
            },
            "tcp_fast_open": true,
            "udp_fragment": true
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF
}

vlessConfig() {
    cat > $CONFIG_FILE<<-EOF
{
    "inbounds": [
        {
            "type": "vless",
            "listen": "0.0.0.0",
            "listen_port": $PORT,
            "domain_strategy": "prefer_ipv4",
            "users": [{
              "uuid": "$UUID",
              "flow": ""
            }],
            "transport": {
              "type": "ws",
              "path": "$WS"
            },
            "tcp_fast_open": true,
            "udp_fragment": true
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF
}

trojanConfig() {
	cat > $CONFIG_FILE<<-EOF
{
    "inbounds": [
        {
            "type": "trojan",
            "listen": "0.0.0.0",
            "listen_port": $PORT,
            "domain_strategy": "prefer_ipv4",
            "users": [{
              "password": "$PASSWORD"
            }],
            "tls": {
              "enabled": false
            },
            "transport": {
              "type": "ws",
              "path": "$WS"
            },
            "tcp_fast_open": true,
            "udp_fragment": true
        }
    ],
    "outbounds": [
        {
          "type": "direct"
        }
    ]
}
EOF
}

configSingBox() {
	mkdir -p /usr/local/sing-box
	if   [[ "$VMESS" = "true" ]]; then
		vmessConfig
	elif [[ "$VLESS" = "true" ]]; then
		vlessConfig
	elif [[ "$TROJAN" = "true" ]]; then
		trojanConfig
	fi
}

install() {
	getData

	$PMT clean all
	[[ "$PMT" = "apt" ]] && $PMT update
	$CMD_INSTALL wget vim tar openssl
	$CMD_INSTALL net-tools
	if [[ "$PMT" = "apt" ]]; then
		$CMD_INSTALL libssl-dev
	fi

	colorEcho $BLUE " 安装SingBox..."
	getVersion
	RETVAL="$?"
	if [[ $RETVAL == 0 ]]; then
		colorEcho $BLUE " SingBox最新版 ${CUR_VER} 已经安装"
	elif [[ $RETVAL == 3 ]]; then
		exit 1
	else
		colorEcho $BLUE " 安装SingBox ${NEW_VER_V} ，架构$(archAffix)"
		installSingBox
	fi
		configSingBox
		setSelinux
		start
		showInfo
}

update() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " SingBox未安装，请先安装！"
		return
	fi

	getVersion
	RETVAL="$?"
	if [[ $RETVAL == 0 ]]; then
		colorEcho $BLUE " SingBox最新版 ${CUR_VER} 已经安装"
	elif [[ $RETVAL == 3 ]]; then
		exit 1
	else
		colorEcho $BLUE " 安装SingBox ${NEW_VER} ，架构$(archAffix)"
		installXray
		stop
		start
		colorEcho $GREEN " 最新版SingBox安装成功！"
	fi
}

uninstall() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " SingBox未安装，请先安装！"
		return
	fi

	echo ""
	read -p " 确定卸载SingBox？[y/n]：" answer
	if [[ "${answer,,}" = "y" ]]; then
		stop
		systemctl disable sing-box
		rm -rf /etc/systemd/system/sing-box.service
		systemctl daemon-reload
		rm -rf /usr/local/bin/sing-box
		rm -rf /usr/local/etc/sing-box
		colorEcho $GREEN " SingBox卸载成功"
	elif [[ "${answer}" = "n" || -z "${answer}" ]]; then
		colorEcho $BLUE " 取消卸载"
	else
		colorEcho $RED " 输入错误, 请输入正确操作。"
		exit 1
	fi
}

start() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " SingBox未安装，请先安装！"
		return
	fi
	systemctl restart sing-box
	sleep 2

	port=`grep port $CONFIG_FILE| head -n 1| cut -d: -f2| tr -d \",' '`
	res=`ss -nutlp| grep ${port} | grep -i sing-box`
	if [[ "$res" = "" ]]; then
		colorEcho $RED " SingBox启动失败，请检查日志或查看端口是否被占用！"
	else
		colorEcho $BLUE " SingBox启动成功"
	fi
}

stop() {
	systemctl stop sing-box
	colorEcho $BLUE " SingBox停止成功"
}


restart() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " SingBox未安装，请先安装！"
		return
	fi

	stop
	start
}

getConfigFileInfo() {
	protocol=`grep type $CONFIG_FILE | cut -d: -f2 | head -n 1 | tr -d \",' '`
	network="ws"
	port=`grep port $CONFIG_FILE | cut -d: -f2 | head -n 1 | tr -d \",' '`
	uuid=`grep id $CONFIG_FILE | head -n1| cut -d: -f2 | tr -d \",' '`
	alterid=`grep alterId $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
	path=`grep path $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
	cert=`grep certificate_path $CONFIG_FILE | tail -n1| cut -d: -f2 | tr -d \",' '`
	key=`grep key_path $CONFIG_FILE | tail -n1 | cut -d: -f2 | tr -d \",' '`
	domain=`grep server_name $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
	password=`grep password $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
}

outputVmess() {
    raw="{
      \"v\": \"2\",
      \"ps\": \"\",
      \"add\": \"${IP}\",
      \"port\": \"${port}\",
      \"id\": \"${uuid}\",
      \"aid\": \"${alterid}\",
      \"scy\": \"none\",
      \"net\": \"ws\",
      \"type\": \"none\",
      \"host\": \"\",
      \"path\": \"${path}\",
      \"tls\": \"\",
      \"sni\": \"\",
      \"alpn\": \"\",
      \"fp\": \"\"
    }"

	link=`echo -n ${raw} | base64 -w 0`
	link="vmess://${link}"

	echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}id(uuid)：${PLAIN} ${RED}${uuid}${PLAIN}"
	echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}ws${PLAIN}"
	echo -e "   ${BLUE}路径(ws)：${PLAIN} ${RED}${path}${PLAIN}"
	echo ""
	echo -e "   ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
}

outputVless() {
	raw="${uuid}@${IP}:${port}?encryption=none&security=none&type=ws&path=${path}"

	link="vless://${raw}"

	echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}id(uuid)：${PLAIN} ${RED}${uuid}${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}ws${PLAIN}"
	echo -e "   ${BLUE}路径(ws)：${PLAIN} ${RED}${path}${PLAIN}"
	echo ""
	echo -e "   ${BLUE}vless链接:${PLAIN} $RED$link$PLAIN"
}

outputTrojan() {
	raw="${password}@${IP}:${port}?encryption=none&security=none&type=ws&path=${path}"

	link="trojan://${raw}"

	echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
	echo -e "   ${BLUE}IP/域名(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}密码(password)：${PLAIN} ${RED}${password}${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}ws${PLAIN}"
	echo -e "   ${BLUE}路径(ws)：${PLAIN} ${RED}${path}${PLAIN}"
	echo ""
	echo -e "   ${BLUE}trojan链接:${PLAIN} $RED$link$PLAIN"
}

showInfo() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " SingBox未安装，请先安装！"
		return
	fi

	echo ""
	echo -n -e " ${BLUE}SingBox运行状态：${PLAIN}"
	statusText
	echo -e " ${BLUE}SingBox配置文件: ${PLAIN} ${RED}${CONFIG_FILE}${PLAIN}"
	colorEcho $BLUE " SingBox配置信息："

	getConfigFileInfo
	if   [[ "$protocol" = vmess ]]; then
		outputVmess
	elif [[ "$protocol" = vless ]]; then
		outputVless
	elif [[ "$protocol" = trojan ]]; then
		outputTrojan
	fi
}

showLog() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " SingBox未安装，请先安装！"
		return
	fi

	journalctl -xen -u sing-box --no-pager
}

menu() {
	clear
	echo "####################################################"
	echo -e "#               ${RED}SingBox一键安装脚本${PLAIN}                #"
	echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)                             #"
	echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com                       #"
	echo -e "# ${GREEN}频道${PLAIN}: https://t.me/SlothNews                     #"
	echo "####################################################"
	echo " -----------------------------------------------"
	colorEcho $GREEN "  全协议支持UDP over TCP , 且ss/socks支持原生UDP"
  echo " -----------------------------------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装vmess+ws"
	echo -e "  ${GREEN}2.${PLAIN}  安装vless+ws"
	echo -e "  ${GREEN}3.${PLAIN}  安装Trojan+ws"
	echo " --------------------"
	echo -e "  ${GREEN}4.${PLAIN}  更新SingBox"
	echo -e "  ${GREEN}5.${PLAIN} ${RED} 卸载SingBox${PLAIN}"
	echo " --------------------"
	echo -e "  ${GREEN}6.${PLAIN} 启动SingBox"
	echo -e "  ${GREEN}7.${PLAIN} 重启SingBox"
	echo -e "  ${GREEN}8.${PLAIN} 停止SingBox"
	echo " --------------------"
	echo -e "  ${GREEN}9.${PLAIN} 查看SingBox配置"
	echo -e "  ${GREEN}10.${PLAIN}查看SingBox日志"
	echo " --------------------"
	echo -e "  ${GREEN}0.${PLAIN}  退出"
	echo ""
	echo -n " 当前状态："
	statusText
	echo 

	read -p " 请选择操作[0-16]：" answer
	case $answer in
		0)
			exit 0
			;;
		1)
			VMESS="true"
			install
			;;
		2)
			VLESS="true"
			install
			;;
		3)
			TROJAN="true"
			install
			;;
		4)
			update
			;;
		5)
			uninstall
			;;
		6)
			start
			;;
		7)
			restart
			;;
		8)
			stop
			;;
		9)
			showInfo
			;;
		10)
			showLog
			;;
		*)
			colorEcho $RED " 请选择正确的操作！"
			exit 1
			;;
	esac
}
checkSystem
menu
