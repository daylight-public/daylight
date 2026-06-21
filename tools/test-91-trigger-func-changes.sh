#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
DAYLIGHT_SH="$SCRIPT_DIR/../daylight.sh"
[[ -f "$DAYLIGHT_SH" ]] || { printf 'Cannot find daylight.sh\n' >&2; exit 1; }

source "$DAYLIGHT_SH" || { printf 'Failed to source daylight.sh\n' >&2; exit 1; }

#-------------------------------------------------------------------------------
#
# run-tests()
#
# Run all test scenarios and report results
#
run-tests()
{
    local tests=(
        test-batch-no-args
        test-batch-missing-workflow
        test-batch-missing-positional
        test-batch-invalid-workflow
        test-batch-token-and-label
        test-wrapper-defaults-workflow
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
# fail-check()
#
# @internal
# Run a command and verify it fails with the expected substring in stderr
# Usage: fail-check desc expected_substring cmd args...
#
fail-check()
{
    local desc=$1 expected=$2
    shift 2
    local stderr
    stderr=$("$@" 2>&1 1>/dev/null) && {
        printf '  FAIL (%s): expected failure but succeeded\n' "$desc"
        return 1
    }
    if [[ $stderr != *"$expected"* ]]; then
        printf '  FAIL (%s): expected stderr to contain "%s", got:\n  %s\n' "$desc" "$expected" "$stderr"
        return 1
    fi
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# pass-check()
#
# @internal
# Run a command and verify it succeeds
# Usage: pass-check desc cmd args...
#
pass-check()
{
    local desc=$1
    shift
    local stderr
    stderr=$("$@" 2>&1) || {
        printf '  FAIL (%s): expected success but failed with:\n  %s\n' "$desc" "$stderr"
        return 1
    }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-batch-no-args()
#
# Verify batch fails with no arguments
#
test-batch-no-args()
{
    fail-check "no args" 'Usage' trigger-nightly-release-batch
}


#-------------------------------------------------------------------------------
#
# test-batch-missing-workflow()
#
# Verify batch fails without --workflow
#
test-batch-missing-workflow()
{
    fail-check "no --workflow" 'Usage' trigger-nightly-release-batch --token x
}


#-------------------------------------------------------------------------------
#
# test-batch-missing-positional()
#
# Verify batch fails with --workflow but no positional
#
test-batch-missing-positional()
{
    fail-check "missing positional" 'Usage' trigger-nightly-release-batch --workflow nightly
}


#-------------------------------------------------------------------------------
#
# test-batch-invalid-workflow()
#
# Verify batch fails for a workflow that doesn't exist
#
test-batch-invalid-workflow()
{
    fail-check "invalid workflow" 'not found' \
        trigger-nightly-release-batch --workflow does-not-exist-file.yml --token x owner/repo
}


#-------------------------------------------------------------------------------
#
# test-batch-token-and-label()
#
# Verify batch accepts --token and --label and proceeds past arg parsing
# (will fail on workflow not found or GITHUB_TOKEN, but not on usage)
#
test-batch-token-and-label()
{
    fail-check "token+label" 'error: workflow' \
        trigger-nightly-release-batch --workflow nightly --token x --label v0 owner/repo
}


#-------------------------------------------------------------------------------
#
# test-wrapper-defaults-workflow()
#
# Verify wrapper defaults --workflow to nightly-release
#
test-wrapper-defaults-workflow()
{
    fail-check "default workflow" 'not found' \
        trigger-nightly-release --token x owner/repo
}


#-------------------------------------------------------------------------------
#
# main()
#
case ${1:-} in
    *)  run-tests;;
esac


if ! (return 0 2>/dev/null); then
    main "$@"
fi
