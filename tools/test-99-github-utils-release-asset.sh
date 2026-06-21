#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
REPO_DIR=$(dirname "$SCRIPT_DIR")


#-------------------------------------------------------------------------------
#
# run-tests()
#
run-tests()
{
    local tests=(
        test-nightly-release-generate-step
        test-nightly-release-files-list
        test-nightly-release-sha256sum
        test-extract-script-exists
        test-legacy-workflow-removed
    )
    local total=0 passed=0 failed=0
    for t in "${tests[@]}"; do
        printf '=== %s ===\n' "$t"
        (( total++ ))
        if "$t"; then
            (( passed++ ))
        else
            (( failed++ ))
        fi
    done
    printf '\n%d total, %d passed, %d failed\n' "$total" "$passed" "$failed"
    return "$failed"
}


#-------------------------------------------------------------------------------
#
# test-nightly-release-generate-step()
#
# Verify nightly-release.yml has Generate github-utils.sh step
#
test-nightly-release-generate-step()
{
    local f="$REPO_DIR/.github/workflows/nightly-release.yml"
    [[ -f "$f" ]] || { printf '  FAIL: %s not found\n' "$f"; return 1; }
    grep -qF 'Generate github-utils.sh' "$f" || {
        printf '  FAIL: missing Generate github-utils.sh step\n'; return 1; }
    grep -qF 'extract-github-funcs.sh' "$f" || {
        printf '  FAIL: missing extract-github-funcs.sh command\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-nightly-release-files-list()
#
# Verify github-utils.sh is in the release files list
#
test-nightly-release-files-list()
{
    local f="$REPO_DIR/.github/workflows/nightly-release.yml"
    grep -qF 'github-utils.sh' "$f" || {
        printf '  FAIL: github-utils.sh not in release files\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-nightly-release-sha256sum()
#
# Verify github-utils.sh is included in the sha256sum command
#
test-nightly-release-sha256sum()
{
    local f="$REPO_DIR/.github/workflows/nightly-release.yml"
    grep -qF 'sha256sum' "$f" || {
        printf '  FAIL: missing sha256sum command\n'; return 1; }
    grep -qF 'github-utils.sh' < <(grep 'sha256sum' "$f") || {
        printf '  FAIL: github-utils.sh not in sha256sum\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-extract-script-exists()
#
# Verify extract-github-funcs.sh is present in repo root
#
test-extract-script-exists()
{
    [[ -f "$REPO_DIR/extract-github-funcs.sh" ]] || {
        printf '  FAIL: extract-github-funcs.sh not found\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-legacy-workflow-removed()
#
# Verify nightly-release-legacy.yml has been deleted
#
test-legacy-workflow-removed()
{
    [[ -f "$REPO_DIR/.github/workflows/nightly-release-legacy.yml" ]] && {
        printf '  FAIL: legacy workflow should have been removed\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# main()
#
main()
{
    if (( $# >= 1 )); then
        local cmd=$1; shift
        case "$cmd" in
            run-tests)                              run-tests;;
            test-nightly-release-generate-step)      test-nightly-release-generate-step;;
            test-nightly-release-files-list)          test-nightly-release-files-list;;
            test-nightly-release-sha256sum)           test-nightly-release-sha256sum;;
            test-extract-script-exists)               test-extract-script-exists;;
            test-legacy-workflow-removed)             test-legacy-workflow-removed;;
            *)                                        printf 'Unknown test: %s\n' "$cmd" >&2; exit 1;;
        esac
    else
        run-tests
    fi
}

if ! (return 0 2>/dev/null); then
    main "$@"
fi
