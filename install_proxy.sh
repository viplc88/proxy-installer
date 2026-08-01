#!/bin/bash

# ======================================================
# Universal Squid Proxy Installer v3
# Ookla Speedtest + NIC Speed + Squid + SSH
#
# Support:
# Ubuntu Debian Alma Rocky CentOS RHEL Fedora
# Amazon Linux Oracle Linux
# ======================================================


set -e


clear


echo "======================================"
echo " Squid Proxy Installer v3"
echo " Network Benchmark Enabled"
echo "======================================"



if [ "$EUID" -ne 0 ]; then
echo "Run as root"
exit 1
fi



# ==========================
# Detect OS
# ==========================


if [ -f /etc/os-release ]; then

source /etc/os-release
OS=$ID

else

echo "Unknown OS"
exit 1

fi


echo "OS: $OS"



# ==========================
# Package Manager
# ==========================


if command -v apt >/dev/null; then

PKG="apt"

elif command -v dnf >/dev/null; then

PKG="dnf"

elif command -v yum >/dev/null; then

PKG="yum"

else

echo "Unsupported package manager"
exit 1

fi


echo "Package: $PKG"




# ==========================
# Input
# ==========================


echo ""

read -p "SSH Port [2222]: " SSH_PORT
SSH_PORT=${SSH_PORT:-2222}


read -p "Proxy Port [3128]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-3128}


read -p "Proxy Username: " PROXY_USER


read -s -p "Proxy Password: " PROXY_PASS

echo ""




# ==========================
# Install Base Package
# ==========================


install_base(){


case $PKG in


apt)

apt update

apt install -y \
curl \
wget \
gnupg \
ca-certificates \
ethtool \
squid \
apache2-utils \
ufw


;;


dnf)

dnf install -y \
curl \
wget \
ca-certificates \
ethtool \
squid \
httpd-tools \
firewalld


;;


yum)

yum install -y \
curl \
wget \
ca-certificates \
ethtool \
squid \
httpd-tools \
firewalld


;;


esac


}



install_base




# ==========================
# Install Ookla Speedtest
# ==========================


install_speedtest(){


echo ""
echo "Installing Ookla Speedtest..."


case $PKG in


apt)


curl -s \
https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh \
| bash


apt install -y speedtest


;;


dnf|yum)


curl -s \
https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh \
| bash


$PKG install -y speedtest


;;


esac


}



install_speedtest



# ==========================
# Network Test
# ==========================


echo ""

echo "======================================"
echo " NETWORK TEST"
echo "======================================"


NIC=$(ip route | grep default | awk '{print $5}')


echo "Interface:"
echo "$NIC"


echo ""


if command -v ethtool >/dev/null; then

NIC_SPEED=$(ethtool $NIC 2>/dev/null | grep Speed | awk '{print $2}')

if [ "$NIC_SPEED" = "Unknown!" ] || [ -z "$NIC_SPEED" ]; then

echo "NIC Speed: Virtual Interface (Provider does not expose limit)"

else

echo "NIC Speed: $NIC_SPEED"

fi

fi



echo ""


SERVER_IP=$(curl -4 -s https://api.ipify.org)


if [[ ! $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

SERVER_IP=$(hostname -I | awk '{print $1}')

fi



echo "Public IP:"
echo "$SERVER_IP"



echo ""

echo "Running Speedtest..."
echo "Please wait..."



speedtest \
--accept-license \
--accept-gdpr \
> /root/speedtest_result.txt || true



cat /root/speedtest_result.txt


echo ""

# ==========================
# CHANGE SSH PORT
# ==========================


echo ""

echo "Changing SSH port..."

cp /etc/ssh/sshd_config \
/etc/ssh/sshd_config.backup


sed -i "s/^#Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config

sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config



# SELINUX SSH PORT

if command -v semanage >/dev/null 2>&1; then

semanage port -a \
-t ssh_port_t \
-p tcp \
$SSH_PORT 2>/dev/null || true

fi




# ==========================
# FIREWALL SSH
# ==========================


if command -v ufw >/dev/null 2>&1; then


ufw allow $SSH_PORT/tcp

ufw --force enable


fi



if command -v firewall-cmd >/dev/null 2>&1; then


systemctl enable firewalld

systemctl start firewalld


firewall-cmd \
--permanent \
--add-port=$SSH_PORT/tcp


firewall-cmd --reload


fi




systemctl restart sshd 2>/dev/null || \
systemctl restart ssh 2>/dev/null || true





# ==========================
# SQUID CONFIGURATION
# ==========================


echo ""

echo "Configuring Squid..."



SQUID_AUTH=$(find /usr -name basic_ncsa_auth 2>/dev/null | head -1)



if [ -z "$SQUID_AUTH" ]; then

echo "Cannot find squid authentication helper"

exit 1

fi




mkdir -p /etc/squid/passwd



htpasswd -bc \
/etc/squid/passwd/squid_passwd \
"$PROXY_USER" \
"$PROXY_PASS"





if [ -f /etc/squid/squid.conf ]; then

cp /etc/squid/squid.conf \
/etc/squid/squid.conf.backup

fi





cat > /etc/squid/squid.conf <<EOF


# Squid Proxy v3


http_port $PROXY_PORT



auth_param basic program $SQUID_AUTH /etc/squid/passwd/squid_passwd

auth_param basic children 10

auth_param basic realm Squid Proxy

auth_param basic credentialsttl 4 hours



acl authenticated proxy_auth REQUIRED



http_access allow authenticated

http_access deny all



forwarded_for delete

request_header_access X-Forwarded-For deny all

via off


EOF






# ==========================
# FIREWALL PROXY PORT
# ==========================



if command -v ufw >/dev/null 2>&1; then


ufw allow $PROXY_PORT/tcp


fi



if command -v firewall-cmd >/dev/null 2>&1; then


firewall-cmd \
--permanent \
--add-port=$PROXY_PORT/tcp


firewall-cmd --reload


fi





# ==========================
# START SQUID
# ==========================



echo ""

echo "Starting Squid..."


systemctl enable squid


systemctl restart squid





# ==========================
# CHECK SQUID
# ==========================


if systemctl is-active --quiet squid; then

SQUID_STATUS="RUNNING"

else

SQUID_STATUS="FAILED"

fi





# ==========================
# SAVE INFORMATION
# ==========================



cat > /root/proxy_info.txt <<EOF


==================================
SQUID PROXY INFORMATION
==================================


IP:
$SERVER_IP


SSH:
$SERVER_IP:$SSH_PORT


PROXY:
$SERVER_IP:$PROXY_PORT


USERNAME:
$PROXY_USER


PASSWORD:
$PROXY_PASS


FORMAT:

$SERVER_IP:$PROXY_PORT:$PROXY_USER:$PROXY_PASS


SQUID STATUS:

$SQUID_STATUS


==================================

EOF





# ==========================
# FINAL RESULT
# ==========================



clear


echo "======================================"

echo " INSTALL COMPLETE"

echo "======================================"


echo ""

cat /root/proxy_info.txt



echo ""

echo "Network Test:"

cat /root/speedtest_result.txt 2>/dev/null || true



echo ""

echo "======================================"

echo " DONE"

echo "======================================"
