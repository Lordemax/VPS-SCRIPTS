#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage: $0 USER [DAYS]" >&2; exit 1; }
exec "$SCRIPT_DIR/user-manager.sh" add "$@"
