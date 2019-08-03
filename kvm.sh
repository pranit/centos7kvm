#!/bin/bash
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root user " 
   exit 1
fi

echo ""
echo "Please Copy RHEL/CentOS7 iso in /tmp" 

if [ -f /tmp/*.iso ]; then
        echo " ISO file found in /tmp "
else
        echo "ISO file not found in /tmp .. Exiting.."
        exit 1
fi

yum list  >> /dev/null || { echo 'Configure Yum' ; exit 1;}

yum update -y 
yum install -y qemu-kvm libvirt libvirt-python libguestfs-tools virt-install net-tools
systemctl enable libvirtd && systemctl start libvirtd

echo "Configuring Network Bridge"
interfacename="$(ifconfig | cut -d ':' -f1 | grep ens)"
echo "Modifying /etc/sysconfig/network-scripts/$interfacename"
echo "$interfacename is going to be modified- If you loose connection to vm, restore file from /tmp/backup manually"
mkdir -p /tmp/backup
cp /etc/sysconfig/network-scripts/ifcfg-$interfacename /tmp/backup/

ipaddress=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
subnet=$(ifconfig $interfacename | grep 'netmask' |  awk '{print $4}')
gateway=$(netstat -rn | grep UG  | awk '{print $2}')


cat <<EOT > /etc/sysconfig/network-scripts/ifcfg-br0
DEVICE="br0"
BOOTPROTO="static" 
ONBOOT="yes"  
TYPE="Bridge"
DELAY="0" 
IPADDR=$ipaddress
NETMASK=$subnet
EOT

cat <<EOT > /etc/sysconfig/network
NETWORKING=YES
HOSTNAME=$hostname
GATEWAY=$gateway
EOT


echo "" 
cat /etc/sysconfig/network-scripts/ifcfg-br0
echo ""
cat  /etc/sysconfig/network


echo ""
echo "Enabling IP forwarding"
sed -i -e 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf

echo""
echo "Removing IP entries from Ethernet interface"
sed -i -e 's/IPADDR/#IPADDR/g' /etc/sysconfig/network-scripts/ifcfg-$interfacename
sed -i -e 's/NETMASK/#NETMASK/g' /etc/sysconfig/network-scripts/ifcfg-$interfacename
sed -i -e 's/BOOTPROTO="dhcp"/BOOTPROTO="none"/g' /etc/sysconfig/network-scripts/ifcfg-$interfacename

grep -q -F "BRIDGE=br0" /etc/sysconfig/network-scripts/ifcfg-$interfacename || echo "BRIDGE=br0" >>  /etc/sysconfig/network-scripts/ifcfg-$interfacename

echo ""
echo "Setting SELINUX in Permissive Mode"
setenforce 0
sed -i -e 's/SELINUX=enforcing/SELINUX=permissive/g' 


echo ""
echo "Restarting Network - BRIDGE inteface should be working now"
service network restart


echo ""
echo "Creating kickstart file for minimal CentOS/RHEL7 installation"
cat <<EOT > /tmp/backup/vm1.cfg
install
lang en_US.UTF-8
network  --bootproto=static --gateway=192.168.199.2 --ip=192.168.199.131 --nameserver=8.8.8.8 --netmask=255.255.255.0 --ipv6=auto --activate --hostname=vm1
keyboard us
timezone Asia/Kolkata
auth --useshadow --enablemd5
selinux --disabled
firewall --disabled
services --enabled=NetworkManager,sshd
eula --agreed
ignoredisk --only-use=sda
reboot

bootloader --location=mbr
zerombr
clearpart --all --initlabel
part biosboot --fstype=biosboot --size=1 
part swap --asprimary --fstype="swap" --size=1024
part /boot --fstype ext4 --size=500
part pv.01 --size=1 --grow
volgroup rootvg01 pv.01
logvol / --fstype ext4 --name=lv01 --vgname=rootvg01 --size=100000
logvol /var --fstype ext4 --name=lv02 --vgname=rootvg01 --size=20000
logvol /var/log --fstype ext4 --name=lv03 --vgname=rootvg01 --size=10000
logvol /var/log/audit --fstype ext4 --name=lv04 --vgname=rootvg01 --size=5000
logvol /tmp --fstype ext4 --name=lv05 --vgname=rootvg01 --size=20000

rootpw password

%packages  --ignoremissing
@core
%end
EOT
echo ""
echo "kickstart file creation complete"

mkdir -p /opt/vm1
qemu-img create -f qcow2 /opt/vm1/vm1.qcow2 900G

#isofile=$(ls -lrt /tmp | grep iso | cut -d ' ' -f11 )
isofile=$(ls -t /tmp | grep .iso | head -1)
echo ""
echo "We're going to use $isofile for VM installation"

mount -o loop /tmp/$isofile /media
virt-install --network bridge=br0 --name vm1 --ram=1024 --vcpus=1 --disk path=/opt/vm1/vm1.qcow2,format=qcow2 --graphics none --location=/tmp/$isofile --os-type=linux  --initrd-inject=/tmp/backup/vm1.cfg  --extra-args='ks=file:/vm1.cfg console=ttyS0,115200n8 serial' --debug
