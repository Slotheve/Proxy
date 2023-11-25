#!/bin/bash
# Singbox一键安装vless+reality
# Author: Slotheve<https://slotheve.com>


RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

CONFIG_FILE="/usr/local/etc/sing-box/config.json"
CONFIG_CLASH="/usr/local/etc/sing-box/clash.yaml"
OS=`hostnamectl | grep -i system | cut -d: -f2`

IP=`curl -sL -4 ip.sb`

domains=(
gateway.icloud.com
www.microsoft.com
mp.weixin.qq.com
自定义域名
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

Check_singbox() {
    ress=`status`
	if [[ "${ress}" = "0" || "${ress}" = "1" ]]; then
	    colorEcho $RED "未安装Singbox, 请先安装Singbox"
		exit 1
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
	read -p $'请输入监听端口 [1-65535]\n(默认: 6666，回车):' PORT
	[[ -z "${PORT}" ]] && PORT="6666"
	echo $((${PORT}+0)) &>/dev/null
	if [[ $? -eq 0 ]]; then
		if [[ ${PORT} -ge 1 ]] && [[ ${PORT} -le 65535 ]]; then
			colorEcho $BLUE "端口: ${PORT}"
			echo ""
		else
			colorEcho $RED "输入错误, 请输入正确的端口。"
			echo ""
		fi
	else
		colorEcho $RED "输入错误, 请输入数字。"
		echo ""
		exit 1
	fi

 	read -p $'请输入 vless uuid\n(推荐随机生成，直接回车):' UUID
	[[ -z "$UUID" ]] && UUID="$(cat '/proc/sys/kernel/random/uuid')"
	colorEcho $BLUE "UUID：$UUID"
	echo ""

	 for ((i=1;i<=${#domains[@]};i++ )); do
 		hint="${domains[$i-1]}"
 		echo -e "${GREEN}${i}${PLAIN}) ${hint}"
 	done

 	read -p "请选择域名[1-4] (默认: ${domains[0]}):" pick
	[ -z "$pick" ] && pick=1
	expr ${pick} + 1 &>/dev/null
	if [ $? -ne 0 ]; then
		colorEcho $RED "错误, 请输入正确选项"
		continue
	fi
	if [[ "$pick" -lt 1 || "$pick" -gt ${#domains[@]} ]]; then
		echo -e "${red}错误, 请输入正确选项${plain}"
		exit 0
	fi
	DOMAIN=${domains[$pick-1]}
	if [[ "$pick" = "4" ]]; then
		colorEcho $BLUE "已选择: ${domains[$pick-1]}"
		echo ""
		read -p $'请输入自定义域名: ' DOMAIN
		if [[ -z "${DOMAIN}" ]]; then
			colorEcho $RED "错误, 请输入正确的域名"
			echo ""
			exit 1
		else
			colorEcho $BLUE "域名：$DOMAIN"
			echo ""
		fi
	else
		colorEcho $BLUE "域名：${domains[$pick-1]}"
		echo ""
	fi

 	read -p $'是否禁止BT？[y/n]：\n(默认n, 回车)' answer
	if [[ "${answer,,}" = "y" ]]; then
		BT="block"
  		colorEcho $BLUE "BT 已禁止"
		echo ""
	elif [[ "${answer}" = "n" || -z "${answer}" ]]; then
		BT="direct"
  		colorEcho $BLUE "BT 已允许"
		echo ""
	else
		colorEcho $RED " 输入错误, 请输入[y/n]。"
		exit 1
	fi
 
	short_id=$(openssl rand -hex 4)
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
 	echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
	sysctl -p >/dev/null 2>&1
}

configSingBox() {
	mkdir -p /usr/local/sing-box
	keys=$(sing-box generate reality-keypair)
	private_key=$(echo $keys | awk -F " " '{print $2}')
	public_key=$(echo $keys | awk -F " " '{print $4}')

	cat > /usr/local/etc/sing-box/config.json << EOF
{
    "log": {
        "level": "trace",
        "timestamp": true
    },
    "inbounds": [
        {
            "type": "vless",
            "listen": "0.0.0.0",
            "listen_port": $PORT,
            "tcp_fast_open": true,
            "udp_fragment": true,
            "sniff": true,
            "sniff_override_destination": true,
            "users": [
                {
                    "uuid": "$UUID",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "$DOMAIN",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$DOMAIN",
                        "server_port": 443
                    },
                    "private_key": "$private_key",
                    "short_id": "$short_id"
                }
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ],
    "route": {
        "rules": [
            {
                "outbound": "$BT",
                "protocol": [
                "bittorrent"
                ]
            }
        ]
    }
}
EOF

	cat > /usr/local/etc/sing-box/clash.yaml << EOF
- name: Vless+Reality+Vision
  type: vless
  server: $IP
  port: $PORT
  uuid: $UUID
  network: tcp
  tls: true
  udp: true
  fast-open: true
  flow: xtls-rprx-vision
  servername: $DOMAIN
  reality-opts:
    public-key: $public_key
    short-id: $short_id
  client-fingerprint: chrome # chrome/safari/firefox/ios/random/none
EOF
}

install() {
	echo ""
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
		installSingBox
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
	read -p $' 是否卸载SingBox？[y/n]：\n (默认n, 回车)' answer
	if [[ "${answer,,}" = "y" ]]; then
		stop
		systemctl disable sing-box >/dev/null 2>&1
  		colorEcho $BLUE " SingBox服务移除"
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
		colorEcho $GREEN " SingBox启动成功"
	fi
}

stop() {
	systemctl stop sing-box
	colorEcho $GREEN " SingBox停止成功"
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
	port=`grep listen_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
	uuid=`grep uuid $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
	flow=`grep flow $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
	sni=`grep server_name $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
	sid=`grep short_id $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
 	pubkey=`grep public-key $CONFIG_CLASH | cut -d: -f2 | tr -d ' '`
}

output() {
	raw="${uuid}@${IP}:${port}?type=tcp&security=reality&fp=chrome&pbk=${pubkey}&sni=${sni}&flow=${flow}&sid=${sid}&spx=%2F#Vless+Reality+Vision"
	link="vless://${raw}"

	echo -e "   ${BLUE}协议: ${PLAIN} ${RED}vless${PLAIN}"
	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}id(uuid)：${PLAIN} ${RED}${uuid}${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}tcp${PLAIN}"
	echo -e "   ${BLUE}流控(flow)：${PLAIN} ${RED}${flow}${PLAIN}"
	echo -e "   ${BLUE}安全(security)：${PLAIN} ${RED}reality${PLAIN}"
	echo -e "   ${BLUE}域名(sni)：${PLAIN} ${RED}${sni}${PLAIN}"
	echo -e "   ${BLUE}短ID(shortid)：${PLAIN} ${RED}${sid}${PLAIN}"
	echo -e "   ${BLUE}公钥(publickey)：${PLAIN} ${RED}${pubkey}${PLAIN}"
	echo ""
	echo -e "   ${BLUE}Vless链接:${PLAIN} $RED$link$PLAIN"
 	echo -e "   ${BLUE}ClashMeta文件:${PLAIN} $RED${CONFIG_CLASH}$PLAIN"
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
	output
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
	echo -e "#          ${RED}Singbox一键安装vless+reality${PLAIN}            #"
	echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)                             #"
	echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com                       #"
	echo -e "# ${GREEN}频道${PLAIN}: https://t.me/SlothNews                     #"
	echo "####################################################"
	echo " -----------------------------------------------"
	echo -e "  ${GREEN}1.${PLAIN} 安装vless+reality"
	echo " --------------------"
	echo -e "  ${GREEN}2.${PLAIN} 更新SingBox"
	echo -e "  ${GREEN}3.${PLAIN} ${RED}卸载SingBox${PLAIN}"
	echo " --------------------"
	echo -e "  ${GREEN}4.${PLAIN} 启动SingBox"
	echo -e "  ${GREEN}5.${PLAIN} 重启SingBox"
	echo -e "  ${GREEN}6.${PLAIN} 停止SingBox"
	echo " --------------------"
	echo -e "  ${GREEN}7.${PLAIN} 查看SingBox配置"
	echo -e "  ${GREEN}8.${PLAIN} 查看SingBox日志"
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
			install
			;;
		2)
			update
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

action=$1
[[ -z $1 ]] && action=menu
case "$action" in
	menu|update|uninstall|start|restart|stop|showInfo|showLog)
		${action}
		;;
	*)
		echo " 参数错误"
		echo " 用法: `basename $0` [menu|update|uninstall|start|restart|stop|showInfo|showLog]"
		;;
esac
