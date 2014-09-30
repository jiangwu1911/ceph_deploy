#!/bin/sh

#TODO
# 1. Let user input network parameters
# 2. Replace ip address in dhcp template, cent65.ks...
# 3. Let user input cobbler password
# 4. Let user input system password

local_ip=10.20.0.3
subnet=10.20.0.0
netmask=255.255.255.0
router=10.20.0.2
dns=10.20.0.2
range_start=10.20.0.100
range_end=10.20.0.254
password='abc123'

sourcedir='/root/software'

function config_network() {
    sed -i "s/^hosts:.*/hosts: files/" /etc/nsswitch.conf
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
    mkdir -p /var/lib/cobbler/loaders
    cp $sourcedir/cobbler/loaders/* /var/lib/cobbler/loaders

    encrypted_password=`openssl passwd -1 -salt 'a%fiw#ewr' $password`
    sed -i "s/^default_password_crypted.*/default_password_crypted: \"$encrypted_password\"/" /etc/cobbler/settings
    
    sed -i "s/^server: 127.0.0.1/server: $local_ip/" /etc/cobbler/settings
    sed -i "s/^next_server: 127.0.0.1/next_server: $local_ip/" /etc/cobbler/settings
    sed -i "s/manage_dhcp: 0/manage_dhcp: 1/" /etc/cobbler/settings
    
    sed -i "s/disable.*= yes/disable = no/" /etc/xinetd.d/tftp
    sed -i "s/disable.*= yes/disable = no/" /etc/xinetd.d/rsync
    
    sed -i "s/^subnet.*/subnet $subnet netmask $netmask {/" /etc/cobbler/dhcp.template
    sed -i "s/option routers.*192.168.*/option routers $router;/" /etc/cobbler/dhcp.template
    sed -i "s/option domain-name-servers.*192.168.*/option domain-name-servers $router;/" /etc/cobbler/dhcp.template
    sed -i "s/option subnet-mask.*255.255.255.0.*/option subnet-mask $netmask;/" /etc/cobbler/dhcp.template
    sed -i "s/range dynamic-bootp.*192.168.*/range dynamic-bootp $range_start $range_end;/" /etc/cobbler/dhcp.template
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
    cobbler profile edit --name=centos65-x86_64 --distro=centos65-x86_64 --kickstart=/var/lib/cobbler/kickstarts/centos65.ks

    cobbler sync
}

function install_ntp_server() {
    sed -i "s#^server.*##" /etc/ntp.conf
    echo "server 127.127.1.0" >> /etc/ntp.conf
    echo "fudge 127.127.1.0 stratum 10" >> /etc/ntp.conf
    echo "restrict $subnet mask $netmask nomodify notrap" >> /etc/ntp.conf
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

config_network
config_cobbler
start_cobbler

generate_sshkey
import_centos65

install_ntp_server
install_ceph_deploy
