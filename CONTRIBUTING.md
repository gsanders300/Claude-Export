# Contributing

## Running the tests

```bash
tests/run.sh                          # run the tests
/bin/bash tests/run.sh                # on macOS, run them under the built-in bash 3.2
shellcheck claude-export.sh tests/run.sh
```

The tests export the sample sessions in [`tests/fixtures`](tests/fixtures) and compare the results with [`tests/expected`](tests/expected). They also cover redaction, file names, empty sessions, project matching, and options. They don't read your real Claude Code folder.

After an intentional change to the output, regenerate the expected files with `UPDATE=1 tests/run.sh`, then review the diff before committing it.

CI runs shellcheck and the tests on macOS (bash 3.2), Linux (bash 5), and Linux with jq 1.6.

## Compatibility

- **Bash 3.2:** macOS still ships it, so avoid associative arrays, `${var,,}`, `mapfile`, and `readarray`.
- **jq 1.6:** don't name jq variables after keywords such as `$label` or `$end`. jq 1.6 rejects them, even though newer versions accept them.

## Versioning

Every commit raises `VERSION` in `claude-export.sh` and adds a matching `## [x.y.z] - YYYY-MM-DD` entry to `CHANGELOG.md`, following [Semantic Versioning](https://semver.org/):

- **Patch** (`1.1.0` → `1.1.1`): fixes, docs, tests, and other changes that don't affect how you use the tool.
- **Minor** (`1.1.0` → `1.2.0`): new features or changed behavior that stays backward compatible.
- **Major** (`1.1.0` → `2.0.0`): changes that break existing usage, such as removing an option.

A pre-commit hook enforces this. Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

CI runs the same check, `scripts/check-version.sh`, on every pushed commit. To amend a commit without raising the version again, use `git commit --amend --no-verify`.

## Cutting a release

1. Tag the commit and push: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin main vX.Y.Z`
2. Publish with the script attached: `gh release create vX.Y.Z claude-export.sh --title "vX.Y.Z" --notes "..."`
