#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
DAYLIGHT_SH="$SCRIPT_DIR/../daylight.sh"
[[ -f "$DAYLIGHT_SH" ]] || { printf 'Cannot find daylight.sh\n' >&2; exit 1; }
source "$DAYLIGHT_SH" || { printf 'Failed to source daylight.sh\n' >&2; exit 1; }


run-tests()
{
    local tests=(
        test_latest_default
        test_with_version
        test_repo_with_digits
        test_rejects_extra_path
        test_rejects_no_slash
        test_rejects_no_args
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


test_latest_default()
{
    local result
    result=$(ghr-url-path 'edeneast/nightfox.nvim') || {
        printf '  FAIL (latest): function returned non-zero\n'
        return 1
    }
    [[ "$result" == "/repos/edeneast/nightfox.nvim/releases/latest" ]] \
        && { printf '  PASS\n'; return 0; } \
        || { printf '  FAIL (latest): got "%s"\n' "$result"; return 1; }
}


test_with_version()
{
    local result
    result=$(ghr-url-path --version v2.2.0 'edeneast/nightfox.nvim') || {
        printf '  FAIL (version): function returned non-zero\n'
        return 1
    }
    [[ "$result" == "/repos/edeneast/nightfox.nvim/releases/tags/v2.2.0" ]] \
        && { printf '  PASS\n'; return 0; } \
        || { printf '  FAIL (version): got "%s"\n' "$result"; return 1; }
}


test_repo_with_digits()
{
    local result
    result=$(ghr-url-path 'org/repo123') || {
        printf '  FAIL (digits): function returned non-zero\n'
        return 1
    }
    [[ "$result" == "/repos/org/repo123/releases/latest" ]] \
        && { printf '  PASS\n'; return 0; } \
        || { printf '  FAIL (digits): got "%s"\n' "$result"; return 1; }
}


test_rejects_extra_path()
{
    local stderr
    stderr=$(ghr-url-path 'org/repo/extra' 2>&1 1>/dev/null) && {
        printf '  FAIL (extra path): expected failure but succeeded\n'
        return 1
    }
    printf '  PASS\n'
}


test_rejects_no_slash()
{
    local stderr
    stderr=$(ghr-url-path 'invalid' 2>&1 1>/dev/null) && {
        printf '  FAIL (no slash): expected failure but succeeded\n'
        return 1
    }
    printf '  PASS\n'
}


test_rejects_no_args()
{
    local stderr
    stderr=$(ghr-url-path 2>&1 1>/dev/null) && {
        printf '  FAIL (no args): expected failure but succeeded\n'
        return 1
    }
    printf '  PASS\n'
}


main()
{
    case "${1:-}" in
        run-tests|"")   run-tests "$@";;
        test_*)         "$@";;
        *)              printf 'Unknown test\n' >&2; exit 1;;
    esac
}

if ! (return 0 2>/dev/null); then main "$@"; fi
