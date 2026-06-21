#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
DAYLIGHT_SH="$SCRIPT_DIR/../daylight.sh"
[[ -f "$DAYLIGHT_SH" ]] || { printf 'Cannot find daylight.sh\n' >&2; exit 1; }
source "$DAYLIGHT_SH" || { printf 'Failed to source daylight.sh\n' >&2; exit 1; }

# Global mock for github-curl tests
CURL_ARGS=()
curl() { CURL_ARGS=("$@"); return 0; }


#-------------------------------------------------------------------------------
#
# run-tests()
#
run-tests()
{
    local tests=(
        test-github-curl-remote-name
        test-github-curl-output-wins
        test-github-curl-output-dir
        test-download-batch-unknown-flag
        test-download-batch-extract-flags
        test-download-batch-output-dir-remote-name
        test-release-download-extract
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
# test-github-curl-remote-name()
#
# Verify --remote-name passes --remote-name to curl instead of --output -
#
test-github-curl-remote-name()
{
    CURL_ARGS=()
    github-curl --remote-name repos/owner/repo/releases 2>/dev/null || true
    local found_remote=0 found_output=0
    for arg in "${CURL_ARGS[@]}"; do
        [[ $arg == "--remote-name" ]] && found_remote=1
        [[ $arg == "--output" ]] && found_output=1
    done
    (( found_remote == 1 )) || { printf '  FAIL: --remote-name not in curl args\n'; return 1; }
    (( found_output == 0 )) || { printf '  FAIL: --output should not be present with --remote-name\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-github-curl-output-wins()
#
# Verify explicit --output overrides --remote-name
#
test-github-curl-output-wins()
{
    CURL_ARGS=()
    github-curl --remote-name --output /dev/null repos/owner/repo/releases 2>/dev/null || true
    local found_remote=0 found_output=0
    for arg in "${CURL_ARGS[@]}"; do
        [[ $arg == "--remote-name" ]] && found_remote=1
        [[ $arg == "--output" ]] && found_output=1
    done
    (( found_output == 1 )) || { printf '  FAIL: --output not in curl args\n'; return 1; }
    (( found_remote == 0 )) || { printf '  FAIL: --remote-name should be ignored when --output is explicit\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-github-curl-output-dir()
#
# Verify --remote-name --output-dir passes both to curl
#
test-github-curl-output-dir()
{
    CURL_ARGS=()
    github-curl --remote-name --output-dir /tmp repos/owner/repo/releases 2>/dev/null || true
    local found_dir=0
    local i; for ((i=0; i<${#CURL_ARGS[@]}; i++)); do
        [[ ${CURL_ARGS[i]} == "--output-dir" ]] && [[ ${CURL_ARGS[i+1]} == "/tmp" ]] && found_dir=1
    done
    (( found_dir == 1 )) || { printf '  FAIL: --output-dir /tmp not in curl args\n'; return 1; }
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# test-download-batch-unknown-flag()
#
# Verify download-daylight-batch rejects unknown flags
#
test-download-batch-unknown-flag()
{
    fail-check "unknown flag" "Unknown flag" download-daylight-batch --bogus /nonexistent
}


#-------------------------------------------------------------------------------
#
# test-download-batch-extract-flags()
#
# Verify --extract/--extract-dir/--extract-name parse correctly
#
test-download-batch-extract-flags()
{
    fail-check "extract flags" "Non-existent folder" \
        download-daylight-batch --extract --extract-dir /opt --extract-name x /nonexistent
}


#-------------------------------------------------------------------------------
#
# test-download-batch-output-dir-remote-name()
#
# Verify --output-dir and --remote-name pass through (don't break parsing)
#
test-download-batch-output-dir-remote-name()
{
    fail-check "output-dir remote-name" "Non-existent folder" \
        download-daylight-batch --output-dir /tmp --remote-name --token sekret /nonexistent
}


#-------------------------------------------------------------------------------
#
# test-release-download-extract()
#
# Verify github-release-download downloads and extracts with --extract flags
#
test-release-download-extract()
{
    local mockTmp; mockTmp=$(mktemp -d) || return

    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/123"
        ref[filename]=$3
    }

    github-curl()
    {
        local output=""
        local i; for ((i=1; i<=$#; i++)); do
            if [[ "${!i}" == "--output" ]] && (( i+1 <= $# )); then
                local j=$((i+1))
                output="${!j}"
            fi
        done
        if [[ -n "$output" ]]; then
            mkdir -p "$(dirname "$output")"
            local t; t=$(mktemp -d)
            echo "test content" > "$t/release-file"
            tar -czf "$output" -C "$t" release-file || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download --extract --extract-dir "$mockTmp" --extract-name myextracted org repo release-file.tar.gz "$mockTmp"/dl 2>&1) || {
        printf '  FAIL: github-release-download failed:\n  %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }

    if [[ ! -f "$result" ]]; then
        printf '  FAIL: extracted file not found at %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    fi

    local content
    content=$(cat "$result")
    if [[ "$content" != "test content" ]]; then
        printf '  FAIL: extracted file content mismatch (got %s)\n' "$content"
        rm -rf "$mockTmp"
        return 1
    fi

    rm -rf "$mockTmp"
    printf '  PASS\n'
}


#-------------------------------------------------------------------------------
#
# main()
#
main()
{
    if (( $# >= 1 )); then
        local cmd=$1; shift
        case "$cmd" in
            run-tests)                              run-tests;;
            test-github-curl-remote-name)           test-github-curl-remote-name;;
            test-github-curl-output-wins)           test-github-curl-output-wins;;
            test-github-curl-output-dir)            test-github-curl-output-dir;;
            test-download-batch-unknown-flag)       test-download-batch-unknown-flag;;
            test-download-batch-extract-flags)      test-download-batch-extract-flags;;
            test-download-batch-output-dir-remote-name) test-download-batch-output-dir-remote-name;;
            test-release-download-extract)          test-release-download-extract;;
            *)                                      printf 'Unknown test: %s\n' "$cmd" >&2; exit 1;;
        esac
    else
        run-tests
    fi
}

if ! (return 0 2>/dev/null); then
    main "$@"
fi
