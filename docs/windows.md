# Windows notes

`claude-export` runs natively on Windows 11 through Git Bash (part of [Git for Windows](https://git-scm.com/download/win), which Claude Code already needs). Nothing here requires WSL.

## Native Windows (Git Bash)

1. Install jq from PowerShell, then restart your terminal and check it:

   ```powershell
   winget install jqlang.jq
   jq --version
   ```

2. Save the script as `~/bin/claude-export` with the [quick install](../README.md#quick-install) commands, run in Git Bash. If you copy the file another way, it needs Unix (LF) line endings. To fix one that has Windows (CRLF) endings:

   ```bash
   sed -i 's/\r$//' ~/bin/claude-export
   ```

3. If `~/bin` isn't on your `PATH`, add the `PATH` line from the quick install to `~/.bashrc`.
4. Check that it finds your project, from a folder where you've used Claude Code:

   ```bash
   claude-export --where
   claude-export --list
   ```

Inside a Claude Code session, `! claude-export` works as it does on macOS and Linux.

### Running it from PowerShell or Command Prompt

[`claude-export.cmd`](../claude-export.cmd) in this repo starts the script with Git's `bash.exe`. Put the folder that holds both files on your `PATH` (or keep them side by side), then run `claude-export` from any shell. If Git isn't in `C:\Program Files\Git`, edit the path in the `.cmd` file.

### What differs from macOS and Linux

- **Transcript paths:** Claude Code records `C:\Users\you\project`. The script converts between that and Git Bash's `/c/Users/you/project` for project matching, the **Project** header line, the **Files changed** list, and `--redact`.
- **Time zone names:** the header shows Windows' long name ("Eastern Daylight Time") where macOS and Linux show "EDT". The times are correct.
- **`--open`** starts the default app for `.md` files, **`--reveal`** selects the file in File Explorer, and **`--copy`** uses PowerShell's `Set-Clipboard` (so non-English text survives).
- **Auto-export hook:** the [README's hook](../README.md#export-every-session-automatically) works as written. Claude Code runs it through Git Bash, and the script strips the stray carriage return that `jq.exe` adds to `$(jq -r ...)`.

## WSL

Works as on Linux, as long as Claude Code also runs inside WSL (its transcripts then live in the WSL home folder). `--open`, `--reveal`, and `--copy` print a warning there.

## Testing

Run `bash tests/run.sh` from Git Bash. CI runs it on `windows-latest` too.

Not covered by the tests: `--open`, `--reveal`, and a Windows machine with jq 1.6 (the oldest supported version). CI installs the runner's jq, which is newer.
