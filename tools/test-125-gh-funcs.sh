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


# In    flagMap     { data: {"title":"test"}}
# Out   curlFlags   [ --data '{"title":"test"}' ]
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


# In    flagMap     {}
#       urlPath     /repos/org/repo
# Out   url         https://api.github.com/repos/org/repo
test-api-empty-flagmap()
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


# In    flagMap     { per-page: 50}
#       urlPath     /repos/org/repo
# Out   url         https://api.github.com/...?per_page=50
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


# In    cmdline     --nonexistent /repos/org/repo
# Out   result      exit != 0
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


test-resolve-output-remote-name()
{
    local -a curlFlags=()
    resolve-output-spec "" curlFlags

    local found=false
    for arg in "${curlFlags[@]}"; do
        [[ "$arg" == "--remote-name" ]] && found=true
    done
    $found || { printf '  FAIL: --remote-name not set for empty output\n'; return 1; }
    printf '  PASS\n'
}


test-resolve-output-abs-file()
{
    local tmpFile
    tmpFile=$(mktemp --tmpdir rayguntest.XXXXXXXX)
    rm -f "$tmpFile"  # dir exists, file does not

    local -a curlFlags=()
    resolve-output-spec "$tmpFile" curlFlags

    local found=false
    for arg in "${curlFlags[@]}"; do
        [[ "$arg" == "--output" ]] && found=true
    done
    $found || { printf '  FAIL: --output not set for file path\n'; return 1; }

    local foundPath=false
    for arg in "${curlFlags[@]}"; do
        [[ "$arg" == "$tmpFile" ]] && foundPath=true
    done
    $foundPath || { printf '  FAIL: file path not in curlFlags\n'; return 1; }

    rm -f "$tmpFile"
    printf '  PASS\n'
}


test-resolve-output-dir-trailing-slash()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir rayguntest.XXXXXXXX)

    local -a curlFlags=()
    resolve-output-spec "$tmpDir/" curlFlags

    local found=false
    for arg in "${curlFlags[@]}"; do
        [[ "$arg" == "--output-dir" ]] && found=true
    done
    $found || { printf '  FAIL: --output-dir not set for dir with slash\n'; return 1; }

    rm -rf "$tmpDir"
    printf '  PASS\n'
}


test-resolve-output-dir-no-slash()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir rayguntest.XXXXXXXX)

    local -a curlFlags=()
    resolve-output-spec "$tmpDir" curlFlags

    local found=false
    for arg in "${curlFlags[@]}"; do
        [[ "$arg" == "--output-dir" ]] && found=true
    done
    $found || { printf '  FAIL: --output-dir not set for existing dir without slash\n'; return 1; }

    rm -rf "$tmpDir"
    printf '  PASS\n'
}


test-resolve-output-file-exists()
{
    local tmpFile
    tmpFile=$(mktemp --tmpdir rayguntest.XXXXXXXX)

    local -a curlFlags=()
    resolve-output-spec "$tmpFile" curlFlags && {
        printf '  FAIL: expected error for existing file\n'
        rm -f "$tmpFile"
        return 1
    }

    rm -f "$tmpFile"
    printf '  PASS\n'
}


all()
{
    local tests=(
        test-parse-basic
        test-parse-interleaved
        test-parse-terminal
        test-parse-unknown-flag
        test-unparse-basic
        test-unparse-data
        test-api-empty-flagmap
        test-api-per-page
        test-resolve-output-remote-name
        test-resolve-output-abs-file
        test-resolve-output-dir-trailing-slash
        test-resolve-output-dir-no-slash
        test-resolve-output-file-exists
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
        all|"")  all;;
        test-parse-basic|\
        test-parse-interleaved|\
        test-parse-terminal|\
        test-parse-unknown-flag|\
        test-unparse-basic|\
        test-unparse-data|\
        test-api-empty-flagmap|\
        test-api-per-page|\
        test-resolve-output-remote-name|\
        test-resolve-output-abs-file|\
        test-resolve-output-dir-trailing-slash|\
        test-resolve-output-dir-no-slash|\
        test-resolve-output-file-exists)  "$@" ;;
        *)                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
