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

### AGENTS.md changes

AGENTS.md is meta — it holds conventions and reminders. Changes to it don't need issues, labels, or approval. Use the `update-agents-md` persistent branch:

- Check it out from `main`, push commits to it over time
- Open a PR against `main` when there's a batch ready (no issue link needed)
- Self-merge, then rebase `update-agents-md` onto fresh `main` 
