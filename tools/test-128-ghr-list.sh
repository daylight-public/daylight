#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


get-token ()
{
    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh auth token failed\n'
        return 1
    }
    printf '%s' "$token"
    if [[ -t 1 ]]; then printf '\n'; fi
}


test-ghr-list ()
{
    local token; token=$(get-token) || return

    local output
    output=$(ghr-list --token "$token" dylt-dev/dylt) || { printf '  FAIL\n'; return 1; }

    local count
    count=$(wc -l <<< "$output")
    if (( count > 5 )); then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


all()
{
    local tests=(test-ghr-list)
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
        test-ghr-list)                            test-ghr-list "$@";;
        *)                                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
