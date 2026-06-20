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

#### case statement

daylight.sh has a main case statement which dispactches command line arguments to their appropriate function. This lets daylight.sh be called in oneliners without requiring it be sourced and then used interactively.
When new functions are added to daylight.sh they should be added to the main case and properly alphabetized.

### pushing code changes

All code changes will be done on new branches, with short names -- 2 or 3 words or terms separated by hyphens. Ask me to approve branch names. After committing and pushing a branch, create a PR for the change, where the body of the PR contains information similar or identical to the plan markdown. Create an issue and link it to the PR. Ask what the issue should be labelled - Bug, Task, or Feature.

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
| `--branch` + `--release` | — | Error: incompatible |

Rules:
- Flags are parsed in order. The optional value after `--branch` or `--release` is consumed only if it doesn't start with `--`.
- `--latest` must follow `--release` (either immediately or as a later flag).
- The destination folder is the first positional argument after all flags.
- Exactly one of branch mode or release mode must be active. 
