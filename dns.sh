#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-show}" in
  show)
    if command -v resolvectl >/dev/null 2>&1; then
      resolvectl status
    else
      cat /etc/resolv.conf
    fi
    ;;
  *)
    echo "Usage: $0 show" >&2
    exit 1
    ;;
esac
