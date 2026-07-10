#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1


# In    cmdline     --token abc --per-page 50 /repos/org/repo
# Out   flagMap     { token: abc, per-page: 50}
#       posargs     [ /repos/org/repo ]
test-parse-basic()
{
    local -A flagMap=()
    local -a posargs=()
    gh-parse-args flagMap posargs --token abc --per-page 50 /repos/org/repo

    [[ "${flagMap[token]}" == "abc" ]] || { printf '  FAIL: token\n'; return 1; }
    [[ "${flagMap[per-page]}" == "50" ]] || { printf '  FAIL: per-page\n'; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: url\n'; return 1; }
    printf '  PASS\n'
}


# In    cmdline     --token abc /repos/org/repo --output foo.json
# Out   flagMap     { token: abc, output: foo.json}
#       posargs     [ /repos/org/repo ]
test-parse-interleaved()
{
    local -A flagMap=()
    local -a posargs=()
    gh-parse-args flagMap posargs --token abc /repos/org/repo --output foo.json

    [[ "${flagMap[token]}" == "abc" ]] || { printf '  FAIL: token\n'; return 1; }
    [[ "${flagMap[output]}" == "foo.json" ]] || { printf '  FAIL: output\n'; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: url\n'; return 1; }
    printf '  PASS\n'
}


# In    cmdline     --remote-name /repos/org/repo
# Out   flagMap     { remote-name: 1}
#       posargs     [ /repos/org/repo ]
test-parse-bool-flag()
{
    local -A flagMap=()
    local -a posargs=()
    gh-parse-args flagMap posargs --remote-name /repos/org/repo

    [[ -v flagMap[remote-name] ]] || { printf '  FAIL: remote-name not set\n'; return 1; }
    [[ "${flagMap[remote-name]}" == "1" ]] || { printf '  FAIL: remote-name value\n'; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: url\n'; return 1; }
    printf '  PASS\n'
}


# In    cmdline     --token abc -- /repos/org/repo --output foo
# Out   flagMap     { token: abc}
#       posargs     [ /repos/org/repo, --output, foo ]
test-parse-terminal()
{
    local -A flagMap=()
    local -a posargs=()
    gh-parse-args flagMap posargs --token abc -- /repos/org/repo --output foo

    [[ "${flagMap[token]}" == "abc" ]] || { printf '  FAIL: token\n'; return 1; }
    [[ "${#posargs[@]}" -eq 3 ]] || { printf '  FAIL: posargs count (%d)\n' "${#posargs[@]}"; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: posarg 0\n'; return 1; }
    [[ "${posargs[1]}" == "--output" ]] || { printf '  FAIL: posarg 1\n'; return 1; }
    [[ "${posargs[2]}" == "foo" ]] || { printf '  FAIL: posarg 2\n'; return 1; }
    printf '  PASS\n'
}


# In    flagMap     { token: abc }
# Out   curlFlags   [ --header "Authorization: Bearer abc" ]
test-unparse-basic()
{
    local -A flagMap=()

    flagMap[token]=abc

    local -a curlFlags=()

    gh-unparse-curl-args flagMap curlFlags

    local foundAuth=false
    for arg in "${curlFlags[@]}"; do
        [[ "$arg" == *"Authorization"* ]] && foundAuth=true
    done
    $foundAuth || { printf '  FAIL: no auth header\n'; return 1; }

    printf '  PASS\n'
}


test-unparse-data()
{
    local -A flagMap=()

    flagMap[data]='{"title":"test"}'

    local -a curlFlags=()

    gh-unparse-curl-args flagMap curlFlags

    local foundData=false
    local i
    for ((i=0; i<${#curlFlags[@]}; i++)); do
        if [[ "${curlFlags[i]}" == "--data" ]] && [[ "${curlFlags[i+1]}" == '{"title":"test"}' ]]; then
            foundData=true
        fi
    done
    $foundData || { printf '  FAIL: data flag not found\n'; return 1; }

    printf '  PASS\n'
}


test-api-empty-flagMap()
{
    # Empty flagMap, public endpoint — verifies gh-api_ works with
    # no flags at all.
    local -A flagMap=()

    local capturedUrl
    curl() { capturedUrl="$*"; return 0; }

    gh-api_ flagMap "/repos/org/repo" 2>/dev/null

    [[ "$capturedUrl" == *"api.github.com/repos/org/repo" ]] \
        || { printf '  FAIL: empty flagMap URL mismatch: %s\n' "$capturedUrl"; return 1; }

    unset -f curl
    printf '  PASS\n'
}


test-api-per-page()
{
    local -A flagMap=()
    flagMap[per-page]=50

    local capturedUrl
    curl() { capturedUrl="$*"; return 0; }

    gh-api_ flagMap "/repos/org/repo" 2>/dev/null

    [[ "$capturedUrl" == *"per_page=50" ]] \
        || { printf '  FAIL: per_page not in URL: %s\n' "$capturedUrl"; return 1; }

    unset -f curl
    printf '  PASS\n'
}


test-parse-unknown-flag()
{
    local -A flagMap=()
    local -a posargs=()
    gh-parse-args flagMap posargs --nonexistent /repos/org/repo && {
        printf '  FAIL: expected error for unknown flag\n'
        return 1
    }
    printf '  PASS\n'
}


run-tests()
{
    local tests=(
        test-parse-basic
        test-parse-interleaved
        test-parse-bool-flag
        test-parse-terminal
        test-parse-unknown-flag
        test-unparse-basic
        test-unparse-data
        test-api-empty-flagmap
        test-api-per-page
    )
    local total=${#tests[@]}
    local passed=0
    local failed=0
    for t in "${tests[@]}"; do
        printf 'Test: %s\n' "$t"
        if "$t"; then
            (( passed++ ))
        else
            (( failed++ ))
        fi
    done
    printf '\n%d passed, %d failed, %d total\n' "$passed" "$failed" "$total"
    return "$failed"
}


main()
{
    case ${1:-all} in
        all|run-tests|"")  run-tests ;;
        test-parse-basic|\
        test-parse-interleaved|\
        test-parse-bool-flag|\
        test-parse-terminal|\
        test-parse-unknown-flag|\
        test-unparse-basic|\
        test-unparse-data|\
        test-api-empty-flagmap|\
        test-api-per-page)  "$@" ;;
        *)                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
