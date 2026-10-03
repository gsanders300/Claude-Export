# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/).

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

[1.0.0]: https://github.com/gsanders300/Claude-Export/releases/tag/v1.0.0
