#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
case "${1:-status}" in
  on|enable) exec "$SCRIPT_DIR/vps-tools.sh" reboot-on ;;
  off|disable) exec "$SCRIPT_DIR/vps-tools.sh" reboot-off ;;
  status) systemctl is-enabled --quiet vps-autoreboot.timer && echo 'Automatic reboot: enabled' || echo 'Automatic reboot: disabled' ;;
  *) echo "Usage: $0 {on|off|status}" >&2; exit 1 ;;
esac
