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

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

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
    Set_up
	Set_down
	echo "net.core.rmem_max=16777216" >> sysctl.conf
	echo "net.core.wmem_max=16777216" >> sysctl.conf
	sysctl -p
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

Set_pass() {
    read -p $'请设置hysteria密码\n(默认随机生成, 回车): ' PASS
    [[ -z "$PASS" ]] && PASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1`
	colorEcho $BLUE " 密码：$PASS"
    echo ""
}

Set_port(){
    read -p $'请输入hysteria端口 [1-65535]\n(默认: 443，回车): ' PORT
    [[ -z "${PORT}" ]] && PORT="443"
    echo $((${PORT}+0)) &>/dev/null
    if [[ $? -eq 0 ]]; then
	if [[ ${PORT} -ge 1 ]] && [[ ${PORT} -le 65535 ]]; then
		colorEcho $BLUE "端口: ${PORT}"
		echo ""
	else
		colorEcho $RED "输入错误, 请输入正确的端口。"
		Set_port
	fi
    else
		colorEcho $RED "输入错误, 请输入数字。"
		Set_port
    fi
}

Set_ssl() {
	read -p $'请输入解析到VPS的域名\n(请勿开启CF小云朵): ' DOMAIN
	if [[ -z "$DOMAIN" ]]; then
		colorEcho $RED "请输入域名"
		Set_domain
	else
		colorEcho $BLUE "域名: $DOMAIN"
		echo ""
		read -p $'请设置私钥路径\n(不输默认生成): ' KEY
		[[ -z "$KEY" ]] && mkdir -pv /etc/hysteria && openssl genrsa \
		-out /etc/hysteria/hysteria.key 2048 && chmod \
		+x /etc/hysteria/hysteria.key && KEY="/etc/hysteria/hysteria.key"
		colorEcho $BLUE "密钥路径：$KEY"
		echo ""
		read -p $'请设置证书路径\n(不输默认生成): ' CERT
		[[ -z "$CERT" ]] && openssl req -new -x509 -days 3650 -key /etc/hysteria/hysteria.key \
		-out /etc/hysteria/hysteria.crt -subj "/C=US/ST=LA/L=LAX/O=Hysteria/OU=Hysteria/CN=&DOMAIN" \
		&& chmod +x /etc/hysteria/hysteria.crt && CERT="/etc/hysteria/hysteria.crt"
		colorEcho $BLUE "证书路径：$CERT"
		echo ""
	fi
}

Set_up() {
	read -p $'请输入VPS上传带宽, 不超过85%的VPS带宽\n(格式: XX空格b/k/m/g/t): ' UP
	if [[ -z "$UP" ]]; then
		colorEcho $RED "请输入上传带宽"
		Set_bw
	else
		colorEcho $BLUE "上传带宽: $UP"
		echo ""
	fi
}

Set_down() {
	read -p $'请输入VPS下载带宽, 不超过80%的VPS带宽\n(格式: XX空格b/k/m/g/t): ' DOWN
	if [[ -z "$DOWN" ]]; then
		colorEcho $RED "请输入下载带宽"
		Set_bw
	else
		colorEcho $BLUE "下载带宽: $DOWN"
		echo ""
	fi
}

Write_config(){
    cat > ${conf}<<-EOF
listen: :443

tls:
  cert: $CERT
  key: $KEY

auth:
  type: password
  password: $PASS

bandwidth:
  up: $UP
  down: $DOWN

masquerade: 
  type: proxy
  proxy:
    url: https://www.icloud.com/
    rewriteHost: true
  listenHTTP: :80 
  listenHTTPS: :443 
  forceHTTPS: true

# domain: $DOMAIN
EOF
}

Install_hysteria(){
    Generate_conf
	Write_config
	Download_hysteria
	Deploy_hysteria
    colorEcho $BLUE "安装完成"
    echo ""
    ShowInfo
}

Restart_hysteria(){
    systemctl restart hysteria
    colorEcho $BLUE " hysteria已启动"
}

Stop_hysteria(){
    systemctl stop hysteria
    colorEcho $BLUE " hysteria已停止"
}

Uninstall_hysteria(){
    read -p $'是否卸载hysteria？[y/n]\n (默认n, 回车): ' answer
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

ShowInfo() {
    echo ""
    echo -e " ${BLUE}hysteria配置文件: ${PLAIN} ${RED}${conf}${PLAIN}"
    colorEcho $BLUE " hysteria配置信息："
    GetConfig
    outputhysteria
}

GetConfig() {
    port=`grep listen ${conf} | head -n1 | awk -F ' ' '{print $2}' | cut -d: -f2`
    pass=`grep password ${conf} |  awk -F ':' '{print $2}' | tail -n1 | cut -d\  -f2`
	domain=`grep domain ${conf} | awk -F ':' '{print $2}' | cut -d\  -f2`
	up=`grep up ${conf} | awk -F ':' '{print $2}' | awk -F ' ' '{print $1$2}'`
	down=`grep down ${conf} | awk -F ':' '{print $2}' | awk -F ' ' '{print $1$2}'`
}

outputhysteria() {
    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}hysteria${PLAIN}"
    echo -e "   ${BLUE}地址(IP): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(PORT)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密码(PASS)：${PLAIN} ${RED}${pass}${PLAIN}"
	echo -e "   ${BLUE}域名(DOMAIN)：${PLAIN} ${RED}${domain}${PLAIN}"
	echo -e "   ${BLUE}上传(UP)：${PLAIN} ${RED}${up}${PLAIN}"
	echo -e "   ${BLUE}下载(DOWN)：${PLAIN} ${RED}${down}${PLAIN}"
}

checkSystem
menu() {
	clear
	echo "################################"
	echo -e "#      ${RED}Hysteria一键安装脚本${PLAIN}       #"
	echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)         #"
	echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com   #"
	echo -e "# ${GREEN}频道${PLAIN}: https://t.me/SlothNews #"
	echo "################################"
	echo " ----------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装Hysteria"
	echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载Hysteria${PLAIN}"
	echo " ----------------------"
	echo -e "  ${GREEN}3.${PLAIN}  重启Hysteria"
	echo -e "  ${GREEN}4.${PLAIN}  停止Hysteria"
	echo " ----------------------"
	echo -e "  ${GREEN}5.${PLAIN}  查看Hysteria配置"
	echo " ----------------------"
	echo -e "  ${GREEN}0.${PLAIN}  退出"
	echo ""
	echo -n " 当前状态："
	statusText
	echo 

	read -p " 请选择操作[0-5]：" answer
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
			Restart_hysteria
			;;
		4)
			Stop_hysteria
			;;
		5)
			ShowInfo
			;;
		*)
			colorEcho $RED " 请选择正确的操作！"
   			sleep 2s
			menu
			;;
	esac
}
menu
