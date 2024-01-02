#!/bin/bash
# Author: Slotheve<https://slotheve.com>

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

IP4=`curl -sL -4 ip.sb`
CPU=`uname -m`
systemd="/etc/systemd/system/ss.service"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

ciphers=(
AEAD_AES_256_GCM
AEAD_AES_128_GCM
AEAD_CHACHA20_POLY1305
)

ArchAffix(){
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

CheckSystem() {
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

Selectcipher() {
    for ((i=1;i<=${#cipher[@]};i++ )); do
 	  hint="${cipher[$i-1]}"
 	  echo -e "${GREEN}${i}${PLAIN}) ${hint}"
    done
    read -p "请选择加密[1-3] (默认: ${cipher[1]}):" pick
    [ -z "$pick" ] && pick=1
    expr ${pick} + 1 &>/dev/null
    if [ $? -ne 0 ]; then
	  colorEcho $RED "错误, 请选择[1-3]"
	  selectcipher
    fi
    if [[ "$pick" -lt 1 || "$pick" -gt ${#cipher[@]} ]]; then
	  colorEcho $RED "错误, 请选择[1-3]"
	  selectcipher
    fi
    cipher=${cipher[$pick-1]}
}

Download() {
    rm -rf /etc/ss/shadowsocks
    ArchAffix
    DOWNLOAD_LINK="https://raw.githubusercontent.com/Slotheve/backup/main/shadowsocks"
    colorEcho $YELLOW "下载ShadowSocks: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /etc/ss/shadowsocks ${DOWNLOAD_LINK}
    chmod +x /etc/ss/shadowsocks
}

Generate(){
    Set_port
    Selectcipher
    Set_pass
}

Deploy(){
    cd /etc/systemd/system
    cat > ss.service<<-EOF
[Unit]
Description=ShadowSocks
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
StartLimitBurst=5
StartLimitIntervalSec=500

[Service]
Type=simple
User=root
DynamicUser=true
ExecStart=/etc/ss/shadowsocks -s 0.0.0.0:${PORT} -cipher ${cipher} -password ${PASS} -udp
LimitNOFILE=1048576
LimitNPROC=51200
RestartSec=2s
Restart=on-failure
StandardOutput=null

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ss
    systemctl restart ss
}

Set_port(){
    read -p $'请输入 SS 端口 [1-65535]\n(默认: 6666，回车): ' PORT
    [[ -z "${PORT}" ]] && PORT="6666"
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

Set_pass(){
    read -p $'请输入 SS 密码\n(推荐随机生成，直接回车): ' PASS
    [[ -z "${PASS}" ]] && PASS=`tr -dc A-Za-z0-9 </dev/urandom | head -c 12`
    colorEcho $BLUE "PASS: ${PASS}"
    echo ""
}

Install(){
    Dependency
    Generate
    Download
    Deploy
    colorEcho $BLUE "安装完成"
    echo ""
    ShowInfo
}

Restart(){
    systemctl restart ss
    colorEcho $BLUE " SS已启动"
}

Stop(){
    systemctl stop ss
    colorEcho $BLUE " SS已停止"
}

Uninstall(){
    read -p $' 是否卸载SS？[y/n]\n (默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
      systemctl stop ss
	  systemctl disable ss >/dev/null 2>&1
	  rm -rf /etc/systemd/system/ss.service
	  rm -rf /etc/ss
	  systemctl daemon-reload
	  colorEcho $BLUE " SS已经卸载完毕"
    else
	  colorEcho $BLUE " 取消卸载"
    fi
}

ShowInfo() {
    if [[ ! -f ${systemd} ]]; then
	  colorEcho $RED " SS未安装"
 	  exit 1
    fi
    echo ""
    echo -e " ${BLUE}SS配置文件: ${PLAIN} ${RED}${systemd}${PLAIN}"
    colorEcho $BLUE " SS配置信息："
    GetConfig
    OutConfig
}

GetConfig() {
    port=`grep cipher ${systemd} | awk -F '=' '{print $2}' | cut -d: -f2 | cut -d- -f1`
	cipher=`grep cipher ${systemd} | awk -F '=' '{print $2}' | cut -d' ' -f5`
    pass=`grep cipher ${systemd} | awk -F '=' '{print $2}' | cut -d' ' -f7`
}

OutConfig() {
    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}ShadowSocks${PLAIN}"
    echo -e "   ${BLUE}地址(IP): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}SS端口(PORT)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}SS加密：${CIPHER} ${RED}${cipher}${PLAIN}"
    echo -e "   ${BLUE}SS密码(PASS)：${PLAIN} ${RED}${pass}${PLAIN}"
}

ChangeConf(){
    Generate
    Deploy
    colorEcho $BLUE " 修改配置成功"
    ShowInfo
}

CheckSystem
Menu() {
	clear
	echo "################################"
	echo -e "#      ${RED}SS-GO一键安装脚本${PLAIN}       #"
	echo -e "# ${GREEN}作者${PLAIN}: 怠惰(Slotheve)         #"
	echo -e "# ${GREEN}网址${PLAIN}: https://slotheve.com   #"
	echo -e "# ${GREEN}频道${PLAIN}: https://t.me/SlothNews #"
	echo "################################"
	echo " ----------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装ShadowSocks"
	echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载ShadowSocks${PLAIN}"
	echo " ----------------------"
	echo -e "  ${GREEN}3.${PLAIN}  重启ShadowSocks"
	echo -e "  ${GREEN}4.${PLAIN}  停止ShadowSocks"
	echo " ----------------------"
	echo -e "  ${GREEN}5.${PLAIN}  查看SS配置"
	echo -e "  ${GREEN}6.${PLAIN}  修改SS配置"
	echo " ----------------------"
	echo -e "  ${GREEN}0.${PLAIN}  退出"
	echo ""
	echo -n " 当前状态："
	echo 

	read -p " 请选择操作[0-6]：" answer
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
		6)
			ChangeConf
			;;
		*)
			colorEcho $RED " 请选择正确的操作！"
   			sleep 1.5s
			menu
			;;
	esac
}
Menu
