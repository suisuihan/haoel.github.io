#!/bin/bash

# Author
# original author: https://github.com/gongzili456
# modified by: https://github.com/haoel

# Ubuntu 18.04 系统环境


update_core(){
    echo "更新系统内核"
    sudo apt install -y -qq --install-recommends linux-generic-hwe-18.04
    sudo apt autoremove

    echo "内核更新完成，重新启动机器。。。"
    sudo reboot
}

check_bbr(){
    has_bbr=$(lsmod | grep bbr)

    # 如果已经发现 bbr 进程
    if [ -n "$has_bbr" ] ;then
        echo "TCP BBR 拥塞控制算法已经启动"
    else
        start_bbr
    fi
}

start_bbr(){
    echo "启动 TCP BBR 拥塞控制算法"
    sudo modprobe tcp_bbr
    echo "tcp_bbr" | sudo tee --append /etc/modules-load.d/modules.conf
    echo "net.core.default_qdisc=fq" | sudo tee --append /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee --append /etc/sysctl.conf
    sudo sysctl -p
    sysctl net.ipv4.tcp_available_congestion_control
    sysctl net.ipv4.tcp_congestion_control
}

install_bbr() {
    # 如果内核版本号满足最小要求
    if [ $VERSION_CURR > $VERSION_MIN ]; then
        check_bbr
    else
        update_core
    fi
}

install_docker() {
    echo "开始安装 Docker CE"
    curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
        "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu \
        $(lsb_release -cs) \
        stable"
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce
}

install_certbot() {
    echo "开始安装 certbot"
    sudo apt-get update -qq
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository universe
    sudo add-apt-repository ppa:certbot/certbot
    sudo apt-get update -qq
    sudo apt-get install -y certbot
}

create_cert() {
    echo "开始生成 SSL 证书"
    read -p "请输入你要使用的域名: " domain

    create_cert $domain
    sudo certbot certonly --standalone -d $domain

}

install_gost() {

    echo "准备启动 Gost 代理程序，为了安全，需要使用用户名与密码进行认证。"
    read -p "请输入你要使用的域名：" DOMAIN
    read -p "请输入你要使用的用户名: " USER
    read -p "请输入你要使用的密码: " PASS
    read -p "请输入HTTP/2需要侦听的端口号(443)：" PORT 

    if [[ -z "${PORT// }" ]] || ! [[ "${PORT}" =~ ^[0-9]+$ ]] || ! [ "$PORT" -ge 1 -a "$PORT" -le 655535 ]; then
        echo "非法端口，使用默认端口443！"
        PORT=443
    fi

    BIND_IP=0.0.0.0
    CERT_DIR=/etc/letsencrypt/
    CERT=${CERT_DIR}/live/${DOMAIN}/fullchain.pem
    KEY=${CERT_DIR}/live/${DOMAIN}/privkey.pem

    docker run -d --name gost \
        -v ${CERT_DIR}:${CERT_DIR}:ro \
        --net=host ginuerzh/gost \
        -L "http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400"
}

create_cront_job(){
    echo "0 0 1 * * /usr/bin/certbot renew --force-renewal" >> /var/spool/cron/crontabs/root
    echo "5 0 1 * * /usr/bin/docker restart gost" >> /var/spool/cron/crontabs/root
}


install_shadowsocks(){

    echo "准备启动 ShadowSocks 代理程序，为了安全，需要使用用户名与密码进行认证。"
    read -p "请输入你要使用的密码: " PASS
    read -p "请输入ShadowSocks需要侦听的端口号(1984)：" PORT 

    BIND_IP=0.0.0.0

    if [[ -z "${PORT// }" ]] || ! [[ "${PORT}" =~ ^[0-9]+$ ]] || ! [ "$PORT" -ge 1 -a "$PORT" -le 655535 ]; then
        echo "非法端口，使用默认端口1984！"
        PORT=1984
    fi 

    sudo docker run -dt --name ss \
        -p ${PORT}:${PORT} mritd/shadowsocks \
        -s "-s ${BIND_IP} -p ${PORT} -m aes-256-cfb -k ${PASS} --fast-open"
}

install_vpn(){

    echo "准备启动 VPN/L2TP 代理程序，为了安全，需要使用用户名与密码进行认证。"
    read -p "请输入你要使用的用户名: " USER
    read -p "请输入你要使用的密码: " PASS
    read -p "请输入你要使用的PSK Key: " PSK

    sudo docker run -d  --privileged \
        -e PSK=${PSK} \
        -e USERNAME=${USER} -e PASSWORD=${PASS} \
        -p 500:500/udp \
        -p 4500:4500/udp \
        -p 1701:1701/tcp \
        -p 1194:1194/udp  \
        siomiz/softethervpn
}

install_brook(){
    wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/brook.sh && chmod +x brook.sh && bash brook.sh
}

init(){
    VERSION_CURR=$(uname -r | awk -F '-' '{print $1}')
    VERSION_MIN="4.9.0"

    OIFS=$IFS  # Save the current IFS (Internal Field Separator)
    IFS=','    # New IFS

    COLUMNS=50
    echo -e "\n菜单选项\n"

    while [ 1 == 1 ]
    do
        PS3="Please select a option: "
        re='^[0-9]+$'
        select opt in "安装 TCP BBR 拥塞控制算法" "安装 Docker 服务程序" "安装 Let's crypt 证书" "安装 Gost HTTP/2 代理服务" \
                      "安装 ShadowSocks 代理服务" "安装 VPN/L2TP 服务" "安装 Brook 代理服务" "创建证书更新 CronJob" "退出" ; do
            if ! [[ $REPLY =~ $re ]] ; then
                echo -e "${COLOR_ERROR}Invalid option. Please input a number.${COLOR_NONE}"
                break;
            elif (( REPLY == 1 )) ; then
                install_bbr
                break;
            elif (( REPLY == 2 )) ; then
                install_docker
                break
            elif (( REPLY == 3 )) ; then
                install_certbot
                loop=1
                break
            elif (( REPLY == 4 )) ; then
                install_gost
                break
            elif (( REPLY == 5  )) ; then
                install_shadowsocks
                break
            elif (( REPLY == 6 )) ; then
                install_vpn
                break
            elif (( REPLY == 7 )) ; then
                install_brook
                break
            elif (( REPLY == 8 )) ; then
                create_cront_job
                break
            elif (( REPLY == 9 )) ; then
                exit
            else
                echo -e "${COLOR_ERROR}Invalid option. Try another one.${COLOR_NONE}"
            fi
        done
    done

     IFS=$OIFS  # Restore the IFS
}

init
