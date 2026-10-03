# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-02

### Changed

- `CLAUDE_EXPORT_REDACT_DOMAINS` now defaults to no domains. Set it to keep masking internal URLs.
- Project matching checks parent folders, so `claude-export` works from a project's subfolders.
- `--help` shows usage and options only. Installation and Windows notes moved to the README and `docs/windows.md`.

### Fixed

- jq 1.6 failed to compile the export program, even though it's the minimum supported version.
- `--redact` left secrets from the first prompt in the default file name.
- `--redact` didn't mask the bare username, for example in `ls -l` output.
- Project matching was case-sensitive on macOS, where folder names aren't.
- Sessions with no prompts or replies were exported as near-empty files.
- Exporting a `.jsonl` file by path failed when no Claude Code transcript folder existed.
- The jq install hint suggested Homebrew on Linux.

### Added

- Test suite (`tests/run.sh`) and CI on macOS (bash 3.2), Linux (bash 5), and Linux with jq 1.6.
- Version check: every commit must raise `VERSION` and add a CHANGELOG entry, enforced by a pre-commit hook and CI.

## [1.0.0] - 2026-10-02

First public release.

### Added

- Export a Claude Code session to Markdown with a summary header, table of contents, and timed exchanges.
- Automatic detection of the Claude Code transcript folder and the current project's sessions.
- `--list`, `--all`, and `--where` for finding sessions.
- `--tools` for a tool activity appendix, and `--rich` for inline collapsible tool sections.
- `--redact` for masking credentials, emails, internal URLs, private IP addresses, and the home folder.
- `--open`, `--reveal`, and `--copy` on macOS.
- `-o`/`--out`, plus the `CLAUDE_EXPORT_DIR`, `CLAUDE_EXPORT_REDACT_DOMAINS`, and `CLAUDE_CONFIG_DIR` environment variables.
- `--version`.
- Optional `SessionEnd` hook for exporting every session automatically.

[1.1.0]: https://github.com/gsanders300/Claude-Export/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/gsanders300/Claude-Export/releases/tag/v1.0.0
