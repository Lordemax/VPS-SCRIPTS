#!/usr/bin/env bash

# Kept for compatibility with existing download commands.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$SCRIPT_DIR/debian12.sh" "$@"
