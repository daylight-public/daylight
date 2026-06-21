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
        test-token-flag
        test-token-and-accept
        test-workflow-flag
        test-label-flag
        test-token-with-positional
        test-double-dash
        test-token-no-value
        test-no-flags-just-positional
        test-workflow-and-label-with-positional
        test-accept-alone
        test-all-flags
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
# parse-check()
#
# @internal
# Call github-curl-parse-args and verify the results
# Usage: parse-check desc expected_nargs expected_key expected_val [extra_flags...] -- [positional...]
#
parse-check()
{
    local desc=$1 expected_nargs=$2 expected_key=$3 expected_val=$4
    shift 4
    local -a extra=()
    local -a positional=()
    local sep=0
    for arg in "$@"; do
        if (( sep )); then
            positional+=("$arg")
        elif [[ $arg == '--' ]]; then
            sep=1
        else
            extra+=("$arg")
        fi
    done

    local -A arg_A=()
    local nargs_A=0
    set -- "${extra[@]}" "${positional[@]}"
    github-curl-parse-args arg_A nargs_A "$@" || {
        printf '  FAIL (%s): github-curl-parse-args returned non-zero\n' "$desc"
        return 1
    }

    if [[ ${arg_A[$expected_key]} != "$expected_val" ]]; then
        printf '  FAIL (%s): expected %s=%s, got %s\n' "$desc" "$expected_key" "$expected_val" "${arg_A[$expected_key]}"
        return 1
    fi

    if (( nargs_A != expected_nargs )); then
        printf '  FAIL (%s): expected nargs=%d, got %d\n' "$desc" "$expected_nargs" "$nargs_A"
        return 1
    fi

    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# parse-fail-check()
#
# @internal
# Call github-curl-parse-args and verify it fails
# Usage: parse-fail-check desc flags...
#
parse-fail-check()
{
    local desc=$1
    shift
    local -A arg_A=()
    local nargs_A=0
    github-curl-parse-args arg_A nargs_A "$@" && {
        printf '  FAIL (%s): expected failure but succeeded\n' "$desc"
        return 1
    }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-token-flag()
#
# Verify --token sets argmap[token]
#
test-token-flag()
{
    parse-check "--token secret" 2 token secret --token secret
}


#-------------------------------------------------------------------------------
#
# test-token-and-accept()
#
# Verify --token and --accept together
#
test-token-and-accept()
{
    parse-check "--token t --accept a" 4 token t --token t --accept a
}


#-------------------------------------------------------------------------------
#
# test-workflow-flag()
#
# Verify --workflow sets argmap[workflow]
#
test-workflow-flag()
{
    parse-check "--workflow nightly" 2 workflow nightly --workflow nightly
}


#-------------------------------------------------------------------------------
#
# test-label-flag()
#
# Verify --label sets argmap[label]
#
test-label-flag()
{
    parse-check "--label test-123" 2 label test-123 --label test-123
}


#-------------------------------------------------------------------------------
#
# test-token-with-positional()
#
# Verify positional arg after flags is preserved
#
test-token-with-positional()
{
    local -a args=(--token secret positional_arg)
    local -A arg_A=()
    local nargs_A=0
    github-curl-parse-args arg_A nargs_A "${args[@]}"
    [[ ${arg_A[token]} == "secret" ]] || { printf '  FAIL: expected token=secret, got %s\n' "${arg_A[token]}"; return 1; }
    (( nargs_A == 2 )) || { printf '  FAIL: expected nargs=2, got %d\n' "$nargs_A"; return 1; }
    [[ ${args[@]:nargs_A} == "positional_arg" ]] || { printf '  FAIL: expected remaining args: positional_arg, got: %s\n' "${args[@]:nargs_A}"; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-double-dash()
#
# Verify -- stops flag parsing
#
test-double-dash()
{
    local -a args=(--token secret -- --extra)
    local -A arg_A=()
    local nargs_A=0
    github-curl-parse-args arg_A nargs_A "${args[@]}"
    [[ ${arg_A[token]} == "secret" ]] || { printf '  FAIL: expected token=secret, got %s\n' "${arg_A[token]}"; return 1; }
    (( nargs_A == 3 )) || { printf '  FAIL: expected nargs=3, got %d\n' "$nargs_A"; return 1; }
    [[ ${args[@]:nargs_A} == "--extra" ]] || { printf '  FAIL: expected remaining args: --extra, got: %s\n' "${args[@]:nargs_A}"; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-token-no-value()
#
# Verify --token without a value returns error
#
test-token-no-value()
{
    parse-fail-check "--token without value" --token
}


#-------------------------------------------------------------------------------
#
# test-no-flags-just-positional()
#
# Verify no flags = nargs=0, positional preserved
#
test-no-flags-just-positional()
{
    local -A arg_A=()
    local nargs_A=0
    set -- just-a-positional
    github-curl-parse-args arg_A nargs_A "$@"
    if (( nargs_A != 0 )); then
        printf '  FAIL: expected nargs=0, got %d\n' "$nargs_A"
        return 1
    fi
    if [[ $1 != "just-a-positional" ]]; then
        printf '  FAIL: expected $1=just-a-positional, got %s\n' "$1"
        return 1
    fi
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-workflow-and-label-with-positional()
#
# Verify --workflow and --label together with a positional arg
#
test-workflow-and-label-with-positional()
{
    local -a args=(--workflow nightly --label v1.0 dylt-dev/dylt)
    local -A arg_A=()
    local nargs_A=0
    github-curl-parse-args arg_A nargs_A "${args[@]}"
    [[ ${arg_A[workflow]} == "nightly" ]] || { printf '  FAIL: expected workflow=nightly, got %s\n' "${arg_A[workflow]}"; return 1; }
    [[ ${arg_A[label]} == "v1.0" ]] || { printf '  FAIL: expected label=v1.0, got %s\n' "${arg_A[label]}"; return 1; }
    (( nargs_A == 4 )) || { printf '  FAIL: expected nargs=4, got %d\n' "$nargs_A"; return 1; }
    [[ ${args[@]:nargs_A} == "dylt-dev/dylt" ]] || { printf '  FAIL: expected remaining: dylt-dev/dylt, got: %s\n' "${args[@]:nargs_A}"; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-accept-alone()
#
# Verify --accept without a value returns error
#
test-accept-alone()
{
    parse-fail-check "--accept without value" --accept
}


#-------------------------------------------------------------------------------
#
# test-all-flags()
#
# Verify all flags parsed correctly together
#
test-all-flags()
{
    local -a args=(--token tok --accept app --output out --per-page 50 --platform linux --version v1 --label l --workflow w pos)
    local -A arg_A=()
    local nargs_A=0
    github-curl-parse-args arg_A nargs_A "${args[@]}"
    (( nargs_A == 16 )) || { printf '  FAIL: expected nargs=16, got %d\n' "$nargs_A"; return 1; }
    [[ ${arg_A[token]} == "tok" ]]    || { printf '  FAIL: expected token=tok\n'; return 1; }
    [[ ${arg_A[accept]} == "app" ]]   || { printf '  FAIL: expected accept=app\n'; return 1; }
    [[ ${arg_A[output]} == "out" ]]   || { printf '  FAIL: expected output=out\n'; return 1; }
    [[ ${arg_A[per-page]} == "50" ]]  || { printf '  FAIL: expected per-page=50\n'; return 1; }
    [[ ${arg_A[platform]} == "linux" ]] || { printf '  FAIL: expected platform=linux\n'; return 1; }
    [[ ${arg_A[version]} == "v1" ]]   || { printf '  FAIL: expected version=v1\n'; return 1; }
    [[ ${arg_A[label]} == "l" ]]      || { printf '  FAIL: expected label=l\n'; return 1; }
    [[ ${arg_A[workflow]} == "w" ]]   || { printf '  FAIL: expected workflow=w\n'; return 1; }
    [[ ${args[@]:nargs_A} == "pos" ]] || { printf '  FAIL: expected remaining: pos, got: %s\n' "${args[@]:nargs_A}"; return 1; }
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
            run-tests)                              run-tests;;
            test-token-flag)                        test-token-flag;;
            test-token-and-accept)                  test-token-and-accept;;
            test-workflow-flag)                     test-workflow-flag;;
            test-label-flag)                        test-label-flag;;
            test-token-with-positional)             test-token-with-positional;;
            test-double-dash)                       test-double-dash;;
            test-token-no-value)                    test-token-no-value;;
            test-no-flags-just-positional)          test-no-flags-just-positional;;
            test-workflow-and-label-with-positional) test-workflow-and-label-with-positional;;
            test-accept-alone)                      test-accept-alone;;
            test-all-flags)                         test-all-flags;;
            *)                                      printf 'Unknown test: %s\n' "$cmd" >&2; exit 1;;
        esac
    else
        run-tests
    fi
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
