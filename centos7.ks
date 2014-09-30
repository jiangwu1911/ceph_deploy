install
lang en_GB.UTF-8
keyboard us
timezone Australia/Melbourne
auth --useshadow --enablemd5
selinux --disabled
firewall --disabled
services --enabled=NetworkManager,sshd
eula --agreed
ignoredisk --only-use=sda
$SNIPPET('network_config')
reboot

bootloader --location=mbr
zerombr
clearpart --all --initlabel
part swap --asprimary --fstype="swap" --size=1024
part /boot --fstype xfs --size=200
part pv.01 --size=1 --grow
volgroup rootvg01 pv.01
logvol / --fstype xfs --name=lv01 --vgname=rootvg01 --size=1 --grow
 
rootpw --iscrypted $6$XmAncpkAdpDoR5bO$.FI0THeFcxkxxIvXKr3HNh5gYdk1P2WJA9XfM1XOm3b18MpwWrjL9TNqWAFk7CrgwfKeaZd0CEX6UddBUr9CT.

repo --name=base --baseurl=http://10.0.10.10/cobbler/ks_mirror/centos7-x86_64/
url --url="http://10.0.10.10/cobbler/ks_mirror/centos7-x86_64/"

%pre
$SNIPPET('pre_install_network_config')
%end
 
%packages --nobase --ignoremissing
@core
%end

%post 
$SNIPPET('post_install_network_config')

# Config yum repo
rm -f /etc/yum.repos.d/*
cat > /etc/yum.repos.d/centos.repo <<EOF
[base]
name=CentOS-$releasever - Base
baseurl=http://mirrors.sohu.com/centos/7/os/x86_64/
gpgcheck=0
enabled=1

[epel]
name=epel
baseurl=http://mirrors.sohu.com/fedora-epel/7/x86_64/
gpgcheck=0
enabled=1
EOF

# Config ssh key
cd /root
mkdir --mode=700 .ssh
cat >> .ssh/authorized_keys << "PUBLIC_KEY"
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAuBwGpXBe9BaWEDHGg0T016kRgRvAPVDpJfnx9AES+u8hg/t0zs9/48Lx+JBXvhO7KtFTqlG12Iy20jHr/wtbmh/e+ffSkVUtPbHGDwXaIiPTWYJXWw2IJIleMd2zYyLxnaAO7c7oS73BzX+8pU5lGbY6UW+eQSyLFdHyEBqMgbD/IMrIHmP4GiEi87FKtNfmzTatS+bIrzXSVE/YnYhsK5pbHb9lXSCAO2J4HU60VUinsL3xwLuu3TAOvPE9Hd2Df5f2BYq96uiD6LYobohaytsu3a8+J85CskYgEaIkLGtHSL4ZrPEEYWi8zWq/uYFNBR1Sd2xorkQ0HeJGCvuDDw== root@cobbler
PUBLIC_KEY

chmod 600 .ssh/authorized_keys

cat >> .ssh/config <<EOF
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
EOF

echo "GATEWAYDEV=ens34" >> /etc/sysconfig/network

%end
