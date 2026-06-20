#! /usr/bin/env bash


SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
DAYLIGHT_SH="$SCRIPT_DIR/../daylight.sh"
[[ -f "$DAYLIGHT_SH" ]] || { printf 'Cannot find daylight.sh\n' >&2; exit 1; }

TOKEN=""
_positional=()
while (( $# > 0 )); do
    case $1 in
        --token) shift; TOKEN=$1 ;;
        -*)      printf 'Unknown flag: %s\n' "$1" >&2; exit 1 ;;
        *)       _positional+=("$1") ;;
    esac
    shift
done
set -- "${_positional[@]}"

command -v jq &>/dev/null || { printf 'jq is required but was not found\n' >&2; exit 1; }


#-------------------------------------------------------------------------------
#
# dl()
#
# @internal
# Shorthand for calling daylight.sh via case dispatch
#
dl()
{
    "$DAYLIGHT_SH" "$@"
}


#-------------------------------------------------------------------------------
#
# run-tests()
#
# Run all test scenarios and report results
#
run-tests()
{
    local tests=(
        test-branch-mode-token
        test-env-var-token
        test-no-token
        test-release-mode-token
        test-token-no-value
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
# test-branch-mode-token()
#
# Verify --token is accepted in branch mode (silently unused for public repos)
#
test-branch-mode-token()
{
    local tmpDir; tmpDir=$(mktemp -d) || return 1
    printf '  Note: --token is accepted but ignored in branch mode for public repos\n'
    dl download-daylight-batch --branch main --token "$TOKEN" "$tmpDir" || {
        printf '  FAIL: download failed\n'
        rm -rf "$tmpDir"; return 1
    }
    [[ -f "$tmpDir/daylight.sh" ]] || {
        printf '  FAIL: daylight.sh not downloaded\n'
        rm -rf "$tmpDir"; return 1
    }
    printf '  PASS\n'
    rm -rf "$tmpDir"
}


#-------------------------------------------------------------------------------
#
# test-env-var-token()
#
# Verify GITHUB_TOKEN env var works when --token is not given
#
test-env-var-token()
{
    [[ -n "$TOKEN" ]] || { printf '  SKIP: no token provided\n'; return 0; }
    local tmpDir; tmpDir=$(mktemp -d) || return 1
    GITHUB_TOKEN=$TOKEN "$DAYLIGHT_SH" download-daylight-batch --release --latest "$tmpDir" || {
        printf '  FAIL: download failed\n'
        rm -rf "$tmpDir"; return 1
    }
    [[ -f "$tmpDir/daylight.sh" ]] || {
        printf '  FAIL: daylight.sh not downloaded\n'
        rm -rf "$tmpDir"; return 1
    }
    printf '  PASS\n'
    rm -rf "$tmpDir"
}


#-------------------------------------------------------------------------------
#
# test-no-token()
#
# Verify behavior when no token is given — falls back to gh auth or GITHUB_TOKEN
#
test-no-token()
{
    local tmpDir; tmpDir=$(mktemp -d) || return 1
    dl download-daylight-batch --branch main "$tmpDir" || {
        printf '  FAIL: download failed\n'
        rm -rf "$tmpDir"; return 1
    }
    [[ -f "$tmpDir/daylight.sh" ]] || {
        printf '  FAIL: daylight.sh not downloaded\n'
        rm -rf "$tmpDir"; return 1
    }
    printf '  PASS\n'
    rm -rf "$tmpDir"
}


#-------------------------------------------------------------------------------
#
# test-release-mode-token()
#
# Verify --token is accepted in release mode and flows through to API calls
#
test-release-mode-token()
{
    [[ -n "$TOKEN" ]] || { printf '  SKIP: no token provided\n'; return 0; }
    local tmpDir; tmpDir=$(mktemp -d) || return 1
    dl download-daylight-batch --release --latest --token "$TOKEN" "$tmpDir" || {
        printf '  FAIL: download failed\n'
        rm -rf "$tmpDir"; return 1
    }
    [[ -f "$tmpDir/daylight.sh" ]] || {
        printf '  FAIL: daylight.sh not downloaded\n'
        rm -rf "$tmpDir"; return 1
    }
    printf '  PASS\n'
    rm -rf "$tmpDir"
}


#-------------------------------------------------------------------------------
#
# test-token-no-value()
#
# Verify --token without a value returns a clear error
#
test-token-no-value()
{
    local output
    output=$(dl download-daylight-batch --release --token 2>&1) && {
        printf '  FAIL: expected error but succeeded\n'
        return 1
    }
    printf '%s' "$output" | grep -q 'requires a value' || {
        printf '  FAIL: unexpected error message: %s\n' "$output"
        return 1
    }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# main()
#
# Dispatch to a specific test or run all
#
main ()
{
    if (( $# >= 1 )); then
        local cmd=$1
        shift
        case "$cmd" in
            run-tests)               run-tests;;
            test-branch-mode-token)  test-branch-mode-token;;
            test-env-var-token)      test-env-var-token;;
            test-no-token)           test-no-token;;
            test-release-mode-token) test-release-mode-token;;
            test-token-no-value)     test-token-no-value;;
            *)                       printf 'Unknown test: %s\n' "$cmd" >&2; exit 1;;
        esac
    else
        run-tests
    fi
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
