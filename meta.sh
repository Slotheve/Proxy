#!/bin/bash
# singbox一键安装脚本
# Author: Slotheve<https://slotheve.com>


RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

CONFIG_FILE="/etc/mihomo/config.yaml"
OS=`hostnamectl | grep -i system | cut -d: -f2`

IP=`curl -sL -4 ip.sb`
VMESS="false"
SS="false"

ciphers=(
aes-256-gcm
2022-blake3-aes-256-gcm
chacha20-ietf-poly1305
2022-blake3-chacha20-poly1305
none
)

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
    if [[ ! -f /etc/mihomo/mihomo ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep listeners $CONFIG_FILE -A10| grep port| cut -d\: -f2`
    res=`ss -nutlp| grep ${port} | grep -i mihomo`
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

selectciphers() {
	for ((i=1;i<=${#ciphers[@]};i++ )); do
		hint="${ciphers[$i-1]}"
		echo -e "${green}${i}${plain}) ${hint}"
	done
	read -p "你选择什么加密方式(默认: ${ciphers[0]}):" pick
	[ -z "$pick" ] && pick=1
	expr ${pick} + 1 &>/dev/null
	if [ $? -ne 0 ]; then
		echo -e "[${red}Error${plain}] Please enter a number"
		continue
	fi
	if [[ "$pick" -lt 1 || "$pick" -gt ${#ciphers[@]} ]]; then
		echo -e "${BLUE}[${PLAIN}${RED}Error${PLAIN}${BLUE}]${PLAIN} ${BLUE}请正确选择${PLAIN}"
		exit 0
	fi
	METHOD=${ciphers[$pick-1]}
	colorEcho $BLUE " 加密：${ciphers[$pick-1]}"
}

getData() {
    read -p " 请输入mihomo节点监听端口[100-65535的一个数字]：" PORT1
    [[ -z "${PORT}" ]] && PORT=`shuf -i200-65000 -n1`
    if [[ "${PORT:0:1}" = "0" ]]; then
	colorEcho ${RED}  " 端口不能以0开头"
	exit 1
    fi
    colorEcho ${BLUE}  " mihomo节点端口：$PORT1"
    if [[ "$VMESS" = "true" ]]; then
	  echo ""
	  read -p " 请设置vmess的UUID（不输则随机生成）:" UUID
	  [[ -z "$UUID" ]] && UUID="$(cat '/proc/sys/kernel/random/uuid')"
	  colorEcho $BLUE " UUID：$UUID"
	  echo ""
	  read -p " 是否启用WS？[y/n]：" answer
	  if [[ "${answer,,}" = "y" ]]; then
	    WEBSOCKET='true'
	    read -p " 请设置ws路径（格式'/xx'）:" WS
	    if [[ -z "$WS" ]]; then
			colorEcho $RED " 请输入路径"
	        colorEcho $BLUE " 路径：$WS"
		else
		    colorEcho $RED " 输入错误, 请重新输入。"
        fi
	  elif [[ "${answer}" = "n" || -z "${answer}" ]]; then
		  echo ""
	  else
		  colorEcho $RED " 输入错误, 请输入正确操作。"
		  exit 1
	  fi
	elif [[ "$SS" = "true" ]]; then
	  selectciphers
	  if [[ "$METHOD" = "2022-blake3-aes-256-gcm" || "$METHOD" = "2022-blake3-chacha20-poly1305" ]]; then
			echo ""
			read -p " 请设置ss2022密钥（不会设置请默认生成）:" PASSWORD
			[[ -z "$PASSWORD" ]] && PASSWORD=`openssl rand -base64 32`
			colorEcho $BLUE " 密码：$PASSWORD"
		else
			echo ""
			read -p " 请设置ss密码（不输则随机生成）:" PASSWORD
			[[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
			colorEcho $BLUE " 密码：$PASSWORD"
		fi
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

installmihomo() {
	archAffix
    rm -rf /etc/mihomo
    mkdir -p /etc/mihomo
    DOWNLOAD_LINK="https://raw.githubusercontent.com/Slotheve/backup/main/mihomo-linux-${ARCH}.gz"
    colorEcho $BLUE " 下载mihomo: ${DOWNLOAD_LINK}"
    wget -O /etc/mihomo/mihomo.gz ${DOWNLOAD_LINK}
    if [ $? != 0 ];then
        colorEcho $RED " 下载mihomo文件失败，请检查服务器网络设置"
        exit 1
    fi
    systemctl stop mihomo
    gzip -d /etc/mihomo/mihomo.gz
    mv /etc/mihomo/mihomo-linux-${ARCH} /etc/mihomo/mihomo
    chmod +x /etc/mihomo/mihomo || {
    colorEcho $RED " mihomo安装失败"
    exit 1
    }

    cat >/etc/systemd/system/mihomo.service<<-EOF
[Unit]
[Unit]
Description=Clash Meta.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=/etc/mihomo/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF

	chmod 644 ${CONFIG_FILE}
	systemctl daemon-reload
	systemctl enable mihomo

	cat >> $CONFIG_FILE<<-EOF
allow-lan: false
bind-address: "*"
find-process-mode: strict
mode: rule
log-level: error
external-controller: 0.0.0.0:$PORT2
secret: "$SEC2"
tcp-concurrent: true
global-client-fingerprint: chrome
keep-alive-interval: 86400
profile:
  store-selected: true
  store-fake-ip: false
tun:
  enable: true
  stack: mixed
  dns-hijack:
    - 0.0.0.0:53
  auto-detect-interface: true
  auto-route: true
  inet4-route-address:
    - 0.0.0.0/1
    - 128.0.0.0/1
  inet6-route-address:
    - "::/1"
    - "8000::/1"
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
  fake-ip-filter:
    - '*.lan'
    - '*.direct'
    - '*.local*'
    - cable.auth.com
    - '*.msftconnecttest.com'
    - '*.msftncsi.com'
    - network-test.debian.org
    - detectportal.firefox.com
    - resolver1.opendns.com
    - '*.srv.nintendo.net'
    - '*.stun.playstation.net'
    - xbox.*.microsoft.com
    - '*.xboxlive.com'
    - stun.*
    - global.turn.twilio.com
    - global.stun.twilio.com
    - app.yinxiang.com
    - injections.adguard.org
    - local.adguard.org
    - cable.auth.com
    - '*.logon.battle.net'
    - api-jooxtt.sanook.com
    - api.joox.com
    - joox.com
    - proxy.golang.org
    - '*.cmpassport.com'
    - id6.me
    - '*.icitymobile.mobi'
    - pool.ntp.org
    - '*.pool.ntp.org'
    - ntp.*.com
    - time.*.com
    - ntp?.*.com
    - time?.*.com
    - time.*.gov
rules:
  - MATCH,DIRECT
EOF
}

vmessConfig() {
  if [[ "$WEBSOCKET" = "true" ]]; then
	cat >> $CONFIG_FILE<<-EOF
  - name: vmess
    type: vmess
    port: $PORT1
    listen: 0.0.0.0
    users:
      - username: vmess
        uuid: $UUID
        alterId: 0
     ws-path: "$WS"
EOF
  else
	cat >> $CONFIG_FILE<<-EOF
  - name: vmess
    type: vmess
    port: $PORT1
    listen: 0.0.0.0
    users:
      - username: vmess
        uuid: $UUID
        alterId: 0
EOF
  fi
}

ssConfig() {
	cat >> $CONFIG_FILE<<-EOF
listeners:
  - name: shadowsocks
    type: shadowsocks
    port: $PORT1
    listen: 0.0.0.0
    password: $PASSWORD
    cipher: $METHOD
	udp: true
EOF
}

config() {
	if   [[ "$VMESS" = "true" ]]; then
		vmessConfig
	elif [[ "$SS" = "true" ]]; then
		ssConfig
	fi
}

install() {
	getData

	$PMT clean all
	[[ "$PMT" = "apt" ]] && $PMT update
	$CMD_INSTALL wget vim tar openssl
	$CMD_INSTALL net-tools

	colorEcho $BLUE " 安装mihomo..."
    if [[ ! -f $CONFIG_FILE ]]; then
		colorEcho $BLUE " mihomo已经安装"
	else
		colorEcho $BLUE " 安装mihomo ，架构$ARCH"
		installmihomo
	fi
		config
		setSelinux
		start
		showInfo
}

uninstall() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " mihomo未安装，请先安装！"
		return
	fi

	echo ""
	read -p " 确定卸载mihomo？[y/n]：" answer
	if [[ "${answer,,}" = "y" ]]; then
		stop
		systemctl disable sing-box
		rm -rf /etc/systemd/system/mihomo.service
		systemctl daemon-reload
		rm -rf /etc/mihomo
		colorEcho $GREEN " mihomo卸载成功"
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
		colorEcho $RED " mihomo未安装，请先安装！"
		return
	fi
	systemctl start mihomo
	sleep 2

	port=`grep listeners $CONFIG_FILE -A10| grep port| cut -d\: -f2`
	res=`ss -nutlp| grep ${port} | grep -i mihomo`
	if [[ "$res" = "" ]]; then
		colorEcho $RED " mihomo启动失败，请检查日志或查看端口是否被占用！"
	else
		colorEcho $BLUE " mihomo启动成功"
	fi
}

stop() {
	systemctl stop mihomo
	colorEcho $BLUE " mihomo停止成功"
}


restart() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " mihomo未安装，请先安装！"
		return
	fi

	stop
	start
}

getConfigFileInfo() {
	protocol=`grep listeners $CONFIG_FILE -A10| grep type| cut -d\: -f2| cut -d" " -f2`
	port=`grep listeners $CONFIG_FILE -A10| grep port| cut -d\: -f2| cut -d" " -f2`
	uuid=`grep listeners $CONFIG_FILE -A10| grep uuid| cut -d\: -f2| cut -d" " -f2`
	alterid=`grep listeners $CONFIG_FILE -A10| grep alterId| cut -d\: -f2| cut -d" " -f2`
	path=`grep listeners $CONFIG_FILE -A10| grep ws-path| cut -d\: -f2| cut -d\" -f2| cut -d" " -f2`
	password=`grep listeners $CONFIG_FILE -A10| grep password| cut -d\: -f2| cut -d" " -f2`
	cipher=`grep listeners $CONFIG_FILE -A10| grep cipher| cut -d\: -f2| cut -d" " -f2`
	if [[ -z "${path}" ]]; then
	  network="tcp"
	elif [[ -n "${path}" ]]; then
	  network="ws"
	fi
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
      \"net\": \"${network}\",
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
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
	echo -e "   ${BLUE}路径(ws)：${PLAIN} ${RED}${path}${PLAIN}"
	echo ""
	echo -e "   ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
}

outputSS() {
	echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}加密(cipher)：${PLAIN} ${RED}${cipher}${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}tcp&udp${PLAIN}"
	echo -e "   ${BLUE}密码(passwd)：${PLAIN} ${RED}${password}${PLAIN}"
}

showInfo() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " mihomo未安装，请先安装！"
		return
	fi

	echo ""
	echo -n -e " ${BLUE}mihomo运行状态：${PLAIN}"
	statusText
	echo -e " ${BLUE}mihomo配置文件: ${PLAIN} ${RED}${CONFIG_FILE}${PLAIN}"
	colorEcho $BLUE " mihomo配置信息："

	getConfigFileInfo
	if   [[ "${protocol}" = "vmess" ]]; then
		outputVmess
	else
		outputSS
	fi
}

showLog() {
	res=`status`
	if [[ $res -lt 2 ]]; then
		colorEcho $RED " mihomo未安装，请先安装！"
		return
	fi

	journalctl -xen -u mihomo --no-pager
}

menu() {
	clear
	echo "####################################################"
	echo -e "#               ${RED}mihomo一键安装脚本${PLAIN}                #"
	echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)                             #"
	echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com                       #"
	echo -e "# ${GREEN}频道${PLAIN}: https://t.me/SlothNews                     #"
	echo "####################################################"
	echo " -----------------------------------------------"
	colorEcho $GREEN "  全协议支持UDP over TCP , 且ss/socks支持原生UDP"
  echo " -----------------------------------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装vmess"
	echo -e "  ${GREEN}2.${PLAIN}  安装shadowsocks"
	echo " --------------------"
	echo -e "  ${GREEN}3.${PLAIN} ${RED} 卸载SingBox${PLAIN}"
	echo " --------------------"
	echo -e "  ${GREEN}4.${PLAIN} 启动mihomo"
	echo -e "  ${GREEN}5.${PLAIN} 重启mihomo"
	echo -e "  ${GREEN}6.${PLAIN} 停止mihomo"
	echo " --------------------"
	echo -e "  ${GREEN}7.${PLAIN} 查看mihomo配置"
	echo -e "  ${GREEN}8.${PLAIN}查看mihomo日志"
	echo " --------------------"
	echo -e "  ${GREEN}0.${PLAIN}  退出"
	echo ""
	echo -n " 当前状态："
	statusText
	echo 

	read -p " 请选择操作[0-8]：" answer
	case $answer in
		0)
			exit 0
			;;
		1)
			VMESS="true"
			install
			;;
		2)
			SS="true"
			install
			;;
		3)
			uninstall
			;;
		4)
			start
			;;
		5)
			restart
			;;
		6)
			stop
			;;
		7)
			showInfo
			;;
		8)
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
