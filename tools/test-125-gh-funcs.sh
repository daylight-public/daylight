#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1


test-parse-basic()
{
    local -A flagmap=()
    local -a posargs=()
    gh-parse-args flagmap posargs --token abc --per-page 50 /repos/org/repo

    [[ "${flagmap[token]}" == "abc" ]] || { printf '  FAIL: token\n'; return 1; }
    [[ "${flagmap[per-page]}" == "50" ]] || { printf '  FAIL: per-page\n'; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: url\n'; return 1; }
    printf '  PASS\n'
}


test-parse-interleaved()
{
    local -A flagmap=()
    local -a posargs=()
    gh-parse-args flagmap posargs --token abc /repos/org/repo --output foo.json

    [[ "${flagmap[token]}" == "abc" ]] || { printf '  FAIL: token\n'; return 1; }
    [[ "${flagmap[output]}" == "foo.json" ]] || { printf '  FAIL: output\n'; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: url\n'; return 1; }
    printf '  PASS\n'
}


test-parse-bool-flag()
{
    local -A flagmap=()
    local -a posargs=()
    gh-parse-args flagmap posargs --remote-name /repos/org/repo

    [[ -v flagmap[remote-name] ]] || { printf '  FAIL: remote-name not set\n'; return 1; }
    [[ "${flagmap[remote-name]}" == "1" ]] || { printf '  FAIL: remote-name value\n'; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: url\n'; return 1; }
    printf '  PASS\n'
}


test-parse-terminal()
{
    local -A flagmap=()
    local -a posargs=()
    gh-parse-args flagmap posargs --token abc -- /repos/org/repo --output foo

    [[ "${flagmap[token]}" == "abc" ]] || { printf '  FAIL: token\n'; return 1; }
    [[ "${#posargs[@]}" -eq 3 ]] || { printf '  FAIL: posargs count (%d)\n' "${#posargs[@]}"; return 1; }
    [[ "${posargs[0]}" == "/repos/org/repo" ]] || { printf '  FAIL: posarg 0\n'; return 1; }
    [[ "${posargs[1]}" == "--output" ]] || { printf '  FAIL: posarg 1\n'; return 1; }
    [[ "${posargs[2]}" == "foo" ]] || { printf '  FAIL: posarg 2\n'; return 1; }
    printf '  PASS\n'
}


test-unparse-basic()
{
    local -A flagmap=()
    local -a posargs=()

    flagmap[token]=abc
    posargs=("/repos/org/repo")

    local -a curlFlags=()
    local -a curlPosArgs=()

    gh-unparse-curl-args flagmap posargs curlFlags curlPosArgs

    # Should have Authorization header
    local foundAuth=false
    for arg in "${curlFlags[@]}"; do
        [[ "$arg" == *"Authorization"* ]] && foundAuth=true
    done
    $foundAuth || { printf '  FAIL: no auth header\n'; return 1; }

    # URL should be constructed correctly
    [[ "${curlPosArgs[0]}" == "https://api.github.com/repos/org/repo" ]] \
        || { printf '  FAIL: url is %s\n' "${curlPosArgs[0]}"; return 1; }

    printf '  PASS\n'
}


test-unparse-per-page()
{
    local -A flagmap=()
    local -a posargs=()

    flagmap[per-page]=50
    posargs=("/repos/org/repo")

    local -a curlFlags=()
    local -a curlPosArgs=()

    gh-unparse-curl-args flagmap posargs curlFlags curlPosArgs

    [[ "${curlPosArgs[0]}" == "https://api.github.com/repos/org/repo?per_page=50" ]] \
        || { printf '  FAIL: url is %s\n' "${curlPosArgs[0]}"; return 1; }

    printf '  PASS\n'
}


test-unparse-data()
{
    local -A flagmap=()
    local -a posargs=()

    flagmap[data]='{"title":"test"}'
    posargs=("/repos/org/repo/issues")

    local -a curlFlags=()
    local -a curlPosArgs=()

    gh-unparse-curl-args flagmap posargs curlFlags curlPosArgs

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


run-tests()
{
    local tests=(
        test-parse-basic
        test-parse-interleaved
        test-parse-bool-flag
        test-parse-terminal
        test-unparse-basic
        test-unparse-per-page
        test-unparse-data
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
        test-unparse-basic|\
        test-unparse-per-page|\
        test-unparse-data)  "$@" ;;
        *)                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
