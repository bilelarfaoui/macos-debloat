#!/usr/bin/env bash
# macos-debloat: switch off telemetry, Siri and other noise on macOS, and
# optionally remove the Apple apps you never use.
# Dry run unless you pass --apply. Written for the bash 3.2 that ships with macOS.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

VERSION="0.1.0"
APPLY=0
ASSUME_YES=0
LIST_ONLY=0
RESTORE=0
RESTORE_DIR=""
CATEGORIES="telemetry,siri,annoyances"

DATA="$ROOT/data"
APPS_DIR="${DEBLOAT_APPS_DIR:-/Applications}"
TRASH_DIR="${DEBLOAT_TRASH_DIR:-$HOME/.Trash}"
BACKUP_ROOT="${DEBLOAT_BACKUP_ROOT:-$HOME/.macos-debloat}"
UNSET="__unset__"

usage() {
  cat <<EOF
macos-debloat $VERSION

Usage: ./debloat.sh [options]

  -a, --apply             make the changes (default is a dry run)
  -y, --yes               don't ask for confirmation
  -c, --categories LIST   comma separated, or "all"
                          (default: telemetry,siri,annoyances)
  -l, --list              show the categories
  -r, --restore [DIR]     undo a previous run (default: the latest one)
  -h, --help
  -v, --version

Don't run it with sudo, the settings are per user.

Examples:
  ./debloat.sh                       # preview
  ./debloat.sh -a                    # apply the default categories
  ./debloat.sh -c agents,apple-office -a
  ./debloat.sh --restore             # put everything back
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -a|--apply) APPLY=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -c|--categories)
      [ $# -ge 2 ] || die "--categories needs a value"
      CATEGORIES="$2"; shift ;;
    -l|--list) LIST_ONLY=1 ;;
    -r|--restore)
      RESTORE=1
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then RESTORE_DIR="$2"; shift; fi ;;
    -h|--help) usage; exit 0 ;;
    -v|--version) echo "$VERSION"; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done

# DEBLOAT_ASSUME_DARWIN is only for the tests, which run against stubbed tools.
if [ "${DEBLOAT_ASSUME_DARWIN:-0}" != 1 ]; then
  [ "$(uname -s)" = Darwin ] || die "This is for macOS."
  [ "$(id -u)" -ne 0 ] || die "Don't run this as root, it would change root's settings instead of yours."
fi
UID_="$(id -u)"

all_categories() {
  cat "$DATA/defaults.txt" "$DATA/agents.txt" "$DATA/apps.txt" | data_lines | cut -d'|' -f1 | sort -u | paste -sd, -
}

want() {
  case ",$CATEGORIES," in *",$1,"*) return 0 ;; esac
  return 1
}

count_lines() { wc -l <"$1" | tr -d ' '; }

PLAN="$(mktemp -d)"
trap 'rm -rf "$PLAN"' EXIT

restart_ui() {
  killall Dock Finder cfprefsd >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- list
if [ "$LIST_ONLY" -eq 1 ]; then
  for c in $(all_categories | tr ',' ' '); do
    d="$(data_lines <"$DATA/defaults.txt" | grep -c "^$c|" || true)"
    g="$(data_lines <"$DATA/agents.txt" | grep -c "^$c|" || true)"
    a="$(data_lines <"$DATA/apps.txt" | grep -c "^$c|" || true)"
    case ",telemetry,siri,annoyances," in *",$c,"*) def="(default)" ;; *) def="" ;; esac
    printf '  %-16s settings:%s agents:%s apps:%s %s\n' "$c" "$d" "$g" "$a" "$def"
  done
  exit 0
fi

# ---------------------------------------------------------------- restore
if [ "$RESTORE" -eq 1 ]; then
  if [ -z "$RESTORE_DIR" ]; then
    latest="$(ls -1 "$BACKUP_ROOT" 2>/dev/null | sort | tail -n 1 || true)"
    [ -n "$latest" ] || die "No backups found in $BACKUP_ROOT"
    RESTORE_DIR="$BACKUP_ROOT/$latest"
  fi
  [ -d "$RESTORE_DIR" ] || die "Not a directory: $RESTORE_DIR"
  log "Restoring from $RESTORE_DIR"
  confirm "Undo that run?" || die "Aborted."

  if [ -f "$RESTORE_DIR/defaults.txt" ]; then
    while IFS='|' read -r dom key type orig; do
      if [ "$orig" = "$UNSET" ]; then
        defaults delete "$dom" "$key" >/dev/null 2>&1 || true
      else
        case "$type" in
          bool) b=true; [ "$orig" = 0 ] && b=false; defaults write "$dom" "$key" -bool "$b" ;;
          int) defaults write "$dom" "$key" -int "$orig" ;;
          *) defaults write "$dom" "$key" -string "$orig" ;;
        esac
      fi
    done <"$RESTORE_DIR/defaults.txt"
    restart_ui
  fi

  if [ -f "$RESTORE_DIR/agents.txt" ]; then
    while IFS= read -r label; do
      launchctl enable "gui/$UID_/$label" || warn "Couldn't re-enable $label"
    done <"$RESTORE_DIR/agents.txt"
    log "Agents are re-enabled, they start again at your next login."
  fi

  if [ -f "$RESTORE_DIR/apps.txt" ]; then
    while IFS='|' read -r trashed original; do
      if [ -d "$trashed" ] && [ ! -e "$original" ]; then
        mv "$trashed" "$original" || warn "Couldn't move $trashed back, try with sudo"
      else
        warn "Skipping $original (not in the Trash any more, or already exists)"
      fi
    done <"$RESTORE_DIR/apps.txt"
  fi

  ok "Restored."
  exit 0
fi

# ---------------------------------------------------------------- plan
ALL="$(all_categories)"
[ "$CATEGORIES" = all ] && CATEGORIES="$ALL"
old_ifs="$IFS"; IFS=,
for c in $CATEGORIES; do
  case ",$ALL," in
    *",$c,"*) ;;
    *) IFS="$old_ifs"; die "Unknown category '$c' (see --list)" ;;
  esac
done
IFS="$old_ifs"

norm() {
  case "$1:$2" in
    bool:true) echo 1 ;;
    bool:false) echo 0 ;;
    *) echo "$2" ;;
  esac
}

: >"$PLAN/defaults"; : >"$PLAN/agents"; : >"$PLAN/apps"

data_lines <"$DATA/defaults.txt" >"$PLAN/rows"
while IFS='|' read -r cat dom key type val desc; do
  want "$cat" || continue
  cur="$(defaults read "$dom" "$key" 2>/dev/null || true)"
  [ -n "$cur" ] || cur="$UNSET"
  if [ "$cur" = "$(norm "$type" "$val")" ]; then continue; fi
  printf '%s|%s|%s|%s|%s\n' "$dom" "$key" "$type" "$val" "$cur" >>"$PLAN/defaults"
  printf '    %s / %s: %s -> %s   (%s)\n' "$dom" "$key" "$cur" "$val" "$desc" >>"$PLAN/defaults.view"
done <"$PLAN/rows"

disabled="$(launchctl print-disabled "gui/$UID_" 2>/dev/null || true)"
data_lines <"$DATA/agents.txt" >"$PLAN/rows"
while IFS='|' read -r cat label desc; do
  want "$cat" || continue
  case "$disabled" in *"\"$label\" => disabled"*) continue ;; esac
  printf '%s\n' "$label" >>"$PLAN/agents"
  printf '    %s   (%s)\n' "$label" "$desc" >>"$PLAN/agents.view"
done <"$PLAN/rows"

data_lines <"$DATA/apps.txt" >"$PLAN/rows"
while IFS='|' read -r cat app desc; do
  want "$cat" || continue
  [ -d "$APPS_DIR/$app" ] || continue
  printf '%s\n' "$app" >>"$PLAN/apps"
  printf '    %s\n' "$app" >>"$PLAN/apps.view"
done <"$PLAN/rows"

nd="$(count_lines "$PLAN/defaults")"
ng="$(count_lines "$PLAN/agents")"
na="$(count_lines "$PLAN/apps")"

log "Categories: $CATEGORIES"
if [ "$nd" -gt 0 ]; then log "Settings to change ($nd):"; cat "$PLAN/defaults.view"; fi
if [ "$ng" -gt 0 ]; then log "Launch agents to disable ($ng):"; cat "$PLAN/agents.view"; fi
if [ "$na" -gt 0 ]; then log "Apps to move to the Trash ($na):"; cat "$PLAN/apps.view"; fi

if [ $((nd + ng + na)) -eq 0 ]; then
  ok "Nothing to do for these categories."
  exit 0
fi

if [ "$APPLY" -ne 1 ]; then
  warn "Dry run only. Run again with --apply to do it."
  exit 0
fi

# ---------------------------------------------------------------- apply
confirm "Apply these changes?" || die "Aborted."

BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ "$nd" -gt 0 ]; then
  while IFS='|' read -r dom key type val cur; do
    printf '%s|%s|%s|%s\n' "$dom" "$key" "$type" "$cur" >>"$BACKUP_DIR/defaults.txt"
    case "$type" in
      bool) defaults write "$dom" "$key" -bool "$val" ;;
      int) defaults write "$dom" "$key" -int "$val" ;;
      *) defaults write "$dom" "$key" -string "$val" ;;
    esac
  done <"$PLAN/defaults"
  restart_ui
fi

if [ "$ng" -gt 0 ]; then
  while IFS= read -r label; do
    printf '%s\n' "$label" >>"$BACKUP_DIR/agents.txt"
    launchctl disable "gui/$UID_/$label" || warn "Couldn't disable $label"
    launchctl bootout "gui/$UID_/$label" >/dev/null 2>&1 || true
  done <"$PLAN/agents"
fi

if [ "$na" -gt 0 ]; then
  mkdir -p "$TRASH_DIR"
  while IFS= read -r app; do
    src="$APPS_DIR/$app"
    if pgrep -f "$src/" >/dev/null 2>&1; then
      warn "Skipping $app, it's running. Quit it and run again."
      continue
    fi
    dest="$TRASH_DIR/${app%.app} $(date +%H.%M.%S).app"
    if mv "$src" "$dest"; then
      printf '%s|%s\n' "$dest" "$src" >>"$BACKUP_DIR/apps.txt"
    else
      warn "Couldn't move $app (root owned? try: sudo mv \"$src\" ~/.Trash/)"
    fi
  done <"$PLAN/apps"
fi

ok "Done. Undo with: ./debloat.sh --restore   (saved in $BACKUP_DIR)"
log "Some changes need a logout or restart to fully show up."
