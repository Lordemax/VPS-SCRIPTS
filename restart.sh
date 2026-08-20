#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then echo 'Run as root.' >&2; exit 1; fi
services=(ssh nginx 'openvpn-server@server' dropbear squid vnstat fail2ban)
for service in "${services[@]}"; do
  if systemctl is-enabled --quiet "$service" 2>/dev/null || systemctl is-active --quiet "$service" 2>/dev/null; then
    systemctl restart "$service" && echo "Restarted: $service" || echo "Failed: $service" >&2
  fi
done
