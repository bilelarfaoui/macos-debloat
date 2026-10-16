#!/usr/bin/env bash
# basic sanity checks. Runs anywhere, touches nothing.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'ok    %s\n' "$desc"; else printf 'FAIL  %s\n' "$desc"; fail=1; fi
}

for f in debloat.sh lib/*.sh tests/*.sh; do
  check "bash -n $f" bash -n "$f"
done

check "--help"    ./debloat.sh --help
check "--version" ./debloat.sh --version
check "unknown option fails" bash -c '! ./debloat.sh --nope'
check "--list works" env DEBLOAT_ASSUME_DARWIN=1 ./debloat.sh --list
check "unknown category fails" bash -c '! DEBLOAT_ASSUME_DARWIN=1 ./debloat.sh -c nonsense'
check "refuses to run on non-macOS" bash -c '[ "$(uname -s)" = Darwin ] || ! ./debloat.sh'

# macOS ships bash 3.2, so none of the bash 4+ features are allowed
check "no bash 4+ features" bash -c "! grep -nE 'declare -A|mapfile|readarray|\\$\\{[A-Za-z_]+(,,|\\^\\^)|\\|&|&>>' debloat.sh lib/*.sh"

# data files: right number of fields, valid types, no tabs
check "defaults.txt has 6 fields per row" bash -c "! sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*\$/d' data/defaults.txt | awk -F'|' 'NF!=6{bad=1} END{exit !bad}'"
check "defaults.txt types are valid" bash -c "! sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*\$/d' data/defaults.txt | awk -F'|' '\$4!=\"bool\" && \$4!=\"int\" && \$4!=\"string\"{bad=1} END{exit !bad}'"
check "agents.txt has 3 fields per row" bash -c "! sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*\$/d' data/agents.txt | awk -F'|' 'NF!=3{bad=1} END{exit !bad}'"
check "apps.txt has 3 fields per row" bash -c "! sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*\$/d' data/apps.txt | awk -F'|' 'NF!=3{bad=1} END{exit !bad}'"
check "app names end in .app" bash -c "! sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*\$/d' data/apps.txt | cut -d'|' -f2 | grep -v '\\.app\$'"

exit "$fail"
