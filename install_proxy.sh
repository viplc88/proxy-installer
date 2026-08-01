#!/bin/bash

# ======================================================
# Universal Linux Squid Proxy Installer
# Ubuntu Debian Alma Rocky CentOS RHEL Fedora Arch
# SSH Port + Squid + User Password + Speed Test
# ======================================================


set -e


clear


echo "======================================"
echo " Universal Squid Proxy Installer"
echo "======================================"


# ROOT CHECK

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi



# ==========================
# Detect OS
# ==========================


if [ -f /etc/os-release ]; then

    source /etc/os-release
    OS=$ID

else

    OS=$(uname -s)

fi


echo "OS detected: $OS"



# ==========================
# Detect Package Manager
# ==========================


if command -v apt >/dev/null 2>&1; then

    PKG="apt"


elif command -v dnf >/dev/null 2>&1; then

    PKG="dnf"


elif command -v yum >/dev/null 2>&1; then

    PKG="yum"


elif command -v pacman >/dev/null 2>&1; then

    PKG="pacman"


elif command -v zypper >/dev/null 2>&1; then

    PKG="zypper"


else

    echo "Unsupported Linux"
    exit 1

fi


echo "Package manager: $PKG"



# ==========================
# Input
# ==========================


echo ""

read -p "SSH Port [2222]: " SSH_PORT
SSH_PORT=${SSH_PORT:-2222}


read -p "Proxy Port [3128]: " SQUID_PORT
SQUID_PORT=${SQUID_PORT:-3128}


read -p "Proxy Username: " PROXY_USER


read -s -p "Proxy Password: " PROXY_PASS

echo ""





# ==========================
# Install Packages
# ==========================


install_packages(){


case $PKG in


apt)


apt update


apt install -y \
curl \
wget \
python3 \
python3-pip \
squid \
apache2-utils \
ufw \
ethtool


;;



dnf)


dnf install -y \
curl \
wget \
python3 \
python3-pip \
squid \
httpd-tools \
firewalld \
ethtool


systemctl enable firewalld
systemctl start firewalld


;;



yum)


yum install -y \
curl \
wget \
python3 \
python3-pip \
squid \
httpd-tools \
firewalld \
ethtool


systemctl enable firewalld
systemctl start firewalld


;;



pacman)


pacman -Sy --noconfirm \
curl \
wget \
python \
python-pip \
squid \
apache \
ethtool


;;



zypper)


zypper refresh


zypper install -y \
curl \
wget \
python3 \
python3-pip \
squid \
apache2-utils \
ethtool


;;


esac


}



install_packages





# ==========================
# SPEED TEST
# ==========================


echo ""

echo "======================================"
echo " VPS SPEED TEST"
echo "======================================"


python3 -m pip install speedtest-cli --break-system-packages 2>/dev/null || \
python3 -m pip install speedtest-cli



speedtest \
--secure \
--simple \
>/root/speedtest_result.txt || true



if [ -f /root/speedtest_result.txt ]; then


cat /root/speedtest_result.txt


fi



# ==========================
# NIC SPEED
# ==========================


echo ""

echo "======================================"
echo " NETWORK PORT SPEED"
echo "======================================"


NIC=$(ip route | grep default | awk '{print $5}')


if command -v ethtool >/dev/null; then

ethtool $NIC 2>/dev/null | grep Speed || true

fi






# ==========================
# Change SSH Port
# ==========================


echo ""

echo "Changing SSH Port..."


cp /etc/ssh/sshd_config \
/etc/ssh/sshd_config.backup



sed -i "/^#Port /c\Port $SSH_PORT" /etc/ssh/sshd_config


sed -i "/^Port /c\Port $SSH_PORT" /etc/ssh/sshd_config



# SELINUX


if command -v getenforce >/dev/null 2>&1; then


if [ "$(getenforce)" != "Disabled" ]; then


if command -v semanage >/dev/null; then


semanage port -a \
-t ssh_port_t \
-p tcp \
$SSH_PORT || true


fi


fi


fi




# Firewall SSH


if command -v ufw >/dev/null; then


ufw allow $SSH_PORT/tcp


ufw --force enable


fi



if command -v firewall-cmd >/dev/null; then


firewall-cmd \
--permanent \
--add-port=$SSH_PORT/tcp


firewall-cmd --reload


fi




systemctl restart sshd 2>/dev/null || \
systemctl restart ssh 2>/dev/null || true






# ==========================
# Configure Squid
# ==========================


echo ""

echo "Configuring Squid..."



AUTH_HELPER=$(find /usr -name basic_ncsa_auth 2>/dev/null | head -1)


if [ -z "$AUTH_HELPER" ]; then

echo "Squid auth helper not found"

exit 1

fi




mkdir -p /etc/squid/passwd



htpasswd -bc \
/etc/squid/passwd/squid_passwd \
"$PROXY_USER" \
"$PROXY_PASS"





cp /etc/squid/squid.conf \
/etc/squid/squid.conf.backup 2>/dev/null || true




cat > /etc/squid/squid.conf <<EOF


http_port $SQUID_PORT



auth_param basic program $AUTH_HELPER /etc/squid/passwd/squid_passwd

auth_param basic children 5

auth_param basic realm Squid Proxy

auth_param basic credentialsttl 2 hours



acl authenticated proxy_auth REQUIRED



http_access allow authenticated

http_access deny all



forwarded_for delete

via off


EOF






# Firewall Proxy


if command -v ufw >/dev/null; then


ufw allow $SQUID_PORT/tcp


fi



if command -v firewall-cmd >/dev/null; then


firewall-cmd \
--permanent \
--add-port=$SQUID_PORT/tcp


firewall-cmd --reload


fi






# Start Squid


systemctl enable squid


systemctl restart squid






# ==========================
# Result
# ==========================



SERVER_IP=$(curl -4 -s ifconfig.me)



clear


echo "======================================"
echo " INSTALL COMPLETE"
echo "======================================"



echo ""

echo "Server IP:"
echo $SERVER_IP



echo ""

echo "SSH:"
echo "$SERVER_IP:$SSH_PORT"



echo ""

echo "Proxy:"
echo "$SERVER_IP:$SQUID_PORT"



echo ""

echo "Username:"
echo "$PROXY_USER"



echo ""

echo "Password:"
echo "$PROXY_PASS"



echo ""

echo "Proxy Format:"

echo "$SERVER_IP:$SQUID_PORT:$PROXY_USER:$PROXY_PASS"



echo ""

echo "Speed Result:"
cat /root/speedtest_result.txt 2>/dev/null || true



echo ""

echo "======================================"
echo " DONE"
echo "======================================"
