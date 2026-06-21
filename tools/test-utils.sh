#-------------------------------------------------------------------------------
#
# test-utils.sh
#
# Shared helper functions for tools/test-*.sh
#
# Source from a test script:
#   source "$(dirname "$(readlink -f "$BASH_SOURCE")")/test-utils.sh"
#


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
