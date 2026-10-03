#!/usr/bin/env bash
# Every commit must raise VERSION in claude-export.sh and add a matching
# "## [x.y.z]" entry to CHANGELOG.md.
#
#   scripts/check-version.sh            Check the staged commit (pre-commit hook)
#   scripts/check-version.sh BASE HEAD  Check each commit in BASE..HEAD (CI)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# An empty ref means the index (staged files).
version_at() { git show "$1:claude-export.sh" 2>/dev/null | sed -n 's/^VERSION="\(.*\)"$/\1/p'; }

# True if version $2 is higher than version $1 (x.y.z).
higher() {
  [[ "$1" != "$2" ]] &&
    [[ "$(printf '%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" == "$2" ]]
}

check() {
  local label="$1" old new
  old="$(version_at "$2")"; new="$(version_at "$3")"
  if [[ -z "$old" ]]; then return 0; fi
  if ! higher "$old" "$new"; then
    echo "$label: raise VERSION in claude-export.sh above $old (see CONTRIBUTING.md)." >&2
    return 1
  fi
  if ! git show "$3:CHANGELOG.md" | grep -q "^## \[$new\]"; then
    echo "$label: add a \"## [$new]\" entry to CHANGELOG.md." >&2
    return 1
  fi
}

if [[ $# -eq 0 ]]; then
  check "This commit" HEAD ""
else
  status=0
  for c in $(git rev-list --reverse --no-merges "$1..$2"); do
    check "$(git log -1 --format='%h %s' "$c")" "$c^" "$c" || status=1
  done
  exit $status
fi
