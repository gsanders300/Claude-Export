# Windows notes

> [!NOTE]
> None of this has been tested. These notes are a starting point for future work.

## Running it today

### WSL

Works as is, as long as Claude Code also runs inside WSL (its transcripts then live in the WSL home folder). Only `--open`, `--reveal`, and `--copy` are unavailable; they print a warning.

### Native Windows (Claude Code using Git Bash)

Run the script from Git Bash, not PowerShell or Command Prompt.

1. Install jq from PowerShell, then restart Git Bash and check it:

   ```bash
   winget install jqlang.jq
   jq --version
   ```

2. Save the script as `~/bin/claude-export` with Unix (LF) line endings. Windows (CRLF) line endings stop bash from running it. To fix a file that has them:

   ```bash
   sed -i 's/\r$//' ~/bin/claude-export
   ```

3. If `~/bin` isn't on your `PATH`, add the `PATH` line from the [README's quick install](../README.md#quick-install) to `~/.bashrc`.
4. Automatic project matching doesn't work yet (see to-do 1), so use the all-projects list:

   ```bash
   claude-export --all --list
   claude-export --all 3
   ```

## To-do for full native Windows support

1. **Project matching (`find_project_dir`).** Transcripts record Windows paths such as `C:\Users\geoff\project`, but Git Bash's `pwd` returns `/c/Users/geoff/project`, so they never match. Convert before comparing, for example `HERE_WIN="$(cygpath -w "$HERE")"`, and compare case-insensitively, since Windows paths are. `short_path` also assumes a Unix-style `$HOME` and needs the same treatment.
2. **Paths inside the jq program.** The Project header line, the Files changed list (which trims `"$cwd/"`), and `--redact`'s home-folder masking all compare against Unix-style paths. Pass the Windows form of `$HOME` as well (`cygpath -w "$HOME"`) and handle backslash separators.
3. **Mac conveniences.** Detect Windows with `case "$(uname)" in MINGW*|MSYS*|CYGWIN*) ... ;; esac`, then map:
   - `--open`: `start "" "$OUT"`
   - `--reveal`: `explorer //select,"$(cygpath -w "$OUT")"` (the double slash stops Git Bash converting `/select`)
   - `--copy`: `clip < "$OUT"` (`clip` can garble non-English characters; PowerShell's `Get-Content -Raw ... | Set-Clipboard` is a safer option)

   For WSL, the equivalents are `wslview` (from the `wslu` package) for `--open` and `clip.exe` for `--copy`.
4. **Timestamps.** Check that jq's `strflocaltime` shows the correct local time and time zone name in Windows builds of jq. If it doesn't, switch to `strftime` and label times as UTC.
5. **Auto-export hook.** Claude Code runs hook commands through Git Bash on Windows, so the [auto-export hook](../README.md#export-every-session-automatically) should work. Check that `transcript_path` arrives in a form the script's file checks accept, and change `~/Documents/claude-transcripts` to a Windows-friendly location if needed.
6. **Testing.** Run `--where` and `--list` first, then export a short session with `--tools`, and confirm the header, links, and tool appendix look right before relying on it. The test suite (`tests/run.sh`) should also pass from Git Bash.
