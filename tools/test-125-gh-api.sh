#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1


# --output	(None)
# expected results
test-gh-api-kf-no-output ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir ghapi-kf-no-output.XXXXXX)
    pushd "$tmpDir" >/dev/null || return 1

    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh auth token failed\n'
        popd >/dev/null
        return 1
    }

    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || {
        printf '  FAIL: gh-api_ returned non-zero\n'
        popd >/dev/null
        return 1
    }

    local expectedFile="dylt_0.0.11-nightly.20260617-test_checksums.txt"

    if [[ ! -f "$expectedFile" ]]; then
        printf '  FAIL: downloaded file not found (%s)\n' "$expectedFile"
        ls "$tmpDir"
        popd >/dev/null
        return 1
    fi

    if [[ ! -s "$expectedFile" ]]; then
        printf '  FAIL: downloaded file is empty\n'
        popd >/dev/null
        return 1
    fi

    local fileSize
    fileSize=$(stat -c%s "$expectedFile" 2>/dev/null)
    printf '  PASS (file: %s, size: %d)\n' "$output" "$fileSize"
    popd >/dev/null
    printf '  Temp folder: %s\n' "$tmpDir"
}


main()
{
    case ${1:-} in
        test-gh-api-kf-no-output) test-gh-api-kf-no-output "$@";;
        "")                        printf 'Usage: %s <test-name>\n' "$0" >&2; exit 1 ;;
        *)                         printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi





