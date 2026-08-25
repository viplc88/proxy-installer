#!/bin/bash

# ======================================================
# Universal Proxy Installer v4.0
#
# Features:
# - Auto Linux Detection
# - Disable SELinux
# - SSH Port Change Safe Mode
# - Squid Proxy + Auth
# - Ookla Speedtest
# - Fail2ban (SSH + Squid protection)
# - Network Information
# - Interactive Service Menu
#
# Support:
# Ubuntu Debian Alma Rocky CentOS RHEL Fedora Amazon
# ======================================================

set -e

clear

echo "======================================"
echo " Universal Proxy Installer v4.0"
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
# SERVICE SELECTION MENU
# ==========================
echo ""
echo "======================================"
echo " Chon service muon cai dat:"
echo "======================================"
echo ""
echo "  [1] Squid Proxy (bao gom SSH port + Firewall)"
echo "  [2] Ookla Speedtest"
echo "  [3] Fail2ban (bao ve SSH + Squid)"
echo "  [4] Tar, Gzip, Zip, Nano (tien ich co ban)"
echo "  [5] Xem va restart Tuong lua (Firewall)"
echo "  [6] Tat ca"
echo ""

read -p "Nhap so thu tu (vi du: 1 3 4 hoac 6 de cai tat ca): " SERVICE_CHOICE
echo ""

INSTALL_SQUID=false
INSTALL_SPEEDTEST=false
INSTALL_FAIL2BAN=false
INSTALL_UTILS=false
INSTALL_FIREWALL_CHECK=false

if echo "$SERVICE_CHOICE" | grep -qw "6"; then
    INSTALL_SQUID=true
    INSTALL_SPEEDTEST=true
    INSTALL_FAIL2BAN=true
    INSTALL_UTILS=true
    INSTALL_FIREWALL_CHECK=true
else
    echo "$SERVICE_CHOICE" | grep -qw "1" && INSTALL_SQUID=true          || true
    echo "$SERVICE_CHOICE" | grep -qw "2" && INSTALL_SPEEDTEST=true       || true
    echo "$SERVICE_CHOICE" | grep -qw "3" && INSTALL_FAIL2BAN=true        || true
    echo "$SERVICE_CHOICE" | grep -qw "4" && INSTALL_UTILS=true           || true
    echo "$SERVICE_CHOICE" | grep -qw "5" && INSTALL_FIREWALL_CHECK=true  || true
fi

if [ "$INSTALL_SQUID" = false ] && [ "$INSTALL_SPEEDTEST" = false ] && \
   [ "$INSTALL_FAIL2BAN" = false ] && [ "$INSTALL_UTILS" = false ] && \
   [ "$INSTALL_FIREWALL_CHECK" = false ]; then
    echo "Khong co service nao duoc chon. Thoat."
    exit 0
fi

echo "Service se duoc cai dat:"
[ "$INSTALL_SQUID"          = true ] && echo "  - Squid Proxy"
[ "$INSTALL_SPEEDTEST"      = true ] && echo "  - Ookla Speedtest"
[ "$INSTALL_FAIL2BAN"       = true ] && echo "  - Fail2ban"
[ "$INSTALL_UTILS"          = true ] && echo "  - Tar / Gzip / Zip / Nano"
[ "$INSTALL_FIREWALL_CHECK" = true ] && echo "  - Kiem tra & Restart Tuong lua"
echo ""


# ==========================
# USER INPUT (Squid)
# ==========================
SSH_PORT=22
PROXY_PORT=3128
PROXY_USER=""
PROXY_PASS=""

if [ "$INSTALL_SQUID" = true ]; then
    read -p "SSH Port [2222]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-2222}

    read -p "Proxy Port [3128]: " PROXY_PORT
    PROXY_PORT=${PROXY_PORT:-3128}

    read -p "Proxy Username: " PROXY_USER

    read -s -p "Proxy Password: " PROXY_PASS
    echo ""

    if [ -z "$PROXY_USER" ]; then
        echo "Username cannot be empty"
        exit 1
    fi

    if [ -z "$PROXY_PASS" ]; then
        echo "Password cannot be empty"
        exit 1
    fi
fi


# ==========================
# INSTALL BASE PACKAGES
# ==========================
install_base_packages() {
    echo ""
    echo "Installing base packages..."

    case $PKG in
    apt)
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt install -y curl wget ca-certificates gnupg ethtool
        ;;
    dnf)
        dnf install -y curl wget ca-certificates ethtool
        ;;
    yum)
        yum install -y curl wget ca-certificates ethtool
        ;;
    esac
}

install_base_packages


# ==========================
# INSTALL SQUID PROXY
# ==========================
do_install_squid() {
    echo ""
    echo "======================================"
    echo " [1] Installing Squid Proxy..."
    echo "======================================"

    case $PKG in
    apt)
        export DEBIAN_FRONTEND=noninteractive
        apt install -y squid apache2-utils ufw
        ;;
    dnf)
        dnf install -y squid httpd-tools firewalld
        ;;
    yum)
        yum install -y squid httpd-tools firewalld
        ;;
    esac

    # --- SSH Port Change ---
    echo ""
    echo "Changing SSH Port to $SSH_PORT..."

    SSHD_CONFIG="/etc/ssh/sshd_config"
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup"
    sed -i '/^Port /d' "$SSHD_CONFIG"
    echo "Port $SSH_PORT" >> "$SSHD_CONFIG"

    if sshd -t; then
        echo "SSH configuration OK"
    else
        echo "SSH configuration failed, restoring backup..."
        cp "${SSHD_CONFIG}.backup" "$SSHD_CONFIG"
        exit 1
    fi

    # --- Firewall ---
    echo ""
    echo "Configuring Firewall..."

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$SSH_PORT"/tcp   || true
        ufw allow "$PROXY_PORT"/tcp || true
        ufw --force enable          || true
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        systemctl enable firewalld || true
        systemctl start firewalld  || true
        firewall-cmd --permanent --add-port="$SSH_PORT"/tcp   || true
        firewall-cmd --permanent --add-port="$PROXY_PORT"/tcp || true
        firewall-cmd --reload || true
    fi

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

    # --- Squid Config ---
    echo ""
    echo "Configuring Squid Proxy..."

    SQUID_AUTH=$(find /usr -name basic_ncsa_auth 2>/dev/null | head -1)

    if [ -z "$SQUID_AUTH" ]; then
        echo "Squid authentication helper not found"
        exit 1
    fi

    echo "Auth helper: $SQUID_AUTH"

    [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf /etc/squid/squid.conf.backup

    mkdir -p /etc/squid/passwd
    htpasswd -bc /etc/squid/passwd/squid_passwd "$PROXY_USER" "$PROXY_PASS"

    if id proxy >/dev/null 2>&1; then
        chown proxy /etc/squid/passwd/squid_passwd
        chmod 640   /etc/squid/passwd/squid_passwd
    elif id squid >/dev/null 2>&1; then
        chown squid /etc/squid/passwd/squid_passwd
        chmod 640   /etc/squid/passwd/squid_passwd
    else
        chmod 644 /etc/squid/passwd/squid_passwd
    fi

    cat > /etc/squid/squid.conf <<EOF
# ==================================
# Squid Proxy v4.0
# ==================================

http_port $PROXY_PORT

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

auth_param basic program $SQUID_AUTH /etc/squid/passwd/squid_passwd
auth_param basic children 10
auth_param basic realm Squid Proxy
auth_param basic credentialsttl 4 hours

acl authenticated proxy_auth REQUIRED

http_access allow authenticated
http_access deny all

forwarded_for delete
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
via off

visible_hostname squid.proxy
coredump_dir /var/spool/squid
EOF

    echo ""
    echo "Testing Squid configuration..."
    if ! squid -k parse; then
        echo "Squid configuration error"
        exit 1
    fi

    squid -z 2>/dev/null || true
    systemctl enable squid || true
    systemctl restart squid || true

    echo ""
    echo "[1] Squid Proxy: DONE"
}


# ==========================
# INSTALL OOKLA SPEEDTEST
# ==========================
do_install_speedtest() {
    echo ""
    echo "======================================"
    echo " [2] Installing Ookla Speedtest..."
    echo "======================================"

    if command -v speedtest >/dev/null 2>&1; then
        echo "Speedtest already installed, skipping."
        return
    fi

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

    echo "[2] Ookla Speedtest: DONE"
}


# ==========================
# INSTALL FAIL2BAN
# ==========================
do_install_fail2ban() {
    echo ""
    echo "======================================"
    echo " [3] Installing Fail2ban..."
    echo "======================================"

    case $PKG in
    apt)
        export DEBIAN_FRONTEND=noninteractive
        apt install -y fail2ban
        ;;
    dnf)
        dnf install -y epel-release || true
        dnf install -y fail2ban
        ;;
    yum)
        yum install -y epel-release || true
        yum install -y fail2ban
        ;;
    esac

    # --- Fail2ban jail.local ---
    cat > /etc/fail2ban/jail.local <<'JAILEOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 5

[squid]
enabled  = false
port     = 3128
filter   = squid
logpath  = /var/log/squid/access.log
maxretry = 10
bantime  = 1800
JAILEOF

    # Override SSH port nếu đã chọn cài Squid (biết SSH_PORT)
    if [ "$INSTALL_SQUID" = true ] && [ "$SSH_PORT" != "22" ]; then
        sed -i "s/^port     = ssh/port     = $SSH_PORT/" /etc/fail2ban/jail.local
    fi

    # Override squid port nếu đã chọn cài Squid
    if [ "$INSTALL_SQUID" = true ]; then
        sed -i "s/^port     = 3128/port     = $PROXY_PORT/" /etc/fail2ban/jail.local
        sed -i "s/^enabled  = false/enabled  = true/" /etc/fail2ban/jail.local
    fi

    systemctl enable fail2ban || true
    systemctl restart fail2ban || true

    echo "[3] Fail2ban: DONE"
}


# ==========================
# INSTALL TAR / GZIP / ZIP / NANO
# ==========================
do_install_utils() {
    echo ""
    echo "======================================"
    echo " [4] Installing Tar, Gzip, Zip, Nano..."
    echo "======================================"

    case $PKG in
    apt)
        export DEBIAN_FRONTEND=noninteractive
        apt install -y tar gzip zip unzip nano
        ;;
    dnf)
        dnf install -y tar gzip zip unzip nano
        ;;
    yum)
        yum install -y tar gzip zip unzip nano
        ;;
    esac

    echo "[4] Tar / Gzip / Zip / Nano: DONE"
}


# ==========================
# FIREWALL STATUS & RESTART
# ==========================
do_firewall_check() {
    echo ""
    echo "======================================"
    echo " [5] Kiem tra & Restart Tuong lua..."
    echo "======================================"

    FIREWALL_REPORT=""

    # --- UFW ---
    if command -v ufw >/dev/null 2>&1; then
        echo ""
        echo "--- UFW ---"
        UFW_STATUS=$(ufw status verbose 2>/dev/null || echo "Khong the doc trang thai UFW")
        echo "$UFW_STATUS"
        FIREWALL_REPORT="$FIREWALL_REPORT
--- UFW ---
$UFW_STATUS"

        echo ""
        read -p "Restart UFW? (y/n) [n]: " RESTART_UFW
        RESTART_UFW=${RESTART_UFW:-n}
        if [[ "$RESTART_UFW" =~ ^[Yy]$ ]]; then
            ufw disable || true
            ufw --force enable || true
            echo "UFW da duoc restart."
            FIREWALL_REPORT="$FIREWALL_REPORT
UFW: Restarted"
        fi
    fi

    # --- FIREWALLD ---
    if command -v firewall-cmd >/dev/null 2>&1; then
        echo ""
        echo "--- FIREWALLD ---"
        if systemctl is-active --quiet firewalld; then
            FWD_STATUS=$(firewall-cmd --list-all 2>/dev/null || echo "Khong the doc trang thai firewalld")
            echo "$FWD_STATUS"
            FIREWALL_REPORT="$FIREWALL_REPORT

--- FIREWALLD ---
$FWD_STATUS"

            echo ""
            read -p "Restart firewalld? (y/n) [n]: " RESTART_FWD
            RESTART_FWD=${RESTART_FWD:-n}
            if [[ "$RESTART_FWD" =~ ^[Yy]$ ]]; then
                systemctl restart firewalld || true
                echo "firewalld da duoc restart."
                FIREWALL_REPORT="$FIREWALL_REPORT
firewalld: Restarted"
            fi
        else
            echo "firewalld khong chay."
            read -p "Khoi dong firewalld? (y/n) [n]: " START_FWD
            START_FWD=${START_FWD:-n}
            if [[ "$START_FWD" =~ ^[Yy]$ ]]; then
                systemctl enable firewalld || true
                systemctl start firewalld  || true
                echo "firewalld da duoc khoi dong."
                FIREWALL_REPORT="$FIREWALL_REPORT
firewalld: Started"
            fi
        fi
    fi

    if [ -z "$(command -v ufw 2>/dev/null)" ] && [ -z "$(command -v firewall-cmd 2>/dev/null)" ]; then
        echo "Khong phat hien ufw hoac firewalld tren he thong nay."
        FIREWALL_REPORT="Khong phat hien tuong lua."
    fi

    echo "[5] Kiem tra Tuong lua: DONE"
}


# ==========================
# RUN SELECTED SERVICES
# ==========================
[ "$INSTALL_SQUID"          = true ] && do_install_squid
[ "$INSTALL_SPEEDTEST"      = true ] && do_install_speedtest
[ "$INSTALL_FAIL2BAN"       = true ] && do_install_fail2ban
[ "$INSTALL_UTILS"          = true ] && do_install_utils
[ "$INSTALL_FIREWALL_CHECK" = true ] && do_firewall_check


# ==========================
# NETWORK INFORMATION
# ==========================
echo ""
echo "======================================"
echo " NETWORK TEST"
echo "======================================"

NIC=$(ip route | awk '/default/ {print $5; exit}')
echo "Interface: ${NIC:-unknown}"
echo ""

if command -v ethtool >/dev/null 2>&1 && [ -n "$NIC" ]; then
    NIC_SPEED=$(ethtool "$NIC" 2>/dev/null | awk '/Speed/ {print $2}')
    if [ "$NIC_SPEED" = "Unknown!" ] || [ -z "$NIC_SPEED" ]; then
        echo "NIC Speed: Virtual NIC (hidden by provider)"
    else
        echo "NIC Speed: $NIC_SPEED"
    fi
fi

SERVER_IP=$(curl -4 -s --max-time 10 https://api.ipify.org || true)
if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

echo "Public IP: $SERVER_IP"
echo ""

if [ "$INSTALL_SPEEDTEST" = true ]; then
    echo "Running Speedtest... please wait..."
    if command -v speedtest >/dev/null 2>&1; then
        speedtest --accept-license --accept-gdpr > /root/speedtest_result.txt 2>&1 || true
    else
        echo "Speedtest not available." > /root/speedtest_result.txt
    fi
    cat /root/speedtest_result.txt
fi


# ==========================
# STATUS SUMMARY
# ==========================
SQUID_STATUS="N/A"
PROXY_TEST="N/A"
FAIL2BAN_STATUS="N/A"
UTILS_STATUS="N/A"
[ "$INSTALL_UTILS" = true ] && UTILS_STATUS="INSTALLED"

if [ "$INSTALL_SQUID" = true ]; then
    if systemctl is-active --quiet squid; then
        SQUID_STATUS="RUNNING"
    else
        SQUID_STATUS="FAILED"
    fi

    echo ""
    echo "Testing local proxy..."
    TEST_PROXY=$(curl \
        -x "http://$PROXY_USER:$PROXY_PASS@127.0.0.1:$PROXY_PORT" \
        -I https://www.google.com \
        --connect-timeout 10 \
        2>/dev/null | head -1 || true)
    [[ "$TEST_PROXY" == HTTP* ]] && PROXY_TEST="SUCCESS" || PROXY_TEST="FAILED"
fi

if [ "$INSTALL_FAIL2BAN" = true ]; then
    if systemctl is-active --quiet fail2ban; then
        FAIL2BAN_STATUS="RUNNING"
    else
        FAIL2BAN_STATUS="FAILED"
    fi
fi


# ==========================
# SAVE INFORMATION
# ==========================
cat > /root/proxy_info.txt <<EOF

========================================
INSTALL SUMMARY
========================================

PUBLIC IP:    $SERVER_IP
SSH PORT:     $SSH_PORT

EOF

if [ "$INSTALL_SQUID" = true ]; then
cat >> /root/proxy_info.txt <<EOF
--- SQUID PROXY ---
PROXY:        $SERVER_IP:$PROXY_PORT
USERNAME:     $PROXY_USER
PASSWORD:     $PROXY_PASS
FORMAT:       $SERVER_IP:$PROXY_PORT:$PROXY_USER:$PROXY_PASS
STATUS:       $SQUID_STATUS
LOCAL TEST:   $PROXY_TEST

EOF
fi

if [ "$INSTALL_FAIL2BAN" = true ]; then
cat >> /root/proxy_info.txt <<EOF
--- FAIL2BAN ---
STATUS:       $FAIL2BAN_STATUS
CONFIG:       /etc/fail2ban/jail.local

EOF
fi

if [ "$INSTALL_UTILS" = true ]; then
cat >> /root/proxy_info.txt <<EOF
--- UTILITIES ---
Tar / Gzip / Zip / Unzip / Nano: $UTILS_STATUS

EOF
fi

if [ "$INSTALL_FIREWALL_CHECK" = true ]; then
cat >> /root/proxy_info.txt <<EOF
--- FIREWALL ---
${FIREWALL_REPORT:-N/A}

EOF
fi

if [ "$INSTALL_SPEEDTEST" = true ]; then
cat >> /root/proxy_info.txt <<EOF
--- SPEEDTEST ---
$(cat /root/speedtest_result.txt 2>/dev/null)

EOF
fi

echo "========================================" >> /root/proxy_info.txt


# ==========================
# FINAL OUTPUT
# ==========================
clear

echo "======================================"
echo " INSTALL COMPLETE"
echo "======================================"

cat /root/proxy_info.txt

echo ""
echo "Saved to: /root/proxy_info.txt"
echo ""
echo "======================================"
echo " DONE"
echo "======================================"
