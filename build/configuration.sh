#!/bin/sh

#TODO
# 1. Auto run after OS installed
# 2. Let user input cobbler password
# 3. Let user input system password

PASSWORD='zhu88jie'
MYSQL_PASSWORD='zhu88jie'

sourcedir='/root/software'

function get_input() {
    read -p "$1 (缺省: $2): " VAR
    if [ -z $VAR ]; then
        VAR=$2
    fi
    eval $3=$VAR
}

function answer_yes_or_no() {
    while :
    do
        read -p "$1 (yes/no): " VAR
        if [ "$VAR" = "yes" -o "$VAR" = "no" ]; then
            break
        fi
    done
    eval $2=$VAR
}

function splash_screen() {
    clear
    echo -e "\n            欢迎使用分布式存储系统\n"
}

function config_network() {
    while :
    do
        splash_screen

        echo -e "开始配置网络:\n"
        default_route=$(ip route show)
        default_interface=$(echo $default_route | sed -e 's/^.*dev \([^ ]*\).*$/\1/' | head -n 1)
        address=$(ip addr show label $default_interface scope global | awk '$1 == "inet" { print $2,$4}')
        ip=$(echo $address | awk '{print $1 }')
        ip=${ip%%/*}
        broadcast=$(echo $address | awk '{print $2 }')
        netmask=$(route -n |grep 'U[ \t]' | head -n 1 | awk '{print $3}')
        gateway=$(route -n | grep 'UG[ \t]' | awk '{print $2}')
        hostname=`hostname`
        dns=$(cat /etc/resolv.conf | grep nameserver | head -n 1 | awk '{print $2}')

        get_input '请输入Hostname' $hostname HOSTNAME 
        get_input '提供PXE安装服务的网卡' $default_interface INTERFACE
        get_input 'IP地址' $ip IPADDR
        get_input '掩码' $netmask NETMASK
        get_input '网关地址' $gateway GATEWAY
        SUBNET=$(echo $IPADDR | cut -d. -f1-3)'.0'
        dhcp_start=$(echo $IPADDR | cut -d. -f1-3)'.100'
        dhcp_end=$(echo $IPADDR | cut -d. -f1-3)'.254'
        get_input 'DHCP起始地址' $dhcp_start DHCP_START
        get_input 'DHCP结束地址' $dhcp_end DHCP_END

        echo -e "\n输入的网络配置参数:" 
        echo "    Hostname: $HOSTNAME" 
        echo "    IP地址: $IPADDR" 
        echo "    掩码: $NETMASK" 
        echo "    网关地址: $GATEWAY" 
        echo "    DHCP起始地址: $DHCP_START" 
        echo -e "    DHCP结束地址: $DHCP_END\n" 

        answer_yes_or_no "请确认以上信息是否正确:" ANSWER
        if [ "$ANSWER" = "yes" ]; then
            break
        fi
    done

    cat > /etc/sysconfig/network-scripts/ifcfg-$INTERFACE <<EOF
DEVICE="$INTERFACE"
BOOTPROTO="static"
GATEWAY="$GATEWAY"
IPADDR="$IPADDR"
NETMASK="$NETMASK"
ONBOOT="yes"
EOF
    cat > /etc/sysconfig/network <<EOF
NETWORKING=yes
HOSTNAME=$HOSTNAME
GATEWAY=$GATEWAY
EOF
    sed -i "s/^hosts:.*/hosts: files/" /etc/nsswitch.conf
    service network restart    
}

function generate_sshkey() {
    mkdir -p /root/.ssh
    ssh-keygen -f /root/.ssh/id_rsa -t rsa -N ''
    cat >> /root/.ssh/config <<EOF
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
EOF
}

function config_cobbler() {
    cp /etc/cobbler/settings /etc/cobbler/settings.bak
    cp /etc/cobbler/dhcp.template /etc/cobbler/dhcp.template.bak

    mkdir -p /var/lib/cobbler/loaders
    cp $sourcedir/cobbler/loaders/* /var/lib/cobbler/loaders

    encrypted_password=`openssl passwd -1 -salt 'a%fiw#ewr' $PASSWORD`
    sed -i "s/^default_password_crypted.*/default_password_crypted: \"$encrypted_password\"/" /etc/cobbler/settings
    
    sed -i "s/^server: 127.0.0.1/server: $IPADDR/" /etc/cobbler/settings
    sed -i "s/^next_server: 127.0.0.1/next_server: $IPADDR/" /etc/cobbler/settings
    sed -i "s/manage_dhcp: 0/manage_dhcp: 1/" /etc/cobbler/settings
    
    sed -i "s/disable.*= yes/disable = no/" /etc/xinetd.d/tftp
    sed -i "s/disable.*= yes/disable = no/" /etc/xinetd.d/rsync
    
    sed -i "s#^subnet.*#subnet $SUBNET netmask $NETMASK {#" /etc/cobbler/dhcp.template
    sed -i "s/option routers.*192.168.*/option routers $GATEWAY;/" /etc/cobbler/dhcp.template
    sed -i "/option domain-name-servers.*192.168.*/d" /etc/cobbler/dhcp.template
    sed -i "s/option subnet-mask.*255.255.255.0.*/option subnet-mask $NETMASK;/" /etc/cobbler/dhcp.template
    sed -i "s/range dynamic-bootp.*192.168.*/range dynamic-bootp $DHCP_START $DHCP_END;/" /etc/cobbler/dhcp.template
}

function start_cobbler() {
    service cobblerd restart
    service xinetd restart
    service httpd start
    cobbler sync

    chkconfig cobblerd on
    chkconfig xinetd on
    chkconfig httpd on
}

function import_centos65() {
    mkdir /root/centos65
    mount -o loop $sourcedir/cobbler/centos65/CentOS-6.5-x86_64-minimal.iso /root/centos65
    cobbler import --path=/root/centos65/ --name=centos65 --arch=x86_64

    cp $sourcedir/cobbler/centos65/centos65.ks /var/lib/cobbler/kickstarts/
    cp -r $sourcedir/ceph /var/www/cobbler/ks_mirror

    sshkey=`cat /root/.ssh/id_rsa.pub`
    sed -i "s#ssh-rsa.*#$sshkey#" /var/lib/cobbler/kickstarts/centos65.ks
    sed -i "s#10\.20\.0\.3#$IPADDR#" /var/lib/cobbler/kickstarts/centos65.ks
    cobbler profile edit --name=centos65-x86_64 --distro=centos65-x86_64 --kickstart=/var/lib/cobbler/kickstarts/centos65.ks

    cobbler sync
}

function install_ntp_server() {
    sed -i "s#^server.*##" /etc/ntp.conf
    echo "server 127.127.1.0" >> /etc/ntp.conf
    echo "fudge 127.127.1.0 stratum 10" >> /etc/ntp.conf
    echo "restrict $SUBNET mask $netmask nomodify notrap" >> /etc/ntp.conf
    chkconfig ntpd on
    service ntpd start
}

function install_ceph_deploy() {
    rpm -ivh $sourcedir/ceph_deploy/packages/python-setuptools-0.6.10-3.el6.noarch.rpm
    rpm -ivh $sourcedir/ceph_deploy/packages/python-pip-1.3.1-4.el6.noarch.rpm

    mkdir /root/.pip
    cp $sourcedir/ceph_deploy/pip.conf /root/.pip
    cp $sourcedir/ceph_deploy/pydistutils.cfg /root/.pydistutils.cfg

    mkdir -p /var/www/cobbler/ks_mirror/ceph_deploy
    cp -r $sourcedir/ceph_deploy/pip /var/www/cobbler/ks_mirror/ceph_deploy
    pip install ceph-deploy
}

function config_mysql() {
    service mysqld start
    chkconfig mysqld on

    mysql_secure_installation <<EOF

Y
$MYSQL_PASSWORD
$MYSQL_PASSWORD
Y
Y
Y
EOF

mysql -u root -p$MYSQL_PASSWORD <<EOF
CREATE DATABASE dstorage;  
GRANT ALL ON dstorage.* TO 'dstorage'@'%' IDENTIFIED BY 'dstorage';  
commit;  
EOF
    service mysqld restart
}

config_network
config_cobbler
start_cobbler

generate_sshkey
import_centos65

install_ntp_server
install_ceph_deploy
config_mysql
