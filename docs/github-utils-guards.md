# github-utils.sh Guard System

`github-utils.sh` is auto-generated from `daylight.sh` by
`extract-github-funcs.sh`. Manual edits to it will be overwritten.

## How it stays in sync

Three layers prevent out-of-sync or human-edited copies from reaching `main`.

### 1. Auto-generation on push

**File:** `.github/workflows/generate-github-utils.yml`

Whenever `daylight.sh` is pushed to `main`, this workflow runs
`./extract-github-funcs.sh > github-utils.sh` and auto-commits the result
via [`stefanzweifel/git-auto-commit-action`][git-auto-commit]. The
workflow only triggers on `daylight.sh` changes (`paths:` filter), so the
auto-commit doesn't re-trigger itself. Humans should never need to touch
this file.

### 2. PR validation

**File:** `.github/workflows/validate-github-utils.yml`

On any PR that touches `github-utils.sh` or `daylight.sh`, this workflow
regenerates `github-utils.sh` from `daylight.sh` and diffs it against the
committed version using plain `diff`. If they differ, the check fails,
blocking the merge. This enforces that `github-utils.sh` is always the
exact output of `extract-github-funcs.sh`.

### 3. Code ownership

**File:** `.github/CODEOWNERS`

[CODEOWNERS][codeowners-docs] is a GitHub feature that lets you assign
review responsibilities to specific files or patterns. The entry:

```
github-utils.sh    @github-actions
```

means any PR that modifies `github-utils.sh` automatically requests
review from the `@github-actions` bot account. With branch protection
configured to **require code owner approval**, a human-edited PR cannot
merge without the bot's sign-off — which it will never give, since the
bot only auto-commits via the push workflow above.

## Recovery

If `github-utils.sh` is ever out of sync, run locally:

```bash
./extract-github-funcs.sh > github-utils.sh
```

Or simply push a change to `daylight.sh` — the push-triggered workflow
will regenerate it.

[git-auto-commit]: https://github.com/stefanzweifel/git-auto-commit-action
[codeowners-docs]: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
