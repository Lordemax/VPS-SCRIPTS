#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

cat <<'EOF'
VPS installer

1) Debian 12 or newer
2) Ubuntu 22.04
q) Quit
EOF

read -r -p "Choose the operating system [1-2]: " CHOICE
case "$CHOICE" in
  1) exec "$SCRIPT_DIR/debian12.sh" debian ;;
  2) exec "$SCRIPT_DIR/debian12.sh" ubuntu ;;
  q|Q) exit 0 ;;
  *) echo "Invalid choice." >&2; exit 1 ;;
esac