#!/bin/bash

# ======================================================
# Squid Proxy Auto Installer
# Ubuntu / Debian / AlmaLinux / Rocky / CentOS
# SSH Port Change + Squid + User Password
# ======================================================

set -e

clear

echo "======================================"
echo " Squid Proxy Auto Installer"
echo "======================================"

# Check root

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi


# ==========================
# INPUT
# ==========================

read -p "New SSH port (default 2222): " SSH_PORT
SSH_PORT=${SSH_PORT:-2222}

read -p "Proxy port (default 3128): " SQUID_PORT
SQUID_PORT=${SQUID_PORT:-3128}

read -p "Proxy username: " PROXY_USER

read -s -p "Proxy password: " PROXY_PASS
echo ""


# ==========================
# Detect OS
# ==========================

if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo "Unknown OS"
    exit 1
fi


echo "Detected OS: $ID"


# ==========================
# Install package
# ==========================

install_packages(){

case $ID in

ubuntu|debian)

apt update

apt install -y squid apache2-utils ufw

;;

almalinux|rocky|centos|rhel)

dnf install -y squid httpd-tools firewalld

systemctl enable firewalld
systemctl start firewalld

;;

*)

echo "Unsupported OS"
exit 1

;;

esac

}


install_packages



# ==========================
# SSH PORT CHANGE
# ==========================

echo "Changing SSH port..."

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup


sed -i "s/^#Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config


# Firewall SSH

if command -v ufw >/dev/null; then

ufw allow $SSH_PORT/tcp
ufw --force enable

fi


if command -v firewall-cmd >/dev/null; then

firewall-cmd --permanent --add-port=$SSH_PORT/tcp
firewall-cmd --reload

fi



systemctl restart sshd || systemctl restart ssh



# ==========================
# SQUID CONFIG
# ==========================


echo "Configuring Squid..."


cp /etc/squid/squid.conf /etc/squid/squid.conf.backup


# create password file

mkdir -p /etc/squid/passwd


touch /etc/squid/passwd/squid_passwd


if command -v htpasswd >/dev/null; then

htpasswd -bc \
/etc/squid/passwd/squid_passwd \
"$PROXY_USER" \
"$PROXY_PASS"

fi



cat > /etc/squid/squid.conf <<EOF

http_port $SQUID_PORT


auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/passwd/squid_passwd

auth_param basic children 5

auth_param basic realm Squid Proxy

auth_param basic credentialsttl 2 hours


acl authenticated proxy_auth REQUIRED


http_access allow authenticated

http_access deny all


forwarded_for delete

via off

request_header_access X-Forwarded-For deny all


EOF



# Fix auth path Ubuntu

if [ -f /usr/lib/squid/basic_ncsa_auth ]; then

sed -i \
"s#/usr/lib64/squid/basic_ncsa_auth#/usr/lib/squid/basic_ncsa_auth#" \
/etc/squid/squid.conf

fi



# ==========================
# Firewall Proxy
# ==========================


if command -v ufw >/dev/null; then

ufw allow $SQUID_PORT/tcp

fi


if command -v firewall-cmd >/dev/null; then

firewall-cmd \
--permanent \
--add-port=$SQUID_PORT/tcp

firewall-cmd --reload

fi



# ==========================
# Start squid
# ==========================

systemctl enable squid

systemctl restart squid



# ==========================
# RESULT
# ==========================


SERVER_IP=$(curl -s ifconfig.me)


clear

echo "======================================"
echo " INSTALL COMPLETE"
echo "======================================"

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
echo "Example:"
echo "$SERVER_IP:$SQUID_PORT:$PROXY_USER:$PROXY_PASS"

echo "======================================"
