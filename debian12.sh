#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the operating system." >&2
  exit 1
fi
. /etc/os-release
TARGET_OS=${1:-auto}
case "$TARGET_OS" in
  debian)
    [[ ${ID:-} == debian && ${VERSION_ID%%.*} -ge 12 ]] || {
      echo "Debian 12 or newer was selected, but this is ${PRETTY_NAME}." >&2
      exit 1
    }
    ;;
  ubuntu)
    [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 22.04 ]] || {
      echo "Ubuntu 22.04 was selected, but this is ${PRETTY_NAME}." >&2
      exit 1
    }
    ;;
  auto)
    if [[ ${ID:-} == debian && ${VERSION_ID%%.*} -ge 12 ]]; then
      TARGET_OS=debian
    elif [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 22.04 ]]; then
      TARGET_OS=ubuntu
    else
      echo "This installer supports Debian 12+ or Ubuntu 22.04." >&2
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [debian|ubuntu]" >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get full-upgrade -y
apt-get install -y \
  curl wget ca-certificates nginx php-fpm php-cli \
  openvpn easy-rsa iptables iptables-persistent dropbear squid \
  vnstat fail2ban screen htop iftop bmon mtr-tiny nmap dnsutils \
  traceroute bc less psmisc procps iproute2 rsyslog unzip build-essential

ln -sfn /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

timedatectl set-timezone Asia/Jakarta 2>/dev/null || true

sysctl -w net.ipv4.ip_forward=1
cat >/etc/sysctl.d/99-vps-installer.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.disable_ipv6=1
EOF
sysctl --system >/dev/null

mkdir -p /home/vps/public_html
cat >/home/vps/public_html/index.html <<'EOF'
<pre>VPS installer is ready.</pre>
EOF
PHP_FPM_SERVICE=$(systemctl list-unit-files 'php*-fpm.service' --no-legend | awk 'NR == 1 { print $1 }')
if [[ -z $PHP_FPM_SERVICE ]]; then
  echo "PHP-FPM service was not found." >&2
  exit 1
fi
systemctl enable --now "$PHP_FPM_SERVICE"
PHP_SOCKET=$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' -print -quit)
if [[ -z $PHP_SOCKET ]]; then
  echo "PHP-FPM socket was not found." >&2
  exit 1
fi

cat >/etc/nginx/conf.d/vps.conf <<EOF
server {
    listen 80 default_server;
    server_name _;
    root /home/vps/public_html;
    index index.html index.php;

    location / { try_files $uri $uri/ =404; }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCKET;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx "$PHP_FPM_SERVICE" vnstat fail2ban

cat >/etc/dropbear/config <<'EOF'
-D
-p 109
-p 110
-p 443
EOF
systemctl enable --now dropbear

cat >/etc/squid/conf.d/vps.conf <<'EOF'
http_port 8080
acl localhost src 127.0.0.1/32 ::1
http_access allow localhost
http_access deny all
EOF
systemctl enable --now squid

cat >/etc/openvpn/server/server.conf <<'EOF'
port 1194
proto tcp-server
dev tun
user nobody
group nogroup
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
keepalive 10 60
persist-key
persist-tun
ca /etc/openvpn/server/pki/pki/ca.crt
cert /etc/openvpn/server/pki/pki/issued/server.crt
key /etc/openvpn/server/pki/pki/private/server.key
dh /etc/openvpn/server/pki/pki/dh.pem
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
auth SHA256
status /var/log/openvpn/status.log
verb 3
EOF

PKI_DIR=/etc/openvpn/server/pki
mkdir -p /etc/openvpn/server
if [[ ! -f $PKI_DIR/pki/ca.crt ]]; then
  rm -rf "$PKI_DIR"
  make-cadir "$PKI_DIR"
  cd "$PKI_DIR"
  ./easyrsa init-pki
  EASYRSA_BATCH=1 EASYRSA_REQ_CN=VPS-CA ./easyrsa build-ca nopass
  EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
  EASYRSA_BATCH=1 ./easyrsa sign-req server server
  EASYRSA_BATCH=1 ./easyrsa gen-dh
fi
systemctl enable --now openvpn-server@server

iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$(ip -o route show to default | awk '{print $5; exit}')" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$(ip -o route show to default | awk '{print $5; exit}')" -j MASQUERADE
netfilter-persistent save

MYIP=$(curl -4fsS https://api.ipify.org || hostname -I | awk '{print $1}')
cat > /root/vps-install-info.txt <<EOF
VPS services installed on ${PRETTY_NAME}.
OpenVPN: tcp://$MYIP:1194
OpenSSH: 22
Dropbear: 109, 110, 443
Squid: 8080 (localhost access only)
EOF

echo "Installation complete. Details: /root/vps-install-info.txt"
