#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this command as root." >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage:
  vps-tools.sh menu
  vps-tools.sh info
  vps-tools.sh services
  vps-tools.sh ram
  vps-tools.sh bandwidth
  vps-tools.sh backup

Commands are read-only except backup, which creates a local archive in
/root/vps-backups.
EOF
}

human() {
  numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s B' "$1"
}

show_ports() {
  echo 'Listening sockets:'
  ss -lntup 2>/dev/null || echo 'ss is unavailable.'
  cat <<'EOF'

Expected service ports when configured:
OpenSSH 22 | SSH WebSocket 80 | SSH TLS WebSocket 443
Stunnel 447,777 | Dropbear 109,143 | BadVPN 7100-7300
Nginx 81 | OpenVPN 1194 | Squid 8080
Xray VMess/VLESS/Trojan and Sodosok require separate service installation.
EOF
}

set_ipv6() {
  local value=$1
  [[ $value == 0 || $value == 1 ]] || { echo 'Use ipv6-on or ipv6-off.' >&2; exit 1; }
  printf 'net.ipv6.conf.all.disable_ipv6=%s\n' "$((1 - value))" >/etc/sysctl.d/99-vps-ipv6.conf
  sysctl -w "net.ipv6.conf.all.disable_ipv6=$((1 - value))" >/dev/null
  sysctl -w "net.ipv6.conf.default.disable_ipv6=$((1 - value))" >/dev/null
  echo "IPv6 $([[ $value == 1 ]] && echo enabled || echo disabled)."
}

install_reboot_schedule() {
  cat >/etc/systemd/system/vps-autoreboot.service <<'EOF'
[Unit]
Description=Scheduled VPS reboot

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
EOF
  cat >/etc/systemd/system/vps-autoreboot.timer <<'EOF'
[Unit]
Description=Reboot VPS daily at 05:00

[Timer]
OnCalendar=*-*-* 05:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now vps-autoreboot.timer
  echo 'Automatic reboot enabled for 05:00 server time.'
}

disable_reboot_schedule() {
  systemctl disable --now vps-autoreboot.timer 2>/dev/null || true
  echo 'Automatic reboot disabled.'
}

install_backup_schedule() {
  local script_path
  script_path=$(readlink -f "$0")
  cat >/etc/systemd/system/vps-backup.service <<EOF
[Unit]
Description=VPS configuration backup

[Service]
Type=oneshot
ExecStart=$script_path backup
EOF
  cat >/etc/systemd/system/vps-backup.timer <<'EOF'
[Unit]
Description=Daily VPS configuration backup

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now vps-backup.timer
  echo 'Automatic backup enabled for 04:00 server time.'
}

disable_backup_schedule() {
  systemctl disable --now vps-backup.timer 2>/dev/null || true
  echo 'Automatic backup disabled.'
}

show_logins() {
  who || true
  echo
  echo 'SSH processes:'
  pgrep -a -f 'sshd:.*@' || echo 'No active SSH sessions found.'
}

cleanup_expired_users() {
  local username _ _ _ _ _ _ expire _ uid today
  today=$(( $(date +%s) / 86400 ))
  while IFS=: read -r username _ _ _ _ _ _ expire _; do
    uid=$(id -u "$username" 2>/dev/null || echo 0)
    (( uid >= 1000 )) || continue
    [[ $expire =~ ^[0-9]+$ && $expire -lt $today ]] || continue
    usermod --lock "$username"
    echo "Locked expired user: $username"
  done < /etc/shadow
}

show_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    ufw status verbose || true
  else
    iptables -S 2>/dev/null || echo 'iptables is unavailable.'
  fi
}

show_info() {
  . /etc/os-release
  printf 'OS:       %s\n' "${PRETTY_NAME:-unknown}"
  printf 'Kernel:   %s\n' "$(uname -r)"
  printf 'Hostname: %s\n' "$(hostname)"
  printf 'Uptime:   %s\n' "$(uptime -p 2>/dev/null || uptime)"
  printf 'Load:     %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
  printf 'IPv4:     %s\n' "$(hostname -I 2>/dev/null | awk '{print $1}')"
}

show_services() {
  local service state
  printf '%-24s %s\n' SERVICE STATE
  for service in ssh nginx openvpn-server@server dropbear squid vnstat fail2ban; do
    state=$(systemctl is-active "$service" 2>/dev/null || true)
    printf '%-24s %s\n' "$service" "${state:-unknown}"
  done
}

show_ram() {
  awk '
    /^MemTotal:/ { total=$2 }
    /^MemAvailable:/ { available=$2 }
    END {
      used=total-available
      printf "Total:     %d kB\nUsed:      %d kB\nAvailable: %d kB\nUsage:     %.1f%%\n", total, used, available, used/total*100
    }
  ' /proc/meminfo
}

show_bandwidth() {
  local received=0 transmitted=0 interface values
  while IFS=: read -r interface values; do
    [[ $interface == lo ]] && continue
    read -r rx _ _ _ _ _ _ _ tx _ <<<"$values"
    [[ $rx =~ ^[0-9]+$ ]] && received=$((received + rx))
    [[ $tx =~ ^[0-9]+$ ]] && transmitted=$((transmitted + tx))
  done < /proc/net/dev
  printf 'Received:   %s\n' "$(human "$received")"
  printf 'Transmitted: %s\n' "$(human "$transmitted")"
  printf 'Total:       %s\n' "$(human "$((received + transmitted))")"
}

make_backup() {
  local backup_dir archive
  backup_dir=/root/vps-backups
  archive="$backup_dir/vps-$(date +%Y%m%d-%H%M%S).tar.gz"
  mkdir -p "$backup_dir"
  tar -czf "$archive" \
    --ignore-failed-read \
    /etc/openvpn/server \
    /etc/nginx/conf.d \
    /etc/squid \
    /etc/dropbear \
    /etc/systemd/system \
    /etc/cron.d \
    /home/vps/public_html 2>/dev/null || true
  chmod 600 "$archive"
  echo "Backup created: $archive"
}

menu() {
  local choice
  while true; do
    cat <<'EOF'

VPS tools
1) System information
2) Service status
3) RAM usage
4) Network totals
5) Create local backup
6) Listening ports
7) Active logins
8) Firewall status
9) Cleanup expired users
10) Enable daily reboot (05:00)
11) Disable daily reboot
12) Enable daily backup (04:00)
13) Disable daily backup
14) Enable IPv6
15) Disable IPv6
16) Advanced services
q) Quit
EOF
    read -r -p 'Choose an option: ' choice
    case "$choice" in
      1) show_info ;;
      2) show_services ;;
      3) show_ram ;;
      4) show_bandwidth ;;
      5) make_backup ;;
      6) show_ports ;;
      7) show_logins ;;
      8) show_firewall ;;
      9) cleanup_expired_users ;;
      10) install_reboot_schedule ;;
      11) disable_reboot_schedule ;;
      12) install_backup_schedule ;;
      13) disable_backup_schedule ;;
      14) set_ipv6 1 ;;
      15) set_ipv6 0 ;;
      16) exec "$(dirname -- "$(readlink -f -- "$0")")/advanced-services.sh" menu ;;
      q|Q) return 0 ;;
      *) echo 'Invalid choice.' >&2 ;;
    esac
  done
}

case "${1:-menu}" in
  menu) menu ;;
  info) show_info ;;
  services) show_services ;;
  ram) show_ram ;;
  bandwidth|traffic) show_bandwidth ;;
  backup) make_backup ;;
  ports) show_ports ;;
  logins) show_logins ;;
  firewall) show_firewall ;;
  cleanup-expired) cleanup_expired_users ;;
  reboot-on) install_reboot_schedule ;;
  reboot-off) disable_reboot_schedule ;;
  backup-on) install_backup_schedule ;;
  backup-off) disable_backup_schedule ;;
  ipv6-on) set_ipv6 1 ;;
  ipv6-off) set_ipv6 0 ;;
  *) usage; exit 1 ;;
esac
