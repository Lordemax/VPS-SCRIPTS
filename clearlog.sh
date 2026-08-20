#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then echo 'Run as root.' >&2; exit 1; fi
journalctl --rotate
journalctl --vacuum-time=7d
find /var/log -type f -name '*.log' -size +50M -exec truncate -s 0 {} +
echo 'Logs older than 7 days removed; oversized text logs truncated.'
