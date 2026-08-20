#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this command as root." >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage:
  user-manager.sh add USER [DAYS]
  user-manager.sh list
  user-manager.sh password USER
  user-manager.sh expire USER DAYS
  user-manager.sh disable USER
  user-manager.sh enable USER
  user-manager.sh delete USER

DAYS is the number of days until account expiration.
Use 0 with expire to remove the expiration date.
EOF
}

valid_user() {
  [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

require_user() {
  local username=$1 uid
  valid_user "$username" || { echo "Invalid username: $username" >&2; exit 1; }
  id "$username" >/dev/null 2>&1 || { echo "User does not exist: $username" >&2; exit 1; }
  uid=$(id -u "$username")
  (( uid >= 1000 )) || { echo "Refusing to modify system user: $username" >&2; exit 1; }
}

read_password() {
  local first second
  read -r -s -p "Password: " first
  printf '\n'
  read -r -s -p "Confirm password: " second
  printf '\n'
  [[ -n $first && $first == "$second" ]] || {
    echo "Passwords are empty or do not match." >&2
    exit 1
  }
  ACCOUNT_PASSWORD=$first
}

command_name=${1:-}
case "$command_name" in
  add)
    [[ $# -ge 2 && $# -le 3 ]] || { usage; exit 1; }
    username=$2
    valid_user "$username" || { echo "Invalid username: $username" >&2; exit 1; }
    id "$username" >/dev/null 2>&1 && { echo "User already exists: $username" >&2; exit 1; }
    if [[ $# == 3 ]]; then
      [[ $3 =~ ^[1-9][0-9]*$ ]] || { echo "DAYS must be a positive integer." >&2; exit 1; }
    fi
    read_password
    useradd --create-home --shell /bin/bash "$username"
    printf '%s:%s\n' "$username" "$ACCOUNT_PASSWORD" | chpasswd
    if [[ $# == 3 ]]; then
      chage --expiredate "$(date -d "+$3 days" +%Y-%m-%d)" "$username"
    fi
    echo "Created user: $username"
    ;;
  list)
    printf '%-24s %-12s %-12s\n' USER STATUS EXPIRES
    while IFS=: read -r username _ uid _ _ _ shell; do
      (( uid >= 1000 )) || continue
      status=$(passwd --status "$username" | awk '{print $2}')
      expires=$(chage --list "$username" | awk -F: '/Account expires/ {gsub(/^ +/, "", $2); print $2}')
      printf '%-24s %-12s %-12s\n' "$username" "$status" "$expires"
    done < /etc/passwd
    ;;
  password)
    [[ $# == 2 ]] || { usage; exit 1; }
    require_user "$2"
    read_password
    printf '%s:%s\n' "$2" "$ACCOUNT_PASSWORD" | chpasswd
    echo "Password updated: $2"
    ;;
  expire)
    [[ $# == 3 && $3 =~ ^[0-9]+$ ]] || { usage; exit 1; }
    require_user "$2"
    if [[ $3 == 0 ]]; then
      chage --expiredate -1 "$2"
      echo "Expiration removed: $2"
    else
      chage --expiredate "$(date -d "+$3 days" +%Y-%m-%d)" "$2"
      echo "Expiration set: $2 ($3 days)"
    fi
    ;;
  disable)
    [[ $# == 2 ]] || { usage; exit 1; }
    require_user "$2"
    usermod --lock "$2"
    echo "Disabled user: $2"
    ;;
  enable)
    [[ $# == 2 ]] || { usage; exit 1; }
    require_user "$2"
    usermod --unlock "$2"
    echo "Enabled user: $2"
    ;;
  delete)
    [[ $# == 2 ]] || { usage; exit 1; }
    require_user "$2"
    read -r -p "Delete $2 and its home directory? [y/N] " answer
    [[ $answer == [yY] ]] || { echo "Cancelled."; exit 0; }
    userdel --remove "$2"
    echo "Deleted user: $2"
    ;;
  *)
    usage
    exit 1
    ;;
esac
