#!/usr/bin/env bash
set -Eeuo pipefail
exec "$(dirname -- "$(readlink -f -- "$0")")/vps-tools.sh" logins
