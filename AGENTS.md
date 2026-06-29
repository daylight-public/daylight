### Paramterizing functions: positional args vs flags vs envvars

Sometimes, even when it's easy to know what a function should do, it's hard to figure out how to tell the function to do it. Bash has a rich set of behavior parameterization, all of which are perfectly idiomatic. It can be hard to know which to choose. Below are some rough guidelines.

#### Positional args
Positional args are typically the data that, without it, a function wouldn't make much sense. In an add() function that adds x+y, x and y make sense as positional args, possibly variadic.

#### Flags
Flags are good for data a function might not need to do its job, but they might greatly affect _how_() it does its job. In a div() function, that divides x/y, x and y make sense as positional args but --precision makes sense as a flag that says 'how many decimal points'

#### Environment Variables / envvars
Environment variables are typically non-functional and crosscutting. They often aren't targetted to one specific function, except perhaps an initialization function, and it can be unclear which functions may or may not make use of any given environment variable. And that's ok: that's why they're in the Environment, available to all. In a collection of math functions, like add() sub() mul() div(), SEPARATOR makes sense as an envvar, to tell any interested function whether 999+1 = 1,000, or 1.000, or 1000, or other.

### daylight.sh

daylight.sh is a monolithic bash 4+ script that contains lots of functions for setting up a Linux host (currently Debian/Ubuntu) to support daylight functionality. daylight.sh was the first script created as part of daylight. It was created to be fast and easy to write, read, extend, and maintain. Obviouslt it's also tech debt, but sometimes tech debt can be a goot place to start.

daylight.sh functions are alphabetized, except for a main function at the end.

#### comments
daylight.sh functions should begin with comments that look like this.

#### what if you don't know?
If you don't know ask.
But ... if you're going to make a mistake, the safest way to make a mistake is with flags. Too many positional args makes a function unusable. Too many envvars make it unfeasible to customize, esp in a comfortable one-liner. Too many flags might give code a reputation for having, well, too many flags. But theyre otherwise pretty harmless. 99.999% of curls users couldn't name you 1/10th of the flags curl supports, and they're doing fine. Sometimes a function or tool invocation with a dozen flags is just a nice recipe.

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

Test scripts must be executable (`chmod +x`). Name them
`tools/test-<branchname>.sh` where the branch name includes the issue number
(e.g. `tools/test-91-trigger-func-changes.sh`).

#### test scripts

tools/test-*.sh are manual verification tools (not CI) created alongside
code changes on the same branch. Follow this structure:

```
#! /usr/bin/env bash
SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1
```

- `run-tests()`: declare a `tests` array listing every test function,
  iterate calling each, track total/passed/failed, return `$failed`
- Each test function returns 0 on pass, 1 on fail; prints `  PASS`
  or `  FAIL (...)` with explicit assertions
- `main()` with case dispatch for each test (allows
  `bash test-foo.sh test-name`); `*)` prints "Unknown test" and exits 1
- Guard: `if ! (return 0 2>/dev/null); then main "$@"; fi`

Flag-parsing tests use `fail-check` with a non-existent destination folder
to verify flag routing without network access. For functions that call
external services, mock `curl` or the downstream function
(e.g. `curl() { CURL_ARGS=("$@"); }`) to capture args without real HTTP.

The helper functions `fail-check()` and `pass-check()` live in
`tools/test-utils.sh` and are shared across all test scripts.
Existing test files under `tools/` are reference implementations.

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
- Explore externalizing label creation into a separate function
- Create custom git function for setting URL
- Use a GitHub App for auth instead of PATs
- Sort out all the github functions starting with flags/args
- Nightly release tag format is now consistent with dylt (date dashes, dedup logic). If dylt later enhances with semver support in tags, daylight should adopt the same `v<VERSION>-nightly-` prefix.

### pre-push hook: auto-install to /opt/bin

`.git/hooks/pre-push` copies `daylight.sh` to `/opt/bin/daylight.sh` on every
`git push`. This tightens the dev loop — after pushing, source the installed copy
and new functions are immediately available.

- Runs on every push (pre-push hook)
- Skips copy if checksums match (no-op)
- Prints error to stderr on failure, but never blocks the push (exit 0)
- Hook runs in a subprocess — cannot source into parent shell; prints reminder
- If you add a new function or modify daylight.sh, push, then `source /opt/bin/daylight.sh`

### AGENTS.md changes

AGENTS.md is meta — it holds conventions and reminders. Changes to it don't
need issues, labels, or approval. Use the `update-agents-md` persistent branch:

- Check it out from `main`, push commits to it over time
- Open a PR against `main` when there's a batch ready (no issue link needed)
- Self-merge, then rebase `update-agents-md` onto fresh `main`
