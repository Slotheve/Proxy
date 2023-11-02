#!/bin/bash
# Author: Slotheve<https://slotheve.com>

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

IP4=`curl -sL -4 ip.sb`
IP6=`curl -sL -6 ip.sb`
CPU=`uname -m`
conf="/etc/hysteria/config.yaml"
client="/etc/hysteria/client.yaml"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

ports=(
固定单端
端口跳跃
)

domains=(
gateway.icloud.com
www.bing.com
自定义自签
)

archAffix(){
    if [[ "$CPU" = "x86_64" ]] || [[ "$CPU" = "amd64" ]]; then
		CPU="amd64"
		ARCH="x86_64"
    elif [[ "$CPU" = "armv8" ]] || [[ "$CPU" = "aarch64" ]]; then
		CPU="arm64"
		ARCH="aarch64"
    else
		colorEcho $RED " 不支持的CPU架构！"
    fi
}

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
		OS="apt"
    else
		OS="yum"
    fi
    res=`which systemctl 2>/dev/null`
    if [[ "$?" != "0" ]]; then
		colorEcho $RED " 系统版本过低，请升级到最新版本"
		exit 1
    fi
}

status() {
    if [[ ! -f /etc/hysteria/hysteria ]]; then
		echo 0
		return
    fi
    if [[ ! -f ${conf} ]]; then
		echo 1
		return
    fi
    tmp=`grep listen ${conf} | head -n1 | awk -F ' ' '{print $2}' | cut -d: -f2`
    res=`ss -nutlp| grep ${tmp} | grep -i hysteria`
    if [[ -z $res ]]; then
		echo 2
    else
		echo 3
		return
    fi
}

statusText() {
    res=`status`
    case ${res} in
        2)
            echo -e ${BLUE}hysteria:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${BLUE}hysteria:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}已运行${PLAIN}
            ;;
        *)
            echo -e ${BLUE}hysteria:${PLAIN} ${RED}未安装${PLAIN}
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
                echo "v2.0.0"
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
    VER=`/etc/hysteria/hysteria version | grep ersion | head -n1 | awk '{print $2}'`
    RETVAL=$?
    CUR_VER="$(normalizeVersion "$(echo "$VER" | head -n 1 | cut -d " " -f2)")"
    TAG_URL="https://api.github.com/repos/apernet/hysteria/releases/latest"
    NEW_VER="$(normalizeVersion "$(curl -s "${TAG_URL}" --connect-timeout 10| grep -Eo '\"tag_name\"(.*?)\",' | cut -d\" -f4 | cut -d\/ -f2)")"

    if [[ $? -ne 0 ]] || [[ $NEW_VER == "" ]]; then
        colorEcho $RED " 检查Hysteria版本信息失败，请检查网络"
        return 3
    elif [[ $RETVAL -ne 0 ]];then
        return 2
    elif [[ $NEW_VER != $CUR_VER ]];then
        return 1
    fi
    return 0
}

Download_hysteria(){
    archAffix
    getVersion
    DOWNLOAD_LINK="https://github.com/apernet/hysteria/releases/download/app%2F${NEW_VER}/hysteria-linux-${CPU}"
    colorEcho $YELLOW "下载hysteria: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /etc/hysteria/hysteria ${DOWNLOAD_LINK}
    chmod +x /etc/hysteria/hysteria
}

Generate_conf(){
    rm -rf /etc/hysteria
    mkdir -p /etc/hysteria
    Set_port
    Set_pass
    Set_ssl
	Set_proxy
    echo "net.core.rmem_max=16777216" >> sysctl.conf >/dev/null 2>&1
    echo "net.core.wmem_max=16777216" >> sysctl.conf >/dev/null 2>&1
    sysctl -p >/dev/null 2>&1
}

Deploy_hysteria(){
    cd /etc/systemd/system
    cat > hysteria.service<<-EOF
[Unit]
Description=Hysteria Server
After=network.target

[Service]
ExecStart=/etc/hysteria/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable hysteria
    systemctl restart hysteria
}

Set_port(){
    for ((i=1;i<=${#ports[@]};i++ )); do
 		hint="${ports[$i-1]}"
 		echo -e "${GREEN}${i}${PLAIN}) ${hint}"
    done
    read -p "请选择域名[1/2] (默认: ${ports[0]}):" pick
    [ -z "$pick" ] && pick=1
    expr ${pick} + 1 &>/dev/null
    if [ $? -ne 0 ]; then
		colorEcho $RED "错误, 请输入正确选项"
		continue
    fi
    if [[ "$pick" -lt 1 || "$pick" -gt ${#ports[@]} ]]; then
		colorEcho $RED "错误, 请输入正确选项"
		exit 0
    fi
    if [[ "$pick" = "1" ]]; then
		read -p $'请输入固定端口 [1-65535]\n(默认: 6666，回车): ' PORT
		[[ -z "${PORT}" ]] && PORT="6666"
		echo $((${PORT}+0)) &>/dev/null
		if [[ $? -eq 0 ]]; then
			if [[ ${PORT} -ge 1 ]] && [[ ${PORT} -le 65535 ]]; then
				colorEcho $BLUE "端口: ${PORT}"
				echo ""
			else
				colorEcho $RED "输入错误, 请输入正确的端口。"
				exit 0
			fi
		else
			colorEcho $RED "输入错误, 请输入数字。"
			exit 0
		fi
    elif [[ "$pick" = "2" ]]; then
		read -p $'请输入起始端口 [1-65535]\n(默认: 10001，回车): ' FPORT
		[[ -z "${FPORT}" ]] && FPORT="10001"
		echo $((${FPORT}+0)) &>/dev/null
		if [[ $? -eq 0 ]]; then
			if [[ ${FPORT} -ge 1 ]] && [[ ${FPORT} -le 65535 ]]; then
				read -p $'请输入末尾端口 [>起始-65535]\n(默认: 60000，回车): ' EPORT
				[[ -z "${EPORT}" ]] && EPORT="60000"
				echo $((${EPORT}+0)) &>/dev/null
				if [[ $? -eq 0 ]]; then
					if [[ ${EPORT} -ge 1 ]] && [[ ${EPORT} -le 65535 ]]; then
						iptables -t nat -A PREROUTING -p udp --dport $((${FPORT}+1)):$EPORT  -j DNAT --to-destination :$FPORT
						ip6tables -t nat -A PREROUTING -p udp --dport $((${FPORT}+1)):$EPORT  -j DNAT --to-destination :$FPORT
						netfilter-persistent save >/dev/null 2>&1
						PORT="${FPORT}"
						colorEcho $BLUE "端口范围: ${FPORT}-${EPORT}"
						echo ""
					else
						colorEcho $RED "输入错误, 请输入正确的端口。"
						exit 0
					fi
				else
					colorEcho $RED "输入错误, 请输入数字。"
					exit 0
				fi
			else
				colorEcho $RED "输入错误, 请输入正确的端口。"
				exit 0
			fi
		else
			colorEcho $RED "输入错误, 请输入数字。"
			exit 0
		fi
    fi
}

Set_pass() {
    read -p $'请设置hysteria密码\n(默认随机生成, 回车): ' PASS
    [[ -z "$PASS" ]] && PASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1`
	colorEcho $BLUE "密码：$PASS"
    echo ""
}

Set_ssl() {
    for ((i=1;i<=${#domains[@]};i++ )); do
 		hint="${domains[$i-1]}"
 		echo -e "${GREEN}${i}${PLAIN}) ${hint}"
    done
    read -p "请选择域名[1-3] (默认: ${domains[0]}):" pick
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
    if [[ "$pick" = "3" ]]; then
		read -p $'请输入自定义域名: ' DOMAIN
		if [[ -z "${DOMAIN}" ]]; then
			colorEcho $RED "错误, 请输入域名"
			echo ""
			exit 1
		else
			colorEcho $BLUE "域名：${DOMAIN}"
			echo ""
			read -p $'请设置私钥路径\n(不输默认生成): ' KEY
			colorEcho $BLUE "私钥路径：${KEY}"
			echo ""
			read -p $'请设置证书路径\n(不输默认生成): ' CERT
			colorEcho $BLUE "证书路径：${CERT}"
			echo ""
		fi
    else
		KEY="/etc/hysteria/hysteria.key"
		CERT="/etc/hysteria/hysteria.crt"
		openssl ecparam -genkey -name prime256v1 -out ${KEY}
		openssl req -new -x509 -days 36500 -key ${KEY} -out ${CERT} -subj "/CN=${domains[$pick-1]}"
		chmod +x /etc/hysteria/hysteria.*
		colorEcho $BLUE "域名：${domains[$pick-1]}"
		echo ""
    fi
}

Set_proxy() {
    read -p $'设置伪装域名[去https://]\n(默认icloud): ' PROXY
    [[ -z "${PROXY}" ]] && PROXY="www.icloud.com"
    colorEcho $BLUE "伪装域名：${PROXY}"
	echo ""
}

Write_config(){
    cat > ${conf}<<-EOF
listen: :$PORT

tls:
  cert: $CERT
  key: $KEY

auth:
  type: password
  password: $PASS

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

masquerade: 
  type: proxy
  proxy:
    url: https://${PROXY}
    rewriteHost: true
EOF
}

Write_client(){
    echo " hysteria配置文件:  ${conf}" >> ${client}
    echo " hysteria配置信息：" >> ${client}
    if [[ -z "$IP6" ]]; then
		echo "   地址(IP4):  ${IP4}" >> ${client}
    else
		echo -e "   地址(IP4):  ${IP4}" >> ${client}
		echo -e "   地址(IP6):  ${IP6}" >> ${client}
    fi
    if [[ ! -z ${FPORT} ]]; then
		echo "   端口(PORT)： ${FPORT},$((${FPORT}+1))-${EPORT}" >> ${client}
    elif [[ -z ${FPORT} ]]; then
		echo "   端口(PORT)： ${PORT}" >> ${client}
    fi
    echo "   密码(PASS)： ${PASS}" >> ${client}
    echo "   域名(DOMAIN)： ${DOMAIN}" >> ${client}
    echo "   伪装域名(PROXY)： ${PROXY}" >> ${client}
}

Install_hysteria(){
    Generate_conf
    Write_config
    Write_client
    Download_hysteria
    Deploy_hysteria
    colorEcho $BLUE "安装完成"
    echo ""
    cat ${client}
}

Start_hysteria(){
    systemctl start hysteria
    colorEcho $BLUE " hysteria已启动"
}

Restart_hysteria(){
    systemctl restart hysteria
    colorEcho $BLUE " hysteria已重启"
}

Stop_hysteria(){
    systemctl stop hysteria
    colorEcho $BLUE " hysteria已停止"
}

Uninstall_hysteria(){
    read -p $' 是否卸载hysteria？[y/n]\n (默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
		systemctl stop hysteria
		systemctl disable hysteria >/dev/null 2>&1
		rm -rf /etc/systemd/system/hysteria.service
		rm -rf /etc/hysteria
		systemctl daemon-reload
		colorEcho $BLUE " hysteria已经卸载完毕"
    else
		colorEcho $BLUE " 取消卸载"
    fi
}

checkSystem
menu() {
	clear
	echo "################################"
	echo -e "#      ${RED}Hysteria一键安装脚本${PLAIN}    #"
	echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)         #"
	echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com   #"
	echo -e "# ${GREEN}频道${PLAIN}: https://t.me/SlothNews #"
	echo "################################"
	echo " ----------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装Hysteria"
	echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载Hysteria${PLAIN}"
	echo " ----------------------"
 	echo -e "  ${GREEN}3.${PLAIN}  启动Hysteria"
	echo -e "  ${GREEN}4.${PLAIN}  重启Hysteria"
	echo -e "  ${GREEN}5.${PLAIN}  停止Hysteria"
	echo " ----------------------"
	echo -e "  ${GREEN}6.${PLAIN}  查看Hysteria配置"
	echo " ----------------------"
	echo -e "  ${GREEN}0.${PLAIN}  退出"
	echo ""
	echo -n " 当前状态："
	statusText
	echo 

	read -p " 请选择操作[0-6]：" answer
	case $answer in
		0)
			exit 0
			;;
		1)
			Install_hysteria
			;;
		2)
			Uninstall_hysteria
			;;
		3)
			Start_hysteria
			;;
		4)
			Restart_hysteria
			;;
		5)
			Stop_hysteria
			;;
		6)
			cat ${client}
			;;
		*)
			colorEcho $RED " 请选择正确的操作！"
   			sleep 2s
			menu
			;;
	esac
}
menu
