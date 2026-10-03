# claude-export

[![CI](https://github.com/gsanders300/Claude-Export/actions/workflows/ci.yml/badge.svg)](https://github.com/gsanders300/Claude-Export/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/gsanders300/Claude-Export)](https://github.com/gsanders300/Claude-Export/releases/latest)
[![License: MIT](https://img.shields.io/github/license/gsanders300/Claude-Export)](LICENSE)

Turn Claude Code sessions into clean, readable Markdown transcripts.

Claude Code saves every session as a raw JSONL log. `claude-export` finds the sessions for the folder you're in and converts one into a Markdown document with a summary header, a table of contents, and one section per prompt and reply. Optionally, it adds the files Claude read, the edits it made, and the commands it ran.

It's a single bash script. The only dependency is `jq`.

## Features

- **Zero configuration:** finds your Claude Code transcript folder and the current project's sessions automatically, even from a subfolder.
- **Readable transcripts:** each export has a header (project, branch, duration, model, files changed), a table of contents, and a timed section for each exchange.
- **Tool activity:** `--tools` adds an appendix of files read, edits (as diffs), and commands with their output, linked from each reply. Add `--rich` to show them inline in collapsible sections.
- **Redaction:** `--redact` masks API keys, tokens, passwords, private keys, email addresses, internal URLs, private IP addresses, your home folder, and your username, in both the transcript and its file name.
- **Descriptive file names:** for example, `2026-09-27_uploader_add-retry-with-backoff-to-the.md`.
- **Auto-export:** an optional Claude Code hook saves every session when it ends, skipping sessions with no prompts.
- **Safe Markdown:** headings inside messages are demoted so they don't break the outline, and code fences are always long enough to wrap any backticks they contain.

## Example output

A trimmed export of the [sample session](tests/fixtures/basic.jsonl) used in the tests, made with `--tools`:

````markdown
# Add retry with backoff to the uploader

- **Project:** `~/code/uploader`
- **Branch:** `main`
- **Started:** 2026-09-27 14:02 EDT
- **Ended:** 2026-09-27 14:19 EDT
- **Duration:** 17m 4s
- **Exchanges:** 3 prompts, 3 replies
- **Files changed:** `src/upload.py`, `tests/test_upload.py`
- **Model:** claude-opus-5-5
- **Claude Code version:** 2.1.288
- **Session ID:** `5f0c2a91-3b7e-4d8a-9c1f-2e6b8d4a7c30`
- **Exported:** 2026-09-27 14:20 EDT (with tool activity)

## Contents

1. [Add retry with backoff to the uploader](#exchange-1) (14:02)
2. [Run the tests and fix anything that fails](#exchange-2) (14:09)
3. [Looks good. Commit it.](#exchange-3) (14:18)

---

## Exchange 1

_14:02_

### You

> Add retry with backoff to the uploader

### Claude (2m 41s)

_Read 2 files, edited 1 file, ran 1 command_ (details: [T1](#t1), [T2](#t2), [T3](#t3), [T4](#t4))

Added exponential backoff to `upload_file()`: up to 5 attempts, starting at 1 second and doubling each time.

---

## Tool activity

### T3

**Edit**: `src/upload.py` · from [exchange 1](#exchange-1)

```diff
-    response = session.post(url, data=chunk)
+    response = with_backoff(lambda: session.post(url, data=chunk))
```
````

## Requirements

- **macOS or Linux:** tested with macOS's built-in bash 3.2 and bash 5. Windows works through WSL (see [Platform support](#platform-support)).
- **jq 1.6 or newer:** check with `jq --version`. Install with `brew install jq` (macOS) or `sudo apt install jq` (Debian/Ubuntu).
- **Claude Code:** at least 1 session in `~/.claude/projects`.

## Installation

### Quick install

Download the latest release into `~/bin`:

```bash
mkdir -p ~/bin
curl -fsSL https://github.com/gsanders300/Claude-Export/releases/latest/download/claude-export.sh -o ~/bin/claude-export
chmod +x ~/bin/claude-export
```

If `~/bin` isn't on your `PATH` yet, add it (use `~/.bashrc` instead if your shell is bash):

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Confirm it works:

```bash
claude-export --version
```

### Install a specific version

Replace `v1.0.0` with any tag from [Releases](https://github.com/gsanders300/Claude-Export/releases):

```bash
curl -fsSL https://github.com/gsanders300/Claude-Export/releases/download/v1.0.0/claude-export.sh -o ~/bin/claude-export
chmod +x ~/bin/claude-export
```

### Install from a clone

```bash
git clone https://github.com/gsanders300/Claude-Export.git
ln -s "$PWD/Claude-Export/claude-export.sh" ~/bin/claude-export
```

Run `git pull` in the clone to update.

### Update or uninstall

To update, run the quick install again. To uninstall, run `rm ~/bin/claude-export`.

## Usage

```text
claude-export [options] [session] [output.md]
```

- **`session`:** a number from `--list`, or a path to a `.jsonl` transcript. Defaults to the most recent session.
- **`output.md`:** where to write the transcript. Defaults to a descriptive name in the current folder (or `$CLAUDE_EXPORT_DIR`).

Run it from a project folder (or any subfolder of one) where you've used Claude Code:

```bash
claude-export                     # export the most recent session for this folder
claude-export --list              # list the 15 most recent sessions for this folder
claude-export 3                   # export session 3 from that list
claude-export --all --list        # list sessions across all projects
claude-export --all 2             # export session 2 from the all-projects list
claude-export --tools             # include tool activity in an appendix
claude-export --tools --rich      # show tool activity inline, in collapsible sections
claude-export --redact --copy     # mask secrets, then copy to the clipboard (macOS)
claude-export -o notes.md         # choose the output file
claude-export ~/path/to/session.jsonl   # export a specific transcript file
```

> [!TIP]
> Inside a Claude Code session, type `! claude-export` to export the session you're in without leaving it.

If no sessions match the current folder or its parent folders, `claude-export` falls back to all projects and tells you so.

### Options

| Option | Description |
| --- | --- |
| `--list` | List recent sessions for this project, or for all projects if none match the current folder |
| `--all` | Use sessions from all projects instead of just this one |
| `--where` | Show which transcript and project folders were detected |
| `--tools` | Include tool activity (files read or edited, commands run) in an appendix, linked from each reply |
| `--rich` | With `--tools`, show tool activity inline in collapsible sections (needs a viewer that renders HTML, such as VS Code, Obsidian, Typora, or GitHub) |
| `--redact` | Mask API keys, tokens, passwords, private keys, emails, internal URLs, private IP addresses, your home folder, and your username |
| `--open` | Open the transcript in your default Markdown app (macOS) |
| `--reveal` | Show the transcript in Finder (macOS) |
| `--copy` | Copy the transcript to the clipboard (macOS) |
| `-o`, `--out FILE` | Output path (same as the `output.md` argument) |
| `-h`, `--help` | Show help |
| `--version` | Show the version |

### Environment variables

| Variable | Description |
| --- | --- |
| `CLAUDE_EXPORT_DIR` | Folder for exports. Default: the current folder. |
| `CLAUDE_EXPORT_REDACT_DOMAINS` | Comma-separated domains that `--redact` treats as internal, such as `corp.example.com,intranet.example.org`. Subdomains are included. Default: none. |
| `CLAUDE_CONFIG_DIR` | Custom Claude Code config folder, if you use one. |

## Export every session automatically

Add this hook to `~/.claude/settings.json` to save each session to `~/Documents/claude-transcripts` when it ends. If you already have a `"hooks"` section, merge it in.

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "CLAUDE_EXPORT_DIR=~/Documents/claude-transcripts ~/bin/claude-export \"$(jq -r .transcript_path)\""
          }
        ]
      }
    ]
  }
}
```

Add `--redact` or `--tools` to the command to apply them to every export. Sessions you close before sending a prompt are skipped, so they don't leave empty files behind.

## Redaction

`--redact` masks:

- **Credentials:** API keys (Anthropic, OpenAI, AWS, GitHub, Slack, Google, Meta), JWTs, bearer tokens, private key blocks, and `key=value` pairs such as `password=...` or `api_key: ...`.
- **Personal details:** email addresses, your home folder path (shown as `~`), and your username (shown as `[USER]`; skipped if it's shorter than 3 characters or `root`).
- **Internal addresses:** private IP addresses (`10.x`, `172.16-31.x`, `192.168.x`) and URLs on the domains you list in `CLAUDE_EXPORT_REDACT_DOMAINS`. To set them for every export, add a line like this to `~/.zshrc`:

  ```bash
  export CLAUDE_EXPORT_REDACT_DOMAINS="corp.example.com,intranet.example.org"
  ```

The default file name is built from the redacted text, so secrets in your first prompt don't end up in it. After exporting, `claude-export` reports how many items it masked.

> [!WARNING]
> Pattern-based redaction can miss things. Skim a transcript before you share it.

## How it works

1. **Finds transcripts.** Checks `$CLAUDE_CONFIG_DIR`, `~/.claude`, and `~/.config/claude` for a `projects` folder.
2. **Matches your project.** Compares the working directory recorded in each project's newest session against your current folder, then its parent folders, nearest first. It also checks symlink-resolved paths, and ignores case on macOS. Your home folder only matches exactly, since almost every folder is inside it.
3. **Converts the session.** A single `jq` program pairs each prompt with its reply. It strips system reminders and slash-command noise, skips subagent transcripts, and renders the result as Markdown.
4. **Writes the file atomically.** Output goes to a temporary file first, so a failed export never leaves a half-written transcript. If the default name is already taken by a different session, the short session ID is appended.

## Platform support

| Platform | Status |
| --- | --- |
| macOS | Fully supported |
| Linux | Supported. `--open`, `--reveal`, and `--copy` are macOS only and print a warning. |
| Windows (WSL) | Works when Claude Code also runs inside WSL. Same limits as Linux. |
| Windows (Git Bash) | Untested. Automatic project matching doesn't work yet, so use `--all --list` and `--all <number>`. |

See [docs/windows.md](docs/windows.md) for Windows setup notes and a to-do list for full native support.

## Versioning

This project follows [Semantic Versioning](https://semver.org/). Run `claude-export --version` to see your version. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release, and [Releases](https://github.com/gsanders300/Claude-Export/releases) for downloads. To run the tests or cut a release, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Geoff Sanders
