#!/usr/bin/env bash
# claude-export: export a Claude Code session to a formatted markdown transcript.
#
# Finds your Claude Code transcript folder and the current project's sessions
# automatically. Run it from inside a project folder, or from anywhere with --all.
#
# Installation (macOS):
#   1. Check that jq 1.6 or newer is installed (recent macOS versions include
#      it):   jq --version
#      If it's missing or older:   brew install jq
#   2. Save this file as ~/bin/claude-export and make it executable:
#        mkdir -p ~/bin
#        mv ~/Downloads/claude-export.sh ~/bin/claude-export
#        chmod +x ~/bin/claude-export
#   3. Add ~/bin to your PATH (one time only):
#        echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
#        source ~/.zshrc
#   4. Test it from a folder where you've used Claude Code:
#        claude-export --where
#        claude-export --list
#
#   Tip: inside a Claude Code session, type  ! claude-export  to export the
#   session you're in without leaving it.
#
#   Optional: to export every session automatically when it ends, add this
#   hook to ~/.claude/settings.json (merge it into any existing "hooks"):
#     {
#       "hooks": {
#         "SessionEnd": [
#           { "hooks": [ { "type": "command",
#             "command": "CLAUDE_EXPORT_DIR=~/Documents/claude-transcripts ~/bin/claude-export \"$(jq -r .transcript_path)\"" } ] }
#         ]
#       }
#     }
#
#   Also runs on Linux; --open, --reveal, and --copy are macOS only.
#   For Windows, see WINDOWS NOTES below the options.
#
# Usage: claude-export [options] [session] [output.md]
#
#   session          A number from --list, or a path to a .jsonl file.
#                    Defaults to the most recent session.
#   output.md        Output path. Defaults to a descriptive name, such as
#                    2026-09-27_coverage-monitor_refactor-the-publisher-list.md
#
# Finding sessions:
#   --list           List recent sessions (this project, or all projects if
#                    none match the current folder)
#   --all            Use sessions from all projects instead of just this one
#   --where          Show which folders were detected
#
# Content:
#   --tools          Include tool activity (files read or edited, commands run)
#                    in an appendix, linked from each reply
#   --rich           With --tools, show tool activity inline in collapsible
#                    sections instead (needs a viewer that renders HTML, such
#                    as VS Code, Obsidian, Typora, or GitHub)
#   --redact         Mask API keys, tokens, passwords, private keys, emails,
#                    internal URLs, private IP addresses, and your home folder
#
# Mac conveniences:
#   --open           Open the transcript in your default markdown app
#   --reveal         Show the transcript in Finder
#   --copy           Copy the transcript to the clipboard
#
# Other:
#   -o, --out FILE   Output path (same as the output.md argument)
#   -h, --help       Show this help
#
# Environment variables:
#   CLAUDE_EXPORT_DIR             Folder for exports (default: current folder)
#   CLAUDE_EXPORT_REDACT_DOMAINS  Comma-separated domains that --redact treats
#                                 as internal (default: internalfb.com,fburl.com,
#                                 fb.workplace.com)
#   CLAUDE_CONFIG_DIR             Custom Claude Code config folder, if you use one

# ---------------------------------------------------------------------------
# WINDOWS NOTES (for future work; none of this has been tested)
# ---------------------------------------------------------------------------
# Running it today:
#
#   WSL: works as is, as long as Claude Code also runs inside WSL (its
#   transcripts then live in the WSL home folder). Only --open, --reveal,
#   and --copy are unavailable; they print a warning.
#
#   Native Windows (Claude Code using Git Bash): run the script from Git
#   Bash, not PowerShell or Command Prompt.
#     1. Install jq from PowerShell, then restart Git Bash and check it:
#          winget install jqlang.jq
#          jq --version
#     2. Save the script as ~/bin/claude-export with Unix (LF) line endings.
#        Windows (CRLF) line endings stop bash from running it. To fix a
#        file that has them:
#          sed -i 's/\r$//' ~/bin/claude-export
#     3. If ~/bin isn't on your PATH, add the PATH line from installation
#        step 3 to ~/.bashrc (Git Bash) instead of ~/.zshrc.
#     4. Automatic project matching doesn't work yet (see to-do 1), so use
#        the all-projects list:
#          claude-export --all --list
#          claude-export --all 3
#
# To-do for full native Windows support:
#
#   1. Project matching (find_project_dir). Transcripts record Windows paths
#      such as C:\Users\geoff\project, but Git Bash's pwd returns
#      /c/Users/geoff/project, so they never match. Convert before
#      comparing, for example HERE_WIN="$(cygpath -w "$HERE")", and compare
#      case-insensitively, since Windows paths are. short_path also assumes
#      a Unix-style $HOME and needs the same treatment.
#
#   2. Paths inside the jq program. The Project header line, the Files
#      changed list (which trims "$cwd/"), and --redact's home-folder
#      masking all compare against Unix-style paths. Pass the Windows form
#      of $HOME as well (cygpath -w "$HOME") and handle backslash
#      separators.
#
#   3. Mac conveniences. Detect Windows with
#        case "$(uname)" in MINGW*|MSYS*|CYGWIN*) ... ;; esac
#      then map:
#        --open    start "" "$OUT"
#        --reveal  explorer //select,"$(cygpath -w "$OUT")"
#                  (the double slash stops Git Bash converting /select)
#        --copy    clip < "$OUT"
#                  (clip can garble non-English characters; PowerShell's
#                  Get-Content -Raw ... | Set-Clipboard is a safer option)
#      For WSL, the equivalents are wslview (from the wslu package) for
#      --open and clip.exe for --copy.
#
#   4. Timestamps. Check that jq's strflocaltime shows the correct local
#      time and time zone name in Windows builds of jq. If it doesn't,
#      switch to strftime and label times as UTC.
#
#   5. Auto-export hook. Claude Code runs hook commands through Git Bash on
#      Windows, so the hook in the installation section should work. Check
#      that transcript_path arrives in a form the script's file checks
#      accept, and change ~/Documents/claude-transcripts to a Windows-
#      friendly location if needed.
#
#   6. Testing. Run --where and --list first, then export a short session
#      with --tools, and confirm the header, links, and tool appendix look
#      right before relying on it.

set -euo pipefail

REDACT_DOMAINS="${CLAUDE_EXPORT_REDACT_DOMAINS-internalfb.com,fburl.com,fb.workplace.com}"

usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
die() { echo "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
GLOBAL=0; MODE=export; TOOLS=false; REDACT=false; RICH=false
OPEN=0; REVEAL=0; COPY=0; SEL=""; OUT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) GLOBAL=1 ;;
    --list) MODE=list ;;
    --where) MODE=where ;;
    --tools) TOOLS=true ;;
    --redact) REDACT=true ;;
    --rich) RICH=true ;;
    --open) OPEN=1 ;;
    --reveal) REVEAL=1 ;;
    --copy) COPY=1 ;;
    -o|--out)
      [[ $# -ge 2 ]] || die "$1 needs a file name."
      OUT_ARG="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Unknown option: $1 (see --help)" ;;
    *)
      if [[ -z "$SEL" ]]; then SEL="$1"
      elif [[ -z "$OUT_ARG" ]]; then OUT_ARG="$1"
      else die "Too many arguments (see --help)"; fi ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is not installed. Install it with: brew install jq"
case "$(jq --version 2>/dev/null)" in
  jq-1.[0-5]|jq-1.[0-5].*|jq-1.[0-5]-*) die "jq 1.6 or newer is required. Update with: brew install jq" ;;
esac

# ---------------------------------------------------------------------------
# jq helpers shared by listing and export
# ---------------------------------------------------------------------------
read -r -d '' JQ_DEFS << 'JQ' || true
def entries: [inputs | fromjson? | select(type == "object" and .isSidechain != true)];
def ts2epoch: try (sub("\\.[0-9]+"; "") | fromdate) catch null;
def localfmt(f): if . == null then "" else strflocaltime(f) end;
def clean: gsub("<system-reminder>[\\s\\S]*?</system-reminder>"; "") | gsub("^\\s+|\\s+$"; "");
def is_noise:
  . == ""
  or . == "(no content)"
  or test("^<(command-name|command-message|command-args|local-command-stdout|local-command-stderr|bash-input|bash-stdout|bash-stderr|user-prompt-submit-hook|task-notification)>")
  or startswith("[Request interrupted by user")
  or startswith("Caveat: The messages below were generated by the user");
def blocks_text:
  if type == "string" then .
  elif type == "array" then
    [ .[] | select(type == "object")
      | if .type == "text" then (.text // "") elif .type == "image" then "[image]" else empty end ]
    | join("\n\n")
  else "" end;
def prompt_text:
  if .isMeta == true or .isCompactSummary == true then null
  else (.message.content | blocks_text | clean) as $t
    | if ($t | is_noise) then null else $t end
  end;
def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "");
def mdline($label; $val): if ($val // "") == "" then empty else "- **\($label):** \($val)" end;
JQ

# Filename parts: date|project|title|session id
read -r -d '' JQ_META << 'JQ' || true
entries as $E
| ($E | map(.timestamp // empty | ts2epoch) | map(select(. != null)) | min | localfmt("%Y-%m-%d")) as $day
| ($E | map(.cwd // empty) | first // ""
   | if . == $home then "home" else (split("/") | last // "" | slug) end) as $proj
| ($E | map(select(.type == "user") | prompt_text | select(. != null)) | first // ""
   | split("\n") | .[0] // "" | slug | split("-") | .[0:6] | join("-") | .[0:50] | gsub("-+$"; "")) as $title
| ($E | map(.sessionId // empty) | first // "") as $sid
| [$day, $proj, $title, $sid] | join("|")
JQ

# Full transcript
read -r -d '' JQ_MAIN << 'JQ' || true
def when($day):
  (.ts | ts2epoch) as $e
  | if $e == null then ""
    elif ($e | localfmt("%Y-%m-%d")) == $day then ($e | localfmt("%H:%M"))
    else ($e | localfmt("%Y-%m-%d %H:%M")) end;
def dur:
  if . == null or . < 0 then "" else
    floor as $s | (($s / 3600) | floor) as $h | ((($s % 3600) / 60) | floor) as $m | ($s % 60) as $sec
    | if $h > 0 then "\($h)h \($m)m" elif $m > 0 then "\($m)m \($sec)s" else "\($s)s" end
  end;
def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def trunc($n): if length > $n then .[0:$n] + "\n... [truncated \(length - $n) more characters]" else . end;

# Code block whose fence is always longer than any backtick run inside it.
def fenced($lang):
  ([match("`{3,}"; "g") | .length] | max // 2) as $m
  | ("`" * ([$m + 1, 3] | max)) as $f
  | "\($f)\($lang)\n\(.)\n\($f)";

def langmap: {
  py: "python", js: "javascript", mjs: "javascript", ts: "typescript", tsx: "tsx", jsx: "jsx",
  json: "json", md: "markdown", sh: "bash", bash: "bash", zsh: "bash", yml: "yaml", yaml: "yaml",
  html: "html", css: "css", scss: "scss", sql: "sql", go: "go", rs: "rust", java: "java",
  kt: "kotlin", swift: "swift", rb: "ruby", php: "php", c: "c", h: "c", cpp: "cpp", hpp: "cpp",
  cs: "csharp", toml: "toml", xml: "xml", csv: "csv", ini: "ini", r: "r", ipynb: "json"
};
def lang_of:
  (split("/") | last // "" | split(".")) as $p
  | if ($p | length) > 1 then ($p[-1] | ascii_downcase) as $ext | (langmap | .[$ext]) // "text" else "text" end;

# Backslash-escape "<" outside inline code so pasted tags stay visible
# (standard markdown; autolinks like <https://...> are kept).
def esc_inline:
  split("`") | to_entries
  | map(if .key % 2 == 0 then (.value | gsub("<(?!https?://)"; "\\<")) else .value end)
  | join("`");

# Clean up markdown inside a message: demote headings by three levels,
# keep code blocks intact (closing any left open), escape stray tags,
# collapse blank-line runs, and add blank lines around code blocks,
# headings, rules, and lists.
def fixmd:
  reduce split("\n")[] as $l ({out: [], fence: null, inlist: false, after_fence: false};
    def lastblank: (.out | length) == 0 or (.out[-1] | test("^\\s*$"));
    if .fence != null then
      .out += [$l]
      | ($l | sub("^\\s{0,3}"; "") | sub("\\s+$"; "")) as $t
      | if ($t | length) >= .fence.n and ($t | test("^[`~]+$")) and ($t | split("") | unique) == [.fence.c]
        then .fence = null | .after_fence = true else . end
    elif ($l | test("^\\s{0,3}(```|~~~)")) then
      ($l | sub("^\\s+"; "") | capture("^(?<f>[`~]+)").f) as $f
      | (if lastblank then . else .out += [""] end)
      | .out += [$l]
      | .fence = {c: ($f | .[0:1]), n: ($f | length)}
      | .inlist = false | .after_fence = false
    elif ($l | test("^\\s*$")) then
      (if lastblank then . else .out += [""] end) | .after_fence = false
    else
      (if .after_fence then .out += [""] else . end) | .after_fence = false
      | if ($l | test("^\\s{0,3}([-*_])(\\s*\\1){2,}\\s*$")) then
          (if lastblank then . else .out += [""] end) | .out += [$l] | .inlist = false
        elif ($l | test("^\\s{0,3}#{1,6}(\\s|$)")) then
          ($l | capture("^\\s{0,3}(?<h>#{1,6})(?<rest>.*)$")) as $m
          | (if lastblank then . else .out += [""] end)
          | .out += [("#" * ([($m.h | length) + 3, 6] | min)) + ($m.rest | esc_inline)]
          | .inlist = false
        elif ($l | test("^\\s*([-*+]|[0-9]+[.)])\\s")) then
          (if .inlist or lastblank then . else .out += [""] end)
          | .out += [$l | esc_inline] | .inlist = true
        else
          .out += [$l | esc_inline]
        end
    end
  )
  | (if .fence != null then .out += [.fence.c * .fence.n] else . end)
  | .out | join("\n") | gsub("^\\n+|\\n+$"; "");

def quote: split("\n") | map(if . == "" then ">" else "> " + . end) | join("\n");

# One-line title from a prompt, safe for headings and links.
def snippet($n):
  split("\n") | map(select(test("\\S"))) | (.[0] // "")
  | gsub("^[\\s#>*+-]+"; "") | gsub("[`*]"; "")
  | gsub("\\s+"; " ")
  | (if length > $n then (.[0:$n] | sub("\\s+\\S*$"; "") | sub("[\\s.,;:!?-]+$"; "")) + "..." else . end)
  | gsub("<"; "\\<") | gsub("(?<c>[\\[\\]])"; "\\\(.c)");

def result_text:
  .content
  | if type == "string" then .
    elif type == "array" then
      [ .[] | select(type == "object") | if .type == "text" then (.text // "") else "[\(.type)]" end ] | join("\n")
    else "" end;
def tool_label:
  (try ((.input // {}) | (.file_path // .notebook_path // .command // .pattern // .path // .url // .query // .description // "") | tostring) catch "")
  | split("\n") | .[0] // "" | .[0:90];
def tool_input:
  (.input // {})
  | if type == "object" then
      to_entries | map("\(.key): \(.value | if type == "string" then . else tojson end)") | join("\n")
    else tojson end;
def edit_diff:
  ((.old_string // "") | split("\n") | map("-" + .)) + ((.new_string // "") | split("\n") | map("+" + .))
  | join("\n");

def tool_cat:
  if . == "Read" then "read"
  elif . == "Edit" or . == "MultiEdit" or . == "Write" or . == "NotebookEdit" then "edit"
  elif . == "Bash" or . == "BashOutput" then "cmd"
  elif . == "Grep" or . == "Glob" or . == "LS" then "search"
  elif . == "WebFetch" or . == "WebSearch" then "web"
  elif . == "Task" or . == "Agent" then "agent"
  elif . == "TodoWrite" then "todo"
  else "other" end;

# "Read 3 files, edited 1 file, ran 2 commands"
def activity_line:
  [ .[] | select(.kind == "tool") | (.name // "" | tool_cat) ] as $c
  | def n($k): [$c[] | select(. == $k)] | length;
    def pl($x; $one; $many): if $x == 1 then $one else $many end;
  [ (n("read") | select(. > 0) | "read \(.) \(pl(.; "file"; "files"))"),
    (n("edit") | select(. > 0) | "edited \(.) \(pl(.; "file"; "files"))"),
    (n("cmd") | select(. > 0) | "ran \(.) \(pl(.; "command"; "commands"))"),
    (n("search") | select(. > 0) | "ran \(.) \(pl(.; "search"; "searches"))"),
    (n("web") | select(. > 0) | "made \(.) web \(pl(.; "request"; "requests"))"),
    (n("agent") | select(. > 0) | "ran \(.) subagent \(pl(.; "task"; "tasks"))"),
    (n("todo") | select(. > 0) | "updated the to-do list"),
    (n("other") | select(. > 0) | "used \(.) other \(pl(.; "tool"; "tools"))") ]
  | join(", ")
  | if . == "" then "" else "_" + (.[0:1] | ascii_upcase) + .[1:] + "_" end;

def codespan: if test("`") then "`` " + . + " ``" else "`" + . + "`" end;

def tool_parts($results; $cwd):
  ($results[.id // ""]) as $r
  | (.name // "unknown") as $name
  | (if (.input | type) == "object" then .input else {} end) as $o
  | ($o.file_path // $o.notebook_path // "") as $fp
  | (if $fp == "" then "text" else ($fp | lang_of) end) as $lang
  | ($r != null and $r.is_error == true) as $err
  | (tool_label | if $cwd != "" then ltrimstr($cwd + "/") else . end) as $lbl
  | (if $name == "Bash" then
       (if ($o.description // "") != "" then "_\($o.description | gsub("<"; "\\<"))_\n\n" else "" end)
       + (($o.command // "") | trunc(3000) | fenced("bash"))
     elif $name == "Edit" then ($o | edit_diff | trunc(3000) | fenced("diff"))
     elif $name == "MultiEdit" then (($o.edits // []) | map(edit_diff | trunc(1500) | fenced("diff")) | join("\n\n"))
     elif $name == "Write" then (($o.content // "") | trunc(3000) | fenced($lang))
     elif $name == "Read" then ""
     else (tool_input | trunc(3000) | fenced("text")) end) as $body
  | (if $r == null then ""
     elif ($err | not) and ($name == "Edit" or $name == "MultiEdit" or $name == "Write") then ""
     else (if $err then "**Error:**" else "Output:" end) + "\n\n"
          + ($r | result_text | trunc(2000) | fenced(if $name == "Read" and ($err | not) then $lang else "text" end))
     end) as $out
  | {name: $name, lbl: $lbl, err: $err, tn: .tn,
     content: ([$body, $out] | map(select(. != "")) | join("\n\n"))};

# --rich: collapsible section, inline in the reply
def render_tool_rich($results; $cwd):
  tool_parts($results; $cwd)
  | "<details>\n<summary>\(.name | esc)"
    + (if .lbl == "" then "" else ": <code>\(.lbl | esc)</code>" end)
    + (if .err then " (error)" else "" end)
    + "</summary>\n\n" + .content + "\n\n</details>";

# Default: numbered entry in the Tool activity appendix
def render_tool_plain($results; $cwd; $x):
  tool_parts($results; $cwd)
  | "### T\(.tn)\n\n**\(.name)**"
    + (if .lbl == "" then "" else ": " + (.lbl | codespan) end)
    + (if .err then " (error)" else "" end)
    + " · from [exchange \($x)](#exchange-\($x))"
    + (if .content == "" then "" else "\n\n" + .content end);

def redact($domre):
  gsub("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----"; "[REDACTED PRIVATE KEY]")
  | gsub("eyJ[A-Za-z0-9_-]{8,}\\.eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"; "[REDACTED TOKEN]")
  | gsub("\\b(sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|EAA[A-Za-z0-9]{30,})"; "[REDACTED TOKEN]")
  | gsub("(?<p>[Bb]earer\\s+)[A-Za-z0-9._~+/=-]{16,}"; "\(.p)[REDACTED TOKEN]")
  | gsub("(?<k>(api[_-]?key|secret|token|passw(or)?d|pwd|client[_-]?secret|access[_-]?key)[\"']?\\s*[:=]\\s*[\"']?)(?!\\[REDACTED)[^\\s\"',;]{6,}"; "\(.k)[REDACTED]"; "i")
  | (if $domre == "" then . else gsub("https?://([A-Za-z0-9-]+\\.)*(\($domre))(/[^\\s)\\]>\"'`]*)?"; "[INTERNAL URL]"; "i") end)
  | gsub("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"; "[EMAIL]")
  | gsub("\\b(10\\.[0-9]{1,3}|192\\.168|172\\.(1[6-9]|2[0-9]|3[01]))\\.[0-9]{1,3}\\.[0-9]{1,3}\\b"; "[PRIVATE IP]");

entries as $E
| ($domains | split(",") | map(gsub("^\\s+|\\s+$"; "") | select(length > 0) | gsub("\\."; "\\.")) | join("|")) as $domre
| ($E | map(.timestamp // empty | ts2epoch) | map(select(. != null))) as $times
| ($times | min) as $start
| ($times | max) as $end
| ($start | localfmt("%Y-%m-%d")) as $day
| ($E | map(.cwd // empty) | first // "") as $cwd
| ($E | map(.gitBranch // empty | select(. != "" and . != "HEAD")) | first // "") as $branch
| ($E | map(.version // empty) | first // "") as $version
| ($E | map(select(.type == "assistant") | .message.model // empty | select(. != "<synthetic>")) | unique | join(", ")) as $models
| ($E | map(.sessionId // empty) | first // "") as $sid
| ($E | map(select(.type == "user") | .message.content | select(type == "array") | .[]
          | select(type == "object" and .type == "tool_result") | {key: (.tool_use_id // ""), value: .})
      | from_entries) as $results
| ($E | map(select(.type == "assistant") | .message.content | select(type == "array") | .[]
          | select(type == "object" and .type == "tool_use"
                   and (.name as $n | ["Edit", "MultiEdit", "Write", "NotebookEdit"] | any(.[]; . == $n)))
          | (.input.file_path // .input.notebook_path // empty))
      | unique) as $changed
| [ $E[]
    | if .type == "user" then
        ((.message.content | blocks_text | clean)) as $raw
        | if ($raw | startswith("<task-notification>")) then
            {kind: "note", ts: .timestamp,
             text: ("Background task update: "
                    + ((($raw | capture("<summary>(?<s>[\\s\\S]*?)</summary>").s) // "a background task finished")
                       | gsub("\\s+"; " ") | gsub("<"; "\\<") | gsub("_"; "\\_")))}
          else prompt_text as $p | if $p == null then empty else {kind: "prompt", ts: .timestamp, text: $p} end
          end
      elif .type == "assistant" and .message.model != "<synthetic>" then
        .timestamp as $ts
        | (.message.id // null) as $mid
        | (.message.content | if type == "string" then [{type: "text", text: .}] elif type == "array" then . else [] end)
        | .[] | select(type == "object")
        | if .type == "text" then
            ((.text // "") | clean) as $t
            | if ($t | is_noise) then empty else {kind: "text", ts: $ts, mid: $mid, text: $t} end
          elif .type == "tool_use" then {kind: "tool", ts: $ts, name: .name, input: .input, id: .id}
          else empty end
      else empty end
  ] as $events
# Without --tools, drop tool calls but remember where they were, so a reply
# that follows a tool call isn't mistaken for an unprompted follow-up.
| (if $tools then $events
   else reduce $events[] as $e ({prev: null, out: []};
          if $e.kind == "tool" then .prev = "tool"
          else .out += [$e + {aftertool: (.prev == "tool")}] | .prev = $e.kind end) | .out
   end) as $events
| (reduce $events[] as $e ({n: 0, out: []};
    if $e.kind == "tool" then .n += 1 | .out += [$e + {tn: .n}] else .out += [$e] end) | .out) as $events
| (reduce $events[] as $ev ([];
    (if $ev.kind == "prompt" then "user" else "assistant" end) as $role
    | if length > 0 and .[length - 1].role == $role
      then (length - 1) as $i | .[$i].parts += [$ev]
      else . + [{role: $role, ts: $ev.ts, parts: [$ev]}] end
  )) as $turns
# Pair each prompt with the reply that follows it.
| (reduce $turns[] as $t ([];
    if $t.role == "user" or length == 0
    then . + [{user: (if $t.role == "user" then $t else null end),
               claude: (if $t.role == "assistant" then $t else null end)}]
    else (length - 1) as $i | .[$i].claude = $t end
  )) as $pairs
| ($pairs | to_entries
   | map(.value + {
       n: (.key + 1),
       ptext: (if .value.user != null then (.value.user.parts | map(.text) | join("\n\n")) else null end),
       w: ((.value.user // .value.claude).parts[0] | when($day))
     })
   | map(. + {title: (if .ptext == null then "Session start"
                      else (.ptext | snippet(70) | if . == "" then "(no text)" else . end) end)})) as $exs
| ($exs | map(select(.user != null)) | length) as $np
| ($exs | map(select(.claude != null)) | length) as $nr
| ($exs | map(select(.ptext != null)) | first | .ptext // "Claude Code session"
   | snippet(80) | if . == "" then "Claude Code session" else . end) as $title
| (if $cwd != "" and ($cwd | startswith($home)) then "~" + ($cwd | ltrimstr($home)) else $cwd end) as $proj
| ([ (if $tools then "tool activity" else empty end), (if $redact then "redaction" else empty end) ] | join(", ")) as $opts
| ($changed
   | map(if $cwd != "" and startswith($cwd + "/") then ltrimstr($cwd + "/")
         elif startswith($home) then "~" + ltrimstr($home) else . end)
   | map("`\(.)`")
   | (if length > 10 then .[0:10] + ["and \(length - 10) more"] else . end)
   | join(", ")) as $changedtxt
| ([ mdline("Project"; if $proj == "" then "" else "`\($proj)`" end),
     mdline("Branch"; if $branch == "" then "" else "`\($branch)`" end),
     mdline("Started"; $start | localfmt("%Y-%m-%d %H:%M %Z")),
     mdline("Ended"; $end | localfmt("%Y-%m-%d %H:%M %Z")),
     mdline("Duration"; if $start == null then "" else ($end - $start | dur) end),
     mdline("Exchanges"; "\($np) prompt\(if $np == 1 then "" else "s" end), \($nr) repl\(if $nr == 1 then "y" else "ies" end)"),
     mdline("Files changed"; $changedtxt),
     mdline("Model"; $models),
     mdline("Claude Code version"; $version),
     mdline("Session ID"; if $sid == "" then "" else "`\($sid)`" end),
     mdline("Exported"; $exported + (if $opts == "" then "" else " (with \($opts))" end))
   ] | join("\n")) as $header
| (if ($exs | length) >= 3 then
     "## Contents\n\n"
     + ($exs | map("\(.n). [\(.title)](#exchange-\(.n))" + (if .w == "" then "" else " (\(.w))" end)) | join("\n"))
   else "" end) as $toc
| def rx:
    ([ "## Exchange \(.n)",
       (if .ptext != null and (.ptext | test("\\n") | not) and (.ptext | length) <= 70
        then (if .w == "" then empty else "_\(.w)_" end)
        else "**\(.title)**" + (if .w == "" then "" else " (\(.w))" end) end) ] | join("\n\n"))
    + (if .ptext != null then "\n\n### You\n\n" + (.ptext | fixmd | quote) else "" end)
    + (if .claude != null then
         .claude.parts as $parts
         | ((.user.parts[0].ts // null) | if . == null then null else ts2epoch end) as $t0
         | ($parts | map(.ts | ts2epoch) | map(select(. != null)) | max) as $t1
         | (if $t0 != null and $t1 != null and $t1 > $t0 then ($t1 - $t0 | dur) else "" end) as $took
         | (if $tools then ($parts | activity_line) else "" end) as $act
         | (if $tools then ($parts | map(select(.kind == "tool") | .tn)) else [] end) as $tns
         | (if $rich or ($tns | length) == 0 then ""
            elif ($tns | length) > 8 then "[T\($tns[0])](#t\($tns[0])) through [T\($tns[-1])](#t\($tns[-1]))"
            else ($tns | map("[T\(.)](#t\(.))") | join(", ")) end) as $refs
         | (if $act == "" then "" elif $refs == "" then $act else $act + " (details: " + $refs + ")" end) as $actline
         | "\n\n### Claude" + (if $took == "" then "" else " (\($took))" end) + "\n\n"
           + ([ (if $actline == "" then empty else $actline end),
                (range(0; $parts | length) as $i
                 | $parts[$i] as $p
                 | (if $i > 0 then $parts[$i - 1] else null end) as $prev
                 | if $p.kind == "tool" then
                     (if $rich and $tools then ($p | render_tool_rich($results; $cwd)) else empty end)
                   elif $p.kind == "note" then "_\($p.text)_"
                   else
                     # A new reply with no prompt or tool call in between
                     # (for example, after a background task reported back).
                     ($prev != null and $prev.kind == "text" and ($p.aftertool != true)
                      and (if $prev.mid != null and $p.mid != null then $prev.mid != $p.mid
                           else (($prev.ts | ts2epoch) as $a | ($p.ts | ts2epoch) as $b
                                 | $a != null and $b != null and $b - $a >= 60) end)) as $followup
                     | (if $followup then "_Follow-up at \($p | when($day))_\n\n" else "" end) + ($p.text | fixmd)
                   end) ]
              | map(select(. != "")) | join("\n\n"))
       else "" end);
  ([ $exs[] | rx ] | join("\n\n---\n\n")) as $body
| (if $rich or ($tools | not) then ""
   else [ $exs[] | .n as $x | (.claude.parts // [])[] | select(.kind == "tool")
          | render_tool_plain($results; $cwd; $x) ] | join("\n\n")
   end) as $appendix
| ("# \($title)\n\n" + $header + (if $toc == "" then "" else "\n\n" + $toc end) + "\n\n---\n\n" + $body
   + (if $appendix == "" then "" else "\n\n---\n\n## Tool activity\n\n" + $appendix end) + "\n")
| if $redact then redact($domre) | split($home) | join("~") | split($home | gsub("/"; "-")) | join("~") else . end
JQ

# ---------------------------------------------------------------------------
# Finding transcripts
# ---------------------------------------------------------------------------
# Checks, in order: $CLAUDE_CONFIG_DIR, ~/.claude, ~/.config/claude
find_roots() {
  local candidates=() seen="" c real
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then candidates+=("$CLAUDE_CONFIG_DIR"); fi
  candidates+=("$HOME/.claude" "${XDG_CONFIG_HOME:-$HOME/.config}/claude")
  for c in "${candidates[@]}"; do
    if [[ -d "$c/projects" ]]; then
      real="$(cd "$c/projects" && pwd -P)"
      case "$seen" in *"|$real|"*) continue ;; esac
      seen="$seen|$real|"
      echo "$real"
    fi
  done
}

session_cwd() {
  jq -Rrn 'first(inputs | fromjson? | select(type == "object" and .cwd) | .cwd)' "$1" 2>/dev/null || true
}

first_prompt() {
  { jq -Rrn "$JQ_DEFS"'
      first(inputs | fromjson? | select(type == "object" and .type == "user" and .isSidechain != true)
            | prompt_text | select(. != null))' "$1" 2>/dev/null || true; } \
    | tr '\n' ' ' | sed 's/[[:space:]]*$//' | cut -c1-70
}

short_path() {
  case "$1" in
    "$HOME"*) echo "~${1#"$HOME"}" ;;
    *) echo "$1" ;;
  esac
}

ROOTS="$(find_roots)"
if [[ -z "$ROOTS" ]]; then
  echo "Could not find a Claude Code transcript folder." >&2
  echo "Checked: ${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/projects, }$HOME/.claude/projects, ${XDG_CONFIG_HOME:-$HOME/.config}/claude/projects" >&2
  die "If yours is elsewhere, set CLAUDE_CONFIG_DIR to the folder that contains 'projects'."
fi

HERE="$(pwd)"
HERE_REAL="$(pwd -P)"

# Match the working directory recorded inside each project's newest session.
find_project_dir() {
  local root dir f cwd
  while IFS= read -r root; do
    for dir in "$root"/*/; do
      [[ -d "$dir" ]] || continue
      f="$(ls -t "$dir"*.jsonl 2>/dev/null | head -1 || true)"
      [[ -n "$f" ]] || continue
      cwd="$(session_cwd "$f")"
      if [[ "$cwd" == "$HERE" || "$cwd" == "$HERE_REAL" ]]; then
        echo "${dir%/}"
        return
      fi
    done
  done <<< "$ROOTS"
}

PROJECT_DIR=""
if [[ $GLOBAL -eq 0 && "$SEL" != *.jsonl ]]; then
  PROJECT_DIR="$(find_project_dir)"
  if [[ -z "$PROJECT_DIR" && "$MODE" != "where" ]]; then
    echo "No sessions found for $(short_path "$HERE"); using all projects." >&2
    echo >&2
    GLOBAL=1
  fi
fi

# Newest first; skips subagent transcripts.
sessions() {
  {
    if [[ $GLOBAL -eq 0 ]]; then
      ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null || true
    else
      local args=() root
      while IFS= read -r root; do args+=("$root"/*/*.jsonl); done <<< "$ROOTS"
      ls -t "${args[@]}" 2>/dev/null || true
    fi
  } | { grep -v '/agent-[^/]*\.jsonl$' || true; }
}

list_sessions() {
  local i=1 f
  if [[ $GLOBAL -eq 0 ]]; then
    echo "Recent sessions for $(short_path "$HERE"):"
  else
    echo "Recent sessions across all projects:"
  fi
  echo
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    printf "%2d) %s  %s" "$i" "$(date -r "$f" "+%Y-%m-%d %H:%M")" "$(basename "$f" .jsonl | cut -c1-8)"
    if [[ $GLOBAL -eq 1 ]]; then printf "  %s" "$(short_path "$(session_cwd "$f")")"; fi
    printf "\n    \"%s\"\n\n" "$(first_prompt "$f")"
    i=$((i + 1))
  done <<< "$(sessions | head -15 || true)"
  if [[ $GLOBAL -eq 1 ]]; then
    echo "To export one of these, use: claude-export --all <number>"
  fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
if [[ "$MODE" == "where" ]]; then
  echo "Transcript folder(s):"
  while IFS= read -r r; do echo "  $r"; done <<< "$ROOTS"
  echo "Project folder for $(short_path "$HERE"):"
  echo "  ${PROJECT_DIR:-(none found)}"
  exit 0
fi

if [[ "$MODE" == "list" ]]; then
  list_sessions
  exit 0
fi

if [[ -z "$SEL" ]]; then
  FILE="$(sessions | head -1 || true)"
elif [[ "$SEL" =~ ^[0-9]+$ ]]; then
  FILE="$(sessions | sed -n "${SEL}p" || true)"
else
  FILE="$SEL"
fi
if [[ -z "${FILE:-}" || ! -f "$FILE" ]]; then
  die "Session not found. Run with --list to see options."
fi

# Descriptive output name: date_project_first-words-of-first-prompt.md
IFS='|' read -r DAY PROJ SLUG SID <<< "$(jq -Rrn --arg home "$HOME" "$JQ_DEFS $JQ_META" "$FILE" 2>/dev/null || true)"
if [[ -n "$OUT_ARG" ]]; then
  OUT="$OUT_ARG"
else
  name=""
  for part in "${DAY:-}" "${PROJ:-}" "${SLUG:-}"; do
    if [[ -n "$part" ]]; then name="${name:+${name}_}${part}"; fi
  done
  if [[ -z "$name" ]]; then name="session-$(basename "$FILE" .jsonl | cut -c1-8)"; fi
  OUT_DIR="${CLAUDE_EXPORT_DIR:-$PWD}"
  mkdir -p "$OUT_DIR"
  OUT="$OUT_DIR/$name.md"
  # Same name but a different session: add the short session ID.
  if [[ -f "$OUT" && -n "${SID:-}" ]] && ! grep -qF "$SID" "$OUT"; then
    OUT="$OUT_DIR/${name}_${SID:0:8}.md"
  fi
fi

TMP="$OUT.tmp.$$"
if ! jq -Rrn \
    --argjson tools "$TOOLS" \
    --argjson redact "$REDACT" \
    --argjson rich "$RICH" \
    --arg home "$HOME" \
    --arg domains "$REDACT_DOMAINS" \
    --arg exported "$(date '+%Y-%m-%d %H:%M %Z')" \
    "$JQ_DEFS $JQ_MAIN" "$FILE" > "$TMP"; then
  rm -f "$TMP"
  die "Export failed while converting $(basename "$FILE")."
fi
mv -f "$TMP" "$OUT"

echo "Exported session from $(short_path "$(session_cwd "$FILE")")"
echo "  to $(short_path "$OUT")"

if [[ "$REDACT" == "true" ]]; then
  n="$(grep -oE '\[(REDACTED[A-Z ]*|EMAIL|INTERNAL URL|PRIVATE IP)\]' "$OUT" | wc -l | tr -d ' ' || true)"
  echo "Redacted $n item(s). Automatic redaction can miss things, so skim before sharing."
fi

# Mac conveniences
if [[ $COPY -eq 1 ]]; then
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy < "$OUT" && echo "Copied to clipboard."
  else
    echo "--copy needs pbcopy, which is only available on macOS." >&2
  fi
fi
if [[ $OPEN -eq 1 || $REVEAL -eq 1 ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    if [[ $OPEN -eq 1 ]]; then open "$OUT"; fi
    if [[ $REVEAL -eq 1 ]]; then open -R "$OUT"; fi
  else
    echo "--open and --reveal are only available on macOS." >&2
  fi
fi
