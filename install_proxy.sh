#!/bin/bash

# ======================================================
# Universal Squid Proxy Installer v3.2 (fixed)
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
echo " Squid Proxy Installer v3.2"
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
    # shellcheck disable=SC1091
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
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
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

# Basic validation (avoids htpasswd aborting the script)
if [ -z "$PROXY_USER" ]; then
    echo "Username cannot be empty"
    exit 1
fi

if [ -z "$PROXY_PASS" ]; then
    echo "Password cannot be empty"
    exit 1
fi


# ==========================
# INSTALL PACKAGES
# ==========================
install_packages() {
    echo ""
    echo "Installing packages..."

    case $PKG in

    apt)
        export DEBIAN_FRONTEND=noninteractive
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
install_speedtest() {
    echo ""
    echo "Installing Ookla Speedtest..."

    if command -v speedtest >/dev/null 2>&1; then
        return
    fi

    # Never let a speedtest problem abort the whole install
    case $PKG in

    apt)
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash || true
        apt install -y speedtest || true
        ;;

    dnf|yum)
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash || true
        $PKG install -y speedtest || true
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

NIC=$(ip route | awk '/default/ {print $5; exit}')

echo "Interface:"
echo "${NIC:-unknown}"
echo ""

if command -v ethtool >/dev/null 2>&1 && [ -n "$NIC" ]; then
    NIC_SPEED=$(ethtool "$NIC" 2>/dev/null | awk '/Speed/ {print $2}')

    if [ "$NIC_SPEED" = "Unknown!" ] || [ -z "$NIC_SPEED" ]; then
        echo "NIC Speed:"
        echo "Virtual NIC (hidden by provider)"
    else
        echo "NIC Speed:"
        echo "$NIC_SPEED"
    fi
fi

SERVER_IP=$(curl -4 -s --max-time 10 https://api.ipify.org || true)

if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

echo ""
echo "Public IP:"
echo "$SERVER_IP"

echo ""
echo "Running Speedtest..."
echo "Please wait..."

if command -v speedtest >/dev/null 2>&1; then
    speedtest --accept-license --accept-gdpr > /root/speedtest_result.txt 2>&1 || true
    cat /root/speedtest_result.txt
else
    echo "Speedtest not available, skipping." > /root/speedtest_result.txt
    cat /root/speedtest_result.txt
fi

echo ""


# ==========================
# SSH PORT CHANGE SAFE MODE
# ==========================
echo ""
echo "Changing SSH Port..."

SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup"

# Remove old Port lines
sed -i '/^Port /d' "$SSHD_CONFIG"

# Add new port
echo "Port $SSH_PORT" >> "$SSHD_CONFIG"

# Test SSH configuration
if sshd -t; then
    echo "SSH configuration OK"
else
    echo "SSH configuration failed"
    echo "Restoring backup..."
    cp "${SSHD_CONFIG}.backup" "$SSHD_CONFIG"
    exit 1
fi


# ==========================
# FIREWALL CONFIGURATION
# ==========================
echo ""
echo "Configuring Firewall..."

# UFW (Ubuntu/Debian)
if command -v ufw >/dev/null 2>&1; then
    ufw allow "$SSH_PORT"/tcp   || true
    ufw allow "$PROXY_PORT"/tcp || true
    ufw --force enable          || true
fi

# FIREWALLD (RHEL family)
if command -v firewall-cmd >/dev/null 2>&1; then
    systemctl enable firewalld || true
    systemctl start firewalld  || true

    firewall-cmd --permanent --add-port="$SSH_PORT"/tcp   || true
    firewall-cmd --permanent --add-port="$PROXY_PORT"/tcp || true
    firewall-cmd --reload || true
fi

# Restart SSH
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true


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
    cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
fi

# Create password directory
mkdir -p /etc/squid/passwd

# Create proxy user
htpasswd -bc /etc/squid/passwd/squid_passwd "$PROXY_USER" "$PROXY_PASS"

# Make the password file readable by the squid service user
if id proxy >/dev/null 2>&1; then
    chown proxy /etc/squid/passwd/squid_passwd
    chmod 640 /etc/squid/passwd/squid_passwd
elif id squid >/dev/null 2>&1; then
    chown squid /etc/squid/passwd/squid_passwd
    chmod 640 /etc/squid/passwd/squid_passwd
else
    chmod 644 /etc/squid/passwd/squid_passwd
fi

# Write Squid Config
cat > /etc/squid/squid.conf <<EOF
# ==================================
# Squid Proxy v3.2
# ==================================

http_port $PROXY_PORT

# --- Standard safe ports ---
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# --- Authentication ---
auth_param basic program $SQUID_AUTH /etc/squid/passwd/squid_passwd
auth_param basic children 10
auth_param basic realm Squid Proxy
auth_param basic credentialsttl 4 hours

acl authenticated proxy_auth REQUIRED

http_access allow authenticated
http_access deny all

# --- Privacy / anonymity ---
forwarded_for delete
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
via off

visible_hostname squid.proxy
coredump_dir /var/spool/squid
EOF


# ==========================
# Squid Config Test
# ==========================
echo ""
echo "Testing Squid configuration..."

if ! squid -k parse; then
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

# Initialise cache/swap dirs if needed (ignore if already present)
squid -z 2>/dev/null || true

systemctl enable squid || true
systemctl restart squid || true


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
    -x "http://$PROXY_USER:$PROXY_PASS@127.0.0.1:$PROXY_PORT" \
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
SERVER_IP=$(curl -4 -s --max-time 10 https://api.ipify.org || true)

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
