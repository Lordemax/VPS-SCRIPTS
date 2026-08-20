#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
VERSION=$(tr -d '[:space:]' <"$SCRIPT_DIR/VERSION")
printf 'VPS-SCRIPTS version %s\n' "$VERSION"
