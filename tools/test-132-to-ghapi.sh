#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


test-ghr-version-path-latest ()
{
    local result
    result=$(ghr-version-path dylt-dev/dylt 2>/dev/null) || {
        printf '  FAIL\n'; return 1
    }
    [[ "$result" == "/repos/dylt-dev/dylt/releases/latest" ]] \
        && { printf '  PASS\n'; return 0; } \
        || { printf '  FAIL\n'; return 1; }
}


test-ghr-version-path-versioned ()
{
    local result
    result=$(ghr-version-path --version v1.0.0 dylt-dev/dylt 2>/dev/null) || {
        printf '  FAIL\n'; return 1
    }
    [[ "$result" == "/repos/dylt-dev/dylt/releases/tags/v1.0.0" ]] \
        && { printf '  PASS\n'; return 0; } \
        || { printf '  FAIL\n'; return 1; }
}


test-ghr-version-path-bad-input ()
{
    ghr-version-path "not-valid" 2>/dev/null && { printf '  FAIL\n'; return 1; }
    printf '  PASS\n'
}


all()
{
    local tests=(
        test-ghr-version-path-latest
        test-ghr-version-path-versioned
        test-ghr-version-path-bad-input
    )
    local total=${#tests[@]} passed=0 failed=0
    for t in "${tests[@]}"; do
        printf 'Test: %s\n' "$t"
        if "$t"; then (( passed++ )); else (( failed++ )); fi
    done
    printf '\n%d passed, %d failed, %d total\n' "$passed" "$failed" "$total"
    return "$failed"
}


main()
{
    case ${1:-all} in
        all|"")                                   all;;
        test-ghr-version-path-latest)             test-ghr-version-path-latest "$@";;
        test-ghr-version-path-versioned)          test-ghr-version-path-versioned "$@";;
        test-ghr-version-path-bad-input)          test-ghr-version-path-bad-input "$@";;
        *)                                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
