#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
DAYLIGHT_SH="$SCRIPT_DIR/../daylight.sh"
[[ -f "$DAYLIGHT_SH" ]] || { printf 'Cannot find daylight.sh\n' >&2; exit 1; }

source "$DAYLIGHT_SH" || { printf 'Failed to source daylight.sh\n' >&2; exit 1; }

#-------------------------------------------------------------------------------
#
# run-tests()
#
run-tests()
{
    local tests=(
        test-batch-no-args
        test-batch-too-many-args
        test-batch-piped-output
        test-wrapper-too-many-args
        test-wrapper-stdin-pipe
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
# test-batch-no-args()
#
test-batch-no-args()
{
    fail-check "no args" 'Usage' gen-completion-script-batch
}


#-------------------------------------------------------------------------------
#
# test-batch-too-many-args()
#
test-batch-too-many-args()
{
    fail-check "too many args" 'Usage' gen-completion-script-batch one two
}


#-------------------------------------------------------------------------------
#
# test-batch-piped-output()
#
test-batch-piped-output()
{
    local out
    out=$(printf 'cmd1\ncmd2\n' | gen-completion-script-batch myscript) || {
        printf '  FAIL: batch returned non-zero\n'
        return 1
    }
    [[ "$out" == *"complete -F _myscript myscript"* ]] || {
        printf '  FAIL: output missing complete line\n'
        return 1
    }
    [[ "$out" == *"cmd1"* && "$out" == *"cmd2"* ]] || {
        printf '  FAIL: output missing subcommands\n'
        return 1
    }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-wrapper-too-many-args()
#
test-wrapper-too-many-args()
{
    fail-check "too many args" 'Usage' gen-completion-script one two three
}


#-------------------------------------------------------------------------------
#
# test-wrapper-stdin-pipe()
#
test-wrapper-stdin-pipe()
{
    local out
    out=$(printf 'cmd1\ncmd2\n' | gen-completion-script myscript) || {
        printf '  FAIL: wrapper returned non-zero\n'
        return 1
    }
    [[ "$out" == *"complete -F _myscript myscript"* ]] || {
        printf '  FAIL: output missing complete line\n'
        return 1
    }
    [[ "$out" == *"cmd1"* && "$out" == *"cmd2"* ]] || {
        printf '  FAIL: output missing subcommands\n'
        return 1
    }
    printf '  PASS\n'
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
