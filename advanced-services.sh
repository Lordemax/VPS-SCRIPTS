#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
STATE_DIR=/etc/vps-scripts
XRAY_CONFIG=/usr/local/etc/xray/config.json

require_debian() {
  . /etc/os-release
  if [[ ${ID:-} != debian && ${ID:-} != ubuntu ]]; then
    echo "This module supports Debian and Ubuntu only." >&2
    exit 1
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y nginx stunnel4 websockify certbot unzip curl openssl ca-certificates qrencode
}

install_xray() {
  require_debian
  install_packages
  if [[ ! -x /usr/local/bin/xray ]]; then
    curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- install
  fi
  mkdir -p /usr/local/etc/xray "$STATE_DIR"
  local uuid password
  uuid=$(cat /proc/sys/kernel/random/uuid)
  password=$(openssl rand -hex 16)
  if [[ -f "$STATE_DIR/xray-credentials" ]]; then
    . "$STATE_DIR/xray-credentials"
  else
    cat >"$STATE_DIR/xray-credentials" <<EOF
XRAY_UUID=$uuid
TROJAN_PASSWORD=$password
EOF
    chmod 600 "$STATE_DIR/xray-credentials"
  fi
  . "$STATE_DIR/xray-credentials"
  cat >"$XRAY_CONFIG" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"listen":"127.0.0.1","port":10080,"protocol":"vmess","settings":{"clients":[{"id":"$XRAY_UUID"}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/vmess"}}},
    {"listen":"127.0.0.1","port":10081,"protocol":"vless","settings":{"clients":[{"id":"$XRAY_UUID"}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/vless"}}},
    {"listen":"127.0.0.1","port":10082,"protocol":"trojan","settings":{"clients":[{"password":"$TROJAN_PASSWORD"}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/trojan"}}}
  ],
  "outbounds": [{"protocol":"freedom"}]
}
EOF
  chmod 600 "$XRAY_CONFIG"
  systemctl enable --now xray
  echo "Xray installed: VMess /vmess, VLESS /vless, Trojan /trojan"
  echo "Credentials saved in $STATE_DIR/xray-credentials"
}

install_websocket() {
  require_debian
  install_packages
  if systemctl is-active --quiet nginx; then
    echo "Nginx already owns HTTP traffic. WebSocket SSH will use port 8022." >&2
  fi
  cat >/etc/systemd/system/ssh-websocket.service <<'EOF'
[Unit]
Description=SSH WebSocket bridge
After=network-online.target ssh.service

[Service]
ExecStart=/usr/bin/websockify 8022 127.0.0.1:22
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now ssh-websocket.service
  echo "SSH WebSocket listening on port 8022. Use Nginx or a TLS proxy for 443."
}

install_socks() {
  require_debian
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y dante-server
  cat >/etc/danted.conf <<'EOF'
logoutput: syslog
internal: 0.0.0.0 port = 1080
external: eth0
method: username none
user.privileged: proxy
user.notprivileged: nobody
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 }
proxy pass { from: 0.0.0.0/0 to: 0.0.0.0/0 command: connect }
EOF
  sed -i "s/^external: eth0/external: $(ip -o route show to default | awk '{print \$5; exit}')/" /etc/danted.conf
  systemctl enable --now danted
  echo 'SOCKS5 listening on port 1080. Restrict access with your firewall before exposing it publicly.'
}

install_stunnel() {
  require_debian
  install_packages
  mkdir -p /etc/stunnel
  if [[ ! -f /etc/stunnel/stunnel.pem ]]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
      -subj "/CN=$(hostname -f 2>/dev/null || hostname)" \
      -keyout /etc/stunnel/stunnel.key -out /etc/stunnel/stunnel.crt >/dev/null 2>&1
    cat /etc/stunnel/stunnel.key /etc/stunnel/stunnel.crt >/etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
  fi
  cat >/etc/stunnel/stunnel.conf <<'EOF'
fips = no
setuid = stunnel4
setgid = stunnel4
pid = /run/stunnel4/stunnel.pid
cert = /etc/stunnel/stunnel.pem

[ssh-tls]
accept = 8443
connect = 127.0.0.1:22
EOF
  sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
  systemctl enable --now stunnel4
  echo "Stunnel SSH TLS listening on port 8443."
}

cloudflare_dns() {
  require_debian
  local token zone record ip
  read -r -s -p 'Cloudflare API token: ' token; printf '\n'
  read -r -p 'Zone name (example.com): ' zone
  read -r -p "DNS record name (default: $zone): " record
  record=${record:-$zone}
  ip=$(curl -4fsS https://api.ipify.org)
  local zone_id
  zone_id=$(curl -fsS -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    "https://api.cloudflare.com/client/v4/zones?name=$zone&status=active" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
  [[ -n $zone_id ]] || { echo 'Unable to find the Cloudflare zone.' >&2; exit 1; }
  local record_id
  record_id=$(curl -fsS -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$record" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
  local payload
  payload=$(printf '{"type":"A","name":"%s","content":"%s","ttl":300,"proxied":true}' "$record" "$ip")
  if [[ -n $record_id ]]; then
    curl -fsS -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" --data "$payload" >/dev/null
  else
    curl -fsS -X POST -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" --data "$payload" >/dev/null
  fi
  echo "Cloudflare record $record -> $ip configured."
}

backup() { exec "$SCRIPT_DIR/vps-tools.sh" backup; }
restore() {
  local archive=${2:-}
  [[ -f $archive ]] || { echo "Usage: $0 restore BACKUP.tar.gz" >&2; exit 1; }
  [[ $archive == /root/vps-backups/* ]] || { echo 'Restore only accepts archives from /root/vps-backups.' >&2; exit 1; }
  tar -tzf "$archive" >/dev/null
  tar -xzf "$archive" -C / --no-same-owner
  systemctl daemon-reload
  echo "Configuration restored from $archive. Review and restart services manually."
}

menu() {
  local choice
  while true; do
    cat <<'EOF'

Advanced VPS services
1) Install Xray VMess/VLESS/Trojan WebSocket
2) Install SSH WebSocket bridge
3) Install Stunnel SSH TLS
4) Install SOCKS5 proxy
5) Update a Cloudflare DNS A record
6) Create local backup
7) Restore a local backup
q) Quit
EOF
    read -r -p 'Choose an option: ' choice
    case "$choice" in
      1) install_xray ;;
      2) install_websocket ;;
      3) install_stunnel ;;
      4) install_socks ;;
      5) cloudflare_dns ;;
      6) backup ;;
      7) read -r -p 'Backup archive: ' archive; restore restore "$archive" ;;
      q|Q) return 0 ;;
      *) echo 'Invalid choice.' >&2 ;;
    esac
  done
}

case "${1:-menu}" in
  menu) menu ;;
  xray) install_xray ;;
  websocket) install_websocket ;;
  stunnel) install_stunnel ;;
  socks) install_socks ;;
  cloudflare) cloudflare_dns ;;
  backup) backup ;;
  restore) restore "$@" ;;
  *) echo "Usage: $0 {menu|xray|websocket|stunnel|socks|cloudflare|backup|restore}" >&2; exit 1 ;;
esac
