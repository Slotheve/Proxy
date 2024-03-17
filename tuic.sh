#!/bin/bash
# Author: Slotheve<https://slotheve.com>

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

CPU=`uname -m`
conf="/etc/tuic/tuic.json"

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
    if [[ ! -f $conf ]]; then
        echo 0
        return
    fi
    tmp=`grep server ${conf} | awk -F '0:' '{print $2}' | cut -d: -f1 | cut -d\" -f1`
    res=`ss -nutlp| grep ${tmp} | grep -i tuic`
    if [[ -z $res ]]; then
        echo 1
    else
        echo 2
        return
    fi
}

statusText() {
    res=`status`
    case ${res} in
        1)
            echo -e ${BLUE}Tuic:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        2)
            echo -e ${BLUE}Tuic:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            ;;
        *)
            echo -e ${BLUE}Tuic:${PLAIN} ${RED}未安装${PLAIN}
            ;;
    esac
}

Dependency(){
    if [[ ${OS} == "yum" ]]; then
        echo ""
        colorEcho $YELLOW "安装依赖中..."
        yum install wget -y >/dev/null 2>&1
        echo ""
    else
        echo ""
        colorEcho $YELLOW "安装依赖中..."
        apt install wget -y >/dev/null 2>&1
        echo ""
    fi
}

Download(){
    rm -rf /etc/tuic
    mkdir -p /etc/tuic
    archAffix
    DOWNLOAD_LINK="https://github.com/Slotheve/backup/raw/main/tuic-${CPU}"
    colorEcho $YELLOW "下载Tuic: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /etc/tuic/tuic ${DOWNLOAD_LINK}
    chmod +x /etc/tuic/tuic
	openssl ecparam -genkey -name prime256v1 -out /etc/tuic/private.key >/dev/null 2>&1
	openssl req -new -x509 -days 36500 -key /etc/tuic/private.key -out /etc/tuic/cert.crt -subj "/CN=www.bing.com" >/dev/null 2>&1
}

Generate(){
    Port
    Uuid
    Pass
}

Deploy(){
    cat > /etc/systemd/system/tuic.service<<-EOF
[Unit]
Description=Tuic Service
After=network.target

[Service]
User=root
ExecStart=/etc/tuic/tuic -c /etc/tuic/tuic.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable tuic
    systemctl start tuic
}

Port(){
    read -p $'请输入 Tuic 端口 [1-65535]\n(默认: 6666，回车): ' PORT
    [[ -z "${PORT}" ]] && PORT="6666"
    echo $((${PORT}+0)) &>/dev/null
    if [[ $? -eq 0 ]]; then
	if [[ ${PORT} -ge 1 ]] && [[ ${PORT} -le 65535 ]]; then
		colorEcho $BLUE "端口: ${PORT}"
		echo ""
	else
		colorEcho $RED "输入错误, 请输入正确的端口。"
		Port
	fi
    else
		colorEcho $RED "输入错误, 请输入数字。"
		Port
    fi
}

Uuid(){
    read -p $'请输入 Tuic 密钥\n(推荐随机生成，直接回车): ' UUID
    [[ -z "${UUID}" ]] && UUID=$(cat /proc/sys/kernel/random/uuid)
    if [[ "${#UUID}" != 36 ]]; then
		colorEcho $RED "请输入正确的密匙。"
		Uuid
    fi
    colorEcho $BLUE "UUID: ${UUID}"
}

Pass(){
    read -p $'请输入 Tuic 密码\n(推荐随机生成，直接回车): ' PASS
    [[ -z "${PASS}" ]] && PASS=`tr -dc A-Za-z0-9 </dev/urandom | head -c 8`
    colorEcho $BLUE "PASS: ${PASS}"
    echo ""
}

Write(){
    cat > $conf<<-EOF
{
    "server": "0.0.0.0:$PORT",
    "users": {
        "$UUID": "$PASS"
    },
    "certificate": "/etc/tuic/cert.crt",
    "private_key": "/etc/tuic/private.key",
    "congestion_control": "bbr",
    "log_level": "warn"
}
EOF
}

Install(){
    Generate
    Download
    Write
    Deploy
    colorEcho $BLUE "安装完成"
    echo ""
    ShowInfo
}

Restart(){
    systemctl restart tuic
    colorEcho $BLUE " Tuic已启动"
}

Stop(){
    systemctl stop tuic
    colorEcho $BLUE " Tuic已停止"
}

Uninstall(){
    read -p $' 是否卸载Tuic？[y/n]\n (默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        systemctl stop tuic
		systemctl disable tuic >/dev/null 2>&1
		rm -rf /etc/systemd/system/tuic.service
		rm -rf /etc/tuic
		systemctl daemon-reload
		colorEcho $BLUE " Tuic已经卸载完毕"
    else
        colorEcho $BLUE " 取消卸载"
    fi
}

ShowInfo() {
    if [[ ! -f $conf ]]; then
        colorEcho $RED " Tuic未安装"
        exit 1
    fi
        echo ""
        echo -e " ${BLUE}Tuic配置文件: ${PLAIN} ${RED}${conf}${PLAIN}"
        colorEcho $BLUE " Tuic配置信息："
        GetConf
        OutPut
}

GetConf() {
    port=`grep server ${conf} | awk -F '0:' '{print $2}' | cut -d: -f1 | cut -d\" -f1`
    pass=`grep ':' ${conf} | awk -F ':' '{print $2}' | cut -d\" -f2 | head -n3 | tail -n1`
    uuid=`grep '"' ${conf} | awk -F '"' '{print $2}' | head -n3 | tail -n1`
}

OutPut() {
    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}tuic${PLAIN}"
    echo -e "   ${BLUE}版本: ${PLAIN} ${RED} v5${PLAIN}"
    echo -e "   ${BLUE}端口: ${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密钥: ${PLAIN} ${RED}${uuid}${PLAIN}"
    echo -e "   ${BLUE}密码: ${PLAIN} ${RED}${pass}${PLAIN}"
    echo -e "   ${BLUE}加速: ${PLAIN} ${RED}bbr${PLAIN}"
    echo -e "   ${BLUE}Alpn: ${PLAIN} ${RED}none${PLAIN}"
    echo -e "   ${BLUE}TLS&SNI: ${PLAIN} ${RED}off${PLAIN}"
}

checkSystem
Dependency
menu() {
	clear
	echo "################################"
	echo -e "#       ${RED}Tuic一键安装脚本${PLAIN}       #"
	echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)         #"
	echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com   #"
	echo -e "# ${GREEN}频道${PLAIN}: https://t.me/SlothNews #"
	echo "################################"
	echo " ----------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装Tuic"
	echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载Tuic${PLAIN}"
	echo " ----------------------"
	echo -e "  ${GREEN}3.${PLAIN}  重启Tuic"
	echo -e "  ${GREEN}4.${PLAIN}  停止Tuic"
	echo " ----------------------"
	echo -e "  ${GREEN}5.${PLAIN}  查看Tuic配置"
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
			Install
			;;
		2)
			Uninstall
			;;
		3)
			Restart
			;;
		4)
			Stop
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
