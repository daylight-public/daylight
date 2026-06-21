### daylight.sh

daylight.sh is a monolithic bash 4+ script that contains lots of functions for setting up a Linux host (currently Debian/Ubuntu) to support daylight functionality. daylight.sh was the first script created as part of daylight. It was created to be fast and easy to write, read, extend, and maintain. Obviouslt it's also tech debt, but sometimes tech debt can be a goot place to start.

daylight.sh functions are alphabetized, except for a main function at the end.

#### comments
daylight.sh functions should begin with comments that look like this.

```
#-------------------------------------------------------------------------------
#
# download-shr-tarball()
#
# Download the tarball for the latest GitHub Actions Self-Hosted Runner release
#
download-shr-tarball ()
{
```

`download-shr-tarball` is the function name.
"Download" etc is a one or two line description. In rare cases a description will be longer because the function will warrant a longer description. Do not shorten or edit existing descriptions.

Functions that appear in the `main()` case statement should NOT use the `@internal` tag in their comment block — it signifies the function is a helper that lives outside the dispatch table.

```
#-------------------------------------------------------------------------------
#
# dl()
#
# @internal
# Shorthand description of the function goes here on the next line
#
```

The `@internal` tag sits alone on its own line between the function name and the description. This makes it trivially grepable (`grep -B3 '^# @internal$'`) while keeping the description readable and adjacent.

#### case statement

daylight.sh has a main case statement which dispactches command line arguments to their appropriate function. This lets daylight.sh be called in oneliners without requiring it be sourced and then used interactively.
When new functions are added to daylight.sh they should be added to the main case and properly alphabetized.

#### Reminder

Audit internal functions (`github-curl`, `github-release-get-data`, `create-temp-folder`, etc.) that are not in the case statement but could benefit from being callable via `daylight.sh <func>`. Add them as needed.

### tools/

New helper scripts should be placed in `./tools/` by default. This keeps the
repo root clean and makes the boundary between the main script (`daylight.sh`)
and auxiliary tooling explicit.

Test scripts live in `tools/` and follow the same conventions as other tools
(comment blocks, case dispatch, `@internal` for helpers). They are manual
verification tools, not CI. Tests cover shared infrastructure (`github-curl-parse-args`,
`--token` flag handling, etc.) and can be referenced by dylt tests.

### pushing code changes (issue-driven workflow)

1. Propose an issue title, a short branch name (without issue number), and an issue body (can include markdown)
2. User confirms or edits each
3. Create the issue via `gh issue create`
4. Prepend the issue number to the branch name (e.g. `42-fix-thing`)
5. Commit, push, create PR with `Closes #N` in the body
6. Do the work; user merges the PR when ready

Exception: Meta changes to AGENTS.md itself use the `update-agents-md` persistent branch with no issue (see below).

### download-daylight flags

`download-daylight` uses a custom flag parser (not `github-parse-args`) for branch/release selection.

| Flag | Value | Behavior |
|---|---|---|
| (none) | — | Branch mode, defaults to `main` |
| `--branch` | (no value) | Branch mode, defaults to `main` |
| `--branch <name>` | branch name | Branch mode, specific branch |
| `--release` | (no value) | Release mode, latest release |
| `--release <tag>` | tag name | Release mode, specific tag |
| `--release --latest` | — | Same as `--release` with no value |
| `--latest` alone | — | Error: requires `--release` |
| `--token <value>` | token | GitHub API token for release mode |
| `--branch` + `--release` | — | Error: incompatible |

Rules:
- Flags are parsed in order. The optional value after `--branch` or `--release` is consumed only if it doesn't start with `--`.
- `--latest` must follow `--release` (either immediately or as a later flag).
- The destination folder is the first positional argument after all flags.
- Exactly one of branch mode or release mode must be active. 
### reminders

- Audit github-utils.sh infrastructure (extract-github-funcs.sh, workflows, nightly-release-legacy, docs) — evaluate whether still needed given the move to GHA workflows
- Add `--token` and `--gen-bash-completions` flags to download-daylight
- Complete the gen-completion-script → gen-completion-script-batch rename
- Explore externalizing label creation into a separate function
- Create custom git function for setting URL
- Use a GitHub App for auth instead of PATs
- Sort out all the github functions starting with flags/args

### AGENTS.md changes

AGENTS.md is meta — it holds conventions and reminders. Changes to it don't
need issues, labels, or approval. Use the `update-agents-md` persistent branch:

- Check it out from `main`, push commits to it over time
- Open a PR against `main` when there's a batch ready (no issue link needed)
- Self-merge, then rebase `update-agents-md` onto fresh `main`
