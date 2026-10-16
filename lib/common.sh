#!/usr/bin/env bash
# helpers for debloat.sh. Keep this bash 3.2 friendly, that's what macOS ships.

if [ -t 1 ]; then
  C_B=$'\033[1;34m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_0=$'\033[0m'
else
  C_B=''; C_G=''; C_Y=''; C_R=''; C_0=''
fi

log()  { printf '%s[*]%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

# stdin -> stdout, minus comments and blank lines
data_lines() {
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d'
}

confirm() {
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  local answer=''
  read -r -p "$1 [y/N] " answer </dev/tty || return 1
  case "$answer" in y|Y) return 0 ;; *) return 1 ;; esac
}
