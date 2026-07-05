#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1


#-------------------------------------------------------------------------------
#
# download-github-openapi()
#
# Download the GitHub OpenAPI spec to a local file
# Usage:  download-github-openapi [$dest]
#
download-github-openapi ()
{
    local dest=${1:-/tmp/github-openapi.json}
    # shellcheck disable=SC2016
    (( $# >= 1 )) || printf 'Usage: download-github-openapi [$dest]\n'
    curl -sL "https://raw.githubusercontent.com/github/rest-api-description/main/descriptions/api.github.com/api.github.com.json" \
        -o "$dest" || return 1
    printf 'Downloaded to %s\n' "$dest"
}


#-------------------------------------------------------------------------------
#
# test-paginate-key()
#
# Verify the pagination key auto-detection algorithm against every GET
# endpoint in the GitHub OpenAPI spec.  The algorithm:
#
#   1. Response is type: array            → key = "."
#   2. Response is object with array field → key = ".<first array field>"
#   3. Otherwise                           → key = ".items"  (fallback)
#
# Accepts an optional path to the OpenAPI JSON (defaults to gh-openapi.json
# alongside this script).  Use download-github-openapi to fetch it fresh.
#
test-paginate-key ()
{
    local specPath=${1:-"$SCRIPT_DIR/gh-openapi.json"}

    if [[ ! -f "$specPath" ]]; then
        printf '  FAIL (paginate-key): spec not found at %s\n' "$specPath"
        printf '    Run download-github-openapi first, or pass a path.\n'
        return 1
    fi

    if ! python3 -c "import gh.paging" 2>/dev/null; then
        printf '  FAIL (paginate-key): raygun package not installed\n'
        printf '    Run src/raygun/scripts/setup-venv.sh then activate the venv.\n'
        return 1
    fi

    local result
    result=$(python3 -m gh.paging "$specPath" 2>&1) || {
        local rc=$?
        printf '%s\n' "$result"
        printf '  FAIL (paginate-key): %d paginated endpoint(s) have no array field\n' "$rc"
        return 1
    }

    printf '  PASS (paginate-key)\n'
    printf '%s\n' "$result"
    return 0
}


run-tests()
{
    local tests=(
        test-paginate-key
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
        download-github-openapi)  download-github-openapi "$@";;
        test-paginate-key)        test-paginate-key "$@";;
        all|run-tests|"")         run-tests ;;
        *)                        printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
