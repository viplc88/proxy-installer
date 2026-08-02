#!/bin/bash

# ======================================================
# Universal Squid Proxy Installer v3.1
#
# Features:
# - Auto Linux Detection
# - Disable SELinux
# - SSH Port Change Safe Mode
# - Squid Proxy + Auth
# - Ookla Speedtest
# - Network Information
#
# Support:
# Ubuntu Debian Alma Rocky CentOS RHEL Fedora Amazon
# ======================================================


set -e


clear


echo "======================================"
echo " Squid Proxy Installer v3.1"
echo " Production Build"
echo "======================================"



# ==========================
# ROOT CHECK
# ==========================


if [ "$EUID" -ne 0 ]; then

echo "Please run as root"

exit 1

fi





# ==========================
# DETECT OS
# ==========================


if [ -f /etc/os-release ]; then

source /etc/os-release

OS=$ID


else

echo "Cannot detect OS"

exit 1

fi



echo "Detected OS: $OS"





# ==========================
# PACKAGE MANAGER
# ==========================


if command -v apt >/dev/null 2>&1; then

PKG="apt"


elif command -v dnf >/dev/null 2>&1; then

PKG="dnf"


elif command -v yum >/dev/null 2>&1; then

PKG="yum"


else

echo "Unsupported package manager"

exit 1

fi



echo "Package Manager: $PKG"







# ==========================
# DISABLE SELINUX
# ==========================


if [ -f /etc/selinux/config ]; then


echo ""

echo "Disabling SELinux..."



sed -i \
's/^SELINUX=.*/SELINUX=disabled/' \
/etc/selinux/config



setenforce 0 2>/dev/null || true



fi







# ==========================
# USER INPUT
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
# INSTALL PACKAGES
# ==========================


install_packages(){


echo ""

echo "Installing packages..."



case $PKG in



apt)


apt update


apt install -y \
curl \
wget \
ca-certificates \
gnupg \
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



install_packages







# ==========================
# INSTALL OOKLA SPEEDTEST
# ==========================


install_speedtest(){


echo ""

echo "Installing Ookla Speedtest..."



if command -v speedtest >/dev/null 2>&1; then

return

fi



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
# NETWORK INFORMATION
# ==========================


echo ""

echo "======================================"

echo " NETWORK TEST"

echo "======================================"



NIC=$(ip route | grep default | awk '{print $5}')



echo "Interface:"
echo "$NIC"



echo ""



if command -v ethtool >/dev/null 2>&1; then


NIC_SPEED=$(ethtool $NIC 2>/dev/null | grep Speed | awk '{print $2}')



if [ "$NIC_SPEED" = "Unknown!" ] || [ -z "$NIC_SPEED" ]; then


echo "NIC Speed:"
echo "Virtual NIC (hidden by provider)"



else


echo "NIC Speed:"
echo "$NIC_SPEED"



fi



fi






SERVER_IP=$(curl -4 -s https://api.ipify.org)



if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then


SERVER_IP=$(hostname -I | awk '{print $1}')

fi



echo ""

echo "Public IP:"
echo "$SERVER_IP"




echo ""

echo "Running Speedtest..."

echo "Please wait..."



speedtest \
--accept-license \
--accept-gdpr \
> /root/speedtest_result.txt 2>&1 || true



cat /root/speedtest_result.txt



echo ""

# ==========================
# SSH PORT CHANGE SAFE MODE
# ==========================


echo ""

echo "Changing SSH Port..."



SSHD_CONFIG="/etc/ssh/sshd_config"


cp $SSHD_CONFIG \
${SSHD_CONFIG}.backup



# Remove old Port lines

sed -i '/^Port /d' $SSHD_CONFIG


# Add new port

echo "Port $SSH_PORT" >> $SSHD_CONFIG




# Test SSH configuration

if sshd -t; then


echo "SSH configuration OK"



else


echo "SSH configuration failed"

echo "Restoring backup..."

cp ${SSHD_CONFIG}.backup $SSHD_CONFIG


exit 1


fi






# ==========================
# FIREWALL CONFIGURATION
# ==========================


echo ""

echo "Configuring Firewall..."



# UFW (Ubuntu/Debian)


if command -v ufw >/dev/null 2>&1; then


ufw allow $SSH_PORT/tcp


ufw allow $PROXY_PORT/tcp


ufw --force enable



fi





# FIREWALLD (RHEL family)


if command -v firewall-cmd >/dev/null 2>&1; then



systemctl enable firewalld

systemctl start firewalld



firewall-cmd \
--permanent \
--add-port=$SSH_PORT/tcp



firewall-cmd \
--permanent \
--add-port=$PROXY_PORT/tcp



firewall-cmd --reload



fi





# Restart SSH


systemctl restart sshd 2>/dev/null || \
systemctl restart ssh 2>/dev/null || true







# ==========================
# SQUID CONFIGURATION
# ==========================


echo ""

echo "Configuring Squid Proxy..."



SQUID_AUTH=$(find /usr -name basic_ncsa_auth 2>/dev/null | head -1)



if [ -z "$SQUID_AUTH" ]; then


echo "Squid authentication helper not found"


exit 1


fi





echo "Auth helper:"

echo "$SQUID_AUTH"






# Backup squid config


if [ -f /etc/squid/squid.conf ]; then


cp /etc/squid/squid.conf \
/etc/squid/squid.conf.backup


fi





# Create password directory


mkdir -p /etc/squid/passwd





# Create proxy user


htpasswd -bc \
/etc/squid/passwd/squid_passwd \
"$PROXY_USER" \
"$PROXY_PASS"








# Write Squid Config


cat > /etc/squid/squid.conf <<EOF


# ==================================
# Squid Proxy v3.1
# ==================================


http_port $PROXY_PORT



auth_param basic program $SQUID_AUTH /etc/squid/passwd/squid_passwd


auth_param basic children 10


auth_param basic realm Squid Proxy


auth_param basic credentialsttl 4 hours



acl authenticated proxy_auth REQUIRED



http_access allow authenticated


http_access deny all




# Hide client information


forwarded_for delete


request_header_access X-Forwarded-For deny all


request_header_access Via deny all


via off



EOF






# ==========================
# Squid Config Test
# ==========================


echo ""

echo "Testing Squid configuration..."



squid -k parse





if [ $? -ne 0 ]; then


echo "Squid configuration error"


exit 1


fi





echo ""

echo "PART 2 COMPLETE"

# ==========================
# START SQUID SERVICE
# ==========================


echo ""

echo "Starting Squid..."



systemctl enable squid


systemctl restart squid






# ==========================
# CHECK SQUID STATUS
# ==========================


echo ""

echo "Checking Squid status..."



if systemctl is-active --quiet squid; then


SQUID_STATUS="RUNNING"


else


SQUID_STATUS="FAILED"



fi






# ==========================
# TEST LOCAL PROXY
# ==========================


echo ""

echo "Testing local proxy..."



TEST_PROXY=$(curl \
-x http://$PROXY_USER:$PROXY_PASS@127.0.0.1:$PROXY_PORT \
-I https://www.google.com \
--connect-timeout 10 \
2>/dev/null | head -1 || true)



if [[ "$TEST_PROXY" == HTTP* ]]; then


PROXY_TEST="SUCCESS"


else


PROXY_TEST="FAILED"



fi






# ==========================
# GET PUBLIC IP AGAIN
# ==========================


SERVER_IP=$(curl -4 -s https://api.ipify.org)



if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then


SERVER_IP=$(hostname -I | awk '{print $1}')


fi







# ==========================
# SAVE PROXY INFORMATION
# ==========================



cat > /root/proxy_info.txt <<EOF


========================================
SQUID PROXY INFORMATION
========================================


PUBLIC IP:

$SERVER_IP



SSH PORT:

$SSH_PORT



PROXY:

$SERVER_IP:$PROXY_PORT



USERNAME:

$PROXY_USER



PASSWORD:

$PROXY_PASS



PROXY FORMAT:


$SERVER_IP:$PROXY_PORT:$PROXY_USER:$PROXY_PASS



SQUID STATUS:

$SQUID_STATUS



LOCAL TEST:

$PROXY_TEST



NETWORK RESULT:

$(cat /root/speedtest_result.txt 2>/dev/null)



========================================

EOF








# ==========================
# FINAL OUTPUT
# ==========================



clear


echo "======================================"

echo " INSTALL COMPLETE"

echo "======================================"



cat /root/proxy_info.txt



echo ""

echo "Saved information:"

echo "/root/proxy_info.txt"



echo ""

echo "======================================"

echo " DONE"

echo "======================================"
