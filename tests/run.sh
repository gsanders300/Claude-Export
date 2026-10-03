#!/usr/bin/env bash
# Tests for claude-export. Usage: tests/run.sh
#
# The script runs under the same bash as this file, so `/bin/bash tests/run.sh`
# on macOS covers bash 3.2. `UPDATE=1 tests/run.sh` rewrites the expected
# outputs in tests/expected; review that diff before committing it.
#
# No pipefail: `... | grep -q` checks would fail whenever grep exits early.
set -u

cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/claude-export.sh"
FIX="$PWD/tests/fixtures"
EXP="$PWD/tests/expected"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Isolate from the real Claude Code folder and make times deterministic.
export TZ=UTC HOME=/home/tester USER=tester
unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME CLAUDE_EXPORT_DIR CLAUDE_EXPORT_REDACT_DOMAINS

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok    $1"; }
fail() {
  FAIL=$((FAIL + 1)); echo "FAIL  $1"
  if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed 's/^/      /'; fi
}
check() { if eval "$2"; then ok "$1"; else fail "$1" "${3:-}"; fi; }
run() { "$BASH" "$SCRIPT" "$@"; }

# The Exported line holds the current time, so blank it before comparing.
normalize() { sed -E 's/^(- \*\*Exported:\*\*) [0-9-]+ [0-9:]+ [A-Z]+/\1 (time)/' "$1"; }

golden() {
  local name="$1" diff; shift
  if ! run "$@" -o "$T/$name.md" "$FIX/basic.jsonl" > /dev/null; then fail "$name: export"; return; fi
  if [[ -n "${UPDATE:-}" ]]; then normalize "$T/$name.md" > "$EXP/$name.md"; fi
  if diff="$(normalize "$T/$name.md" | diff -u "$EXP/$name.md" -)"; then ok "$name matches expected output"
  else fail "$name matches expected output" "$diff"; fi
}

echo "Rendering"
golden basic
golden basic-tools --tools
golden basic-rich --tools --rich
for s in "SYSTEM REMINDER" SIDECHAIN SYNTHETIC META "/cost"; do
  check "drops $s content" "! grep -qF '$s' '$T/basic-tools.md'"
done

echo "Redaction"
# Secrets are assembled at run time so secret scanners don't flag the repo.
SK="sk-""ant-api03-abcdefghijklmnopqrstuvwxyz012345"
AWS="AKIA""IOSFODNN7EXAMPLE"
GH="gh""p_abcdefghijklmnopqrstuvwxyz0123456789"
JWT="ey""JhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0ZXIifQ.c2lnbmF0dXJlLXZhbHVl"
PEM="$(printf '%s\n' "-----BEGIN RSA PRIV""ATE KEY-----" "MIIEowIBAAKCAQEAfakefakefake" "-----END RSA PRIV""ATE KEY-----")"
PROMPT="Use $SK to debug the login.
aws $AWS, gh $GH, jwt $JWT
Authorization: Bearer abcdefghijklmnop1234
password=hunter2hunter2
$PEM
Mail tester@example.com, host 10.1.2.3, docs https://wiki.corp.example.com/page/42
File /home/tester/code/app/main.py is owned by tester."
jq -cn --arg p "$PROMPT" '{type: "user", sessionId: "r1", cwd: "/home/tester/code/app",
  timestamp: "2026-09-27T18:00:00.000Z", message: {role: "user", content: $p}}' > "$T/redact.jsonl"
jq -cn '{type: "assistant", sessionId: "r1", timestamp: "2026-09-27T18:00:05.000Z",
  message: {id: "m1", model: "claude-opus-5-5", content: [{type: "text", text: "Done."}]}}' >> "$T/redact.jsonl"

CLAUDE_EXPORT_DIR="$T/redact" CLAUDE_EXPORT_REDACT_DOMAINS="corp.example.com" run --redact "$T/redact.jsonl" > "$T/redact.log"
R="$(echo "$T"/redact/*.md)"
check "names the file from the redacted prompt" "[[ '$(basename "${R:-none}")' == 2026-09-27_app_use-redacted-token-to-debug-the.md ]]" "got: $(basename "${R:-none}")"
for s in "$SK" "$AWS" "$GH" "$JWT" "abcdefghijklmnop1234" "hunter2hunter2" "MIIEowIBAAKCAQEAfakefakefake" \
         "tester@example.com" "10.1.2.3" "wiki.corp.example.com" "/home/tester" "owned by tester"; do
  check "masks ${s:0:24}" "[[ -s '$R' ]] && ! grep -qF -- '$s' '$R'"
done
# shellcheck disable=SC2088  # the literal ~ is the expected output
for s in "[REDACTED PRIVATE KEY]" "[EMAIL]" "[PRIVATE IP]" "[INTERNAL URL]" "~/code/app/main.py" "owned by [USER]"; do
  check "writes $s" "grep -qF -- '$s' '$R'"
done
check "reports the count" "grep -q 'Redacted [1-9][0-9]* item' '$T/redact.log'"
run --redact -o "$T/redact-nodomains.md" "$T/redact.jsonl" > /dev/null
check "leaves URLs alone when no internal domains are set" "grep -qF 'https://wiki.corp.example.com/page/42' '$T/redact-nodomains.md'"

echo "File names"
mkdir -p "$T/names"
CLAUDE_EXPORT_DIR="$T/names" run "$FIX/basic.jsonl" > /dev/null
check "uses date_project_first-words.md" "[[ -f '$T/names/2026-09-27_uploader_add-retry-with-backoff-to-the.md' ]]"
sed 's/5f0c2a91-3b7e/aaaabbbb-3b7e/' "$FIX/basic.jsonl" > "$T/other.jsonl"
CLAUDE_EXPORT_DIR="$T/names" run "$T/other.jsonl" > /dev/null
check "adds the short session ID when the name is taken" "[[ -f '$T/names/2026-09-27_uploader_add-retry-with-backoff-to-the_aaaabbbb.md' ]]"
CLAUDE_EXPORT_DIR="$T/names" run "$FIX/basic.jsonl" > /dev/null
check "overwrites its own earlier export" "[[ \$(ls '$T/names' | wc -l) -eq 2 ]]"

echo "Empty sessions"
printf '%s\n' '{"type":"summary","summary":"x"}' > "$T/empty.jsonl"
CLAUDE_EXPORT_DIR="$T/empty" run "$T/empty.jsonl" > /dev/null 2> "$T/empty.log"
check "exits 0" "[[ $? -eq 0 ]]"
check "writes no file" "! ls '$T'/empty/*.md > /dev/null 2>&1"
check "says why" "grep -q 'no prompts or replies' '$T/empty.log'"

echo "Project matching"
mkdir -p "$T/cfg/projects/p1" "$T/work/proj/src/deep" "$T/work/other" "$T/home/notes" "$T/cfg/projects/p2"
PROJ="$(cd "$T/work/proj" && pwd -P)"
jq -cn --arg cwd "$PROJ" '{type: "user", sessionId: "s1", cwd: $cwd, timestamp: "2026-09-27T18:00:00.000Z",
  message: {role: "user", content: "hello from proj"}}' > "$T/cfg/projects/p1/s1.jsonl"
jq -cn --arg cwd "$(cd "$T/home" && pwd -P)" '{type: "user", sessionId: "s2", cwd: $cwd,
  timestamp: "2026-09-27T18:00:00.000Z", message: {role: "user", content: "hello from home"}}' > "$T/cfg/projects/p2/s2.jsonl"
where() { (cd "$1" && CLAUDE_CONFIG_DIR="$T/cfg" HOME="$(cd "$T/home" && pwd -P)" run "${@:2}" 2>&1); }
check "matches the project folder" "where '$T/work/proj' --where | grep -q '/projects/p1$'"
check "matches from a subfolder" "where '$T/work/proj/src/deep' --where | grep -q '/projects/p1$'"
check "says when it used a parent folder" "where '$T/work/proj/src/deep' --list | grep -q 'parent folder'"
check "lists that project's sessions" "where '$T/work/proj/src/deep' --list | grep -q 'hello from proj'"
check "finds nothing for an unrelated folder" "where '$T/work/other' --where | grep -q '(none found)'"
check "matches \$HOME exactly" "where '$T/home' --where | grep -q '/projects/p2$'"
check "doesn't match \$HOME as a parent" "where '$T/home/notes' --where | grep -q '(none found)'"
if [[ "$(uname)" == "Darwin" ]]; then
  UPPER="$(printf '%s' "$T/work/proj" | tr '[:lower:]' '[:upper:]')"
  check "ignores case on macOS" "where '$UPPER' --where | grep -q '/projects/p1$'"
fi

echo "Options"
check "--version matches VERSION" "[[ '$(run --version)' == 'claude-export $(sed -n 's/^VERSION="\(.*\)"/\1/p' "$SCRIPT")' ]]"
check "--help shows usage" "run --help | grep -q '^Usage: claude-export'"
check "rejects unknown options" "! run --bogus 2> /dev/null"
check "exports a .jsonl path without a transcript folder" "run -o '$T/plain.md' '$FIX/basic.jsonl' > /dev/null && [[ -s '$T/plain.md' ]]"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
