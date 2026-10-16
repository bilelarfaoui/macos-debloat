#!/usr/bin/env bash
# Runs the whole dry run / apply / restore cycle against stubbed defaults and
# launchctl, with fake /Applications and Trash folders. Nothing real is touched.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STATE="$TMP/state"; BIN="$TMP/bin"; APPS="$TMP/Applications"; TRASH="$TMP/Trash"
mkdir -p "$STATE" "$BIN" "$APPS" "$TRASH" "$TMP/backups"
mkdir -p "$APPS/GarageBand.app" "$APPS/Pages.app" "$APPS/Safari.app"
: >"$STATE/launchctl.log"

cat >"$BIN/defaults" <<'EOF'
#!/usr/bin/env bash
f="$STATE_DIR/$(printf '%s__%s' "$2" "$3" | tr ' /' '__')"
case "$1" in
  read)   [ -f "$f" ] && cat "$f" || exit 1 ;;
  write)  v="$5"
          if [ "$4" = -bool ]; then case "$v" in true|yes|1) v=1 ;; *) v=0 ;; esac; fi
          printf '%s\n' "$v" >"$f" ;;
  delete) rm -f "$f" ;;
esac
EOF

cat >"$BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
D="$STATE_DIR/disabled"
case "$1" in
  print-disabled) cat "$D" 2>/dev/null || true ;;
  disable) l="${2##*/}"; echo "\"$l\" => disabled" >>"$D"; echo "disable $l" >>"$STATE_DIR/launchctl.log" ;;
  enable)  l="${2##*/}"; { grep -vF "\"$l\" =>" "$D" 2>/dev/null || true; } >"$D.new"; mv "$D.new" "$D"
           echo "enable $l" >>"$STATE_DIR/launchctl.log" ;;
  bootout) echo "bootout ${2##*/}" >>"$STATE_DIR/launchctl.log" ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/killall"
chmod +x "$BIN"/*

run() {
  STATE_DIR="$STATE" PATH="$BIN:$PATH" DEBLOAT_ASSUME_DARWIN=1 \
  DEBLOAT_APPS_DIR="$APPS" DEBLOAT_TRASH_DIR="$TRASH" DEBLOAT_BACKUP_ROOT="$TMP/backups" \
    "$ROOT/debloat.sh" "$@"
}
val() { cat "$STATE/$(printf '%s__%s' "$1" "$2" | tr ' /' '__')" 2>/dev/null || echo UNSET; }

fail=0
expect() { # expect "description" actual wanted
  if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1 (got '$2', wanted '$3')"; fail=1; fi
}

# starting point: dock recents is ON, everything else untouched
printf '1\n' >"$STATE/com.apple.dock__show-recents"

# 1. dry run changes nothing
run -c all >/dev/null 2>&1
expect "dry run leaves settings alone"  "$(val com.apple.dock show-recents)" 1
expect "dry run leaves apps alone"      "$([ -d "$APPS/GarageBand.app" ] && echo yes || echo no)" yes
expect "dry run writes no backup"       "$(ls "$TMP/backups" | wc -l | tr -d ' ')" 0

# 2. apply everything
run -c all -a -y >/dev/null 2>&1
expect "dock recents turned off"        "$(val com.apple.dock show-recents)" 0
expect "ads setting written"            "$(val com.apple.AdLib allowApplePersonalizedAdvertising)" 0
expect "key with spaces written"        "$(val com.apple.assistant.support 'Search Queries Data Sharing Status')" 2
expect "string setting written"         "$(val com.apple.CrashReporter DialogType)" none
expect "agent disabled"                 "$(grep -c 'disable com.apple.rcd' "$STATE/launchctl.log")" 1
expect "GarageBand moved out"           "$([ -d "$APPS/GarageBand.app" ] && echo yes || echo no)" no
expect "Pages moved out"                "$([ -d "$APPS/Pages.app" ] && echo yes || echo no)" no
expect "Safari left alone"              "$([ -d "$APPS/Safari.app" ] && echo yes || echo no)" yes
expect "GarageBand is in the Trash"     "$(ls "$TRASH" | grep -c '^GarageBand')" 1

# 3. second apply finds nothing to do
out="$(run -c all -a -y 2>&1)"
case "$out" in *"Nothing to do"*) echo "ok    second run is a no-op" ;; *) echo "FAIL  second run was not a no-op"; fail=1 ;; esac

# 4. restore
run --restore -y >/dev/null 2>&1
expect "dock recents restored to on"    "$(val com.apple.dock show-recents)" 1
expect "previously unset key removed"   "$(val com.apple.AdLib allowApplePersonalizedAdvertising)" UNSET
expect "agent re-enabled"               "$(grep -c 'enable com.apple.rcd' "$STATE/launchctl.log")" 1
expect "GarageBand back in place"       "$([ -d "$APPS/GarageBand.app" ] && echo yes || echo no)" yes

exit "$fail"
