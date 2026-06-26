#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
DAYLIGHT_SH="$SCRIPT_DIR/../daylight.sh"
[[ -f "$DAYLIGHT_SH" ]] || { printf 'Cannot find daylight.sh\n' >&2; exit 1; }
source "$DAYLIGHT_SH" || { printf 'Failed to source daylight.sh\n' >&2; exit 1; }

CURL_ARGS=()
curl() { CURL_ARGS=("$@"); return 0; }

# Release JSON fixture with .tar.gz, .zip, and other assets
RELEASE_JSON='{
  "assets": [
    {"name": "tool-windows-amd64.exe", "content_type": "application/octet-stream"},
    {"name": "tool-linux-amd64.tar.gz", "content_type": "application/gzip"},
    {"name": "tool-linux-arm64.tar.gz", "content_type": "application/gzip"},
    {"name": "tool-darwin-amd64.zip", "content_type": "application/zip"}
  ]
}'

# Release with no .tar.gz (fallback to .zip)
RELEASE_JSON_NO_TAR='{
  "assets": [
    {"name": "tool-windows-amd64.exe", "content_type": "application/octet-stream"},
    {"name": "tool-darwin-amd64.zip", "content_type": "application/zip"}
  ]
}'

# Release with no tar.gz or zip (fallback to first)
RELEASE_JSON_NO_ARCHIVE='{
  "assets": [
    {"name": "tool-windows-amd64.exe", "content_type": "application/octet-stream"}
  ]
}'

# Empty release
RELEASE_JSON_EMPTY='{"assets": []}'


run-tests()
{
    local tests=(
        test-get-asset-name-picks-tar-gz
        test-get-asset-name-fallsback-to-zip
        test-get-asset-name-fallsback-to-first
        test-get-asset-name-no-assets
        test-get-asset-name-rejects-bad-args
        test-download-asset-name-flag
        test-download-asset-name-positional
        test-download-asset-name-auto-detect
        test-download-output-dir-flag
        test-download-output-dir-default-temp
        test-download-extract-single
        test-download-extract-multi
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


test-get-asset-name-picks-tar-gz()
{
    github-release-get-data()
    {
        printf '%s' "$RELEASE_JSON"
    }
    local result
    result=$(github-release-get-asset-name org repo 2>&1) || {
        printf '  FAIL: expected success, got:\n  %s\n' "$result"
        return 1
    }
    [[ "$result" == "tool-linux-amd64.tar.gz" ]] || {
        printf '  FAIL: expected "tool-linux-amd64.tar.gz", got "%s"\n' "$result"
        return 1
    }
    printf '  PASS\n'
}


test-get-asset-name-fallsback-to-zip()
{
    github-release-get-data()
    {
        printf '%s' "$RELEASE_JSON_NO_TAR"
    }
    local result
    result=$(github-release-get-asset-name org repo 2>&1) || {
        printf '  FAIL: expected success, got:\n  %s\n' "$result"
        return 1
    }
    [[ "$result" == "tool-darwin-amd64.zip" ]] || {
        printf '  FAIL: expected "tool-darwin-amd64.zip", got "%s"\n' "$result"
        return 1
    }
    printf '  PASS\n'
}


test-get-asset-name-fallsback-to-first()
{
    github-release-get-data()
    {
        printf '%s' "$RELEASE_JSON_NO_ARCHIVE"
    }
    local result
    result=$(github-release-get-asset-name org repo 2>&1) || {
        printf '  FAIL: expected success, got:\n  %s\n' "$result"
        return 1
    }
    [[ "$result" == "tool-windows-amd64.exe" ]] || {
        printf '  FAIL: expected "tool-windows-amd64.exe", got "%s"\n' "$result"
        return 1
    }
    printf '  PASS\n'
}


test-get-asset-name-no-assets()
{
    github-release-get-data()
    {
        printf '%s' "$RELEASE_JSON_EMPTY"
    }
    fail-check "no assets" "No assets found" github-release-get-asset-name org repo
}


test-get-asset-name-rejects-bad-args()
{
    fail-check "bad args" "Usage" github-release-get-asset-name
}


test-download-asset-name-flag()
{
    local mockTmp; mockTmp=$(mktemp -d) || return 1

    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/999"
        ref[filename]="$3"
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
            echo "content" > "$t/single.txt"
            tar -czf "$output" -C "$t" single.txt || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download --asset-name my-asset.tar.gz org repo --output-dir "$mockTmp" 2>&1) || {
        printf '  FAIL: github-release-download with --asset-name failed:\n  %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    rm -rf "$mockTmp"
    printf '  PASS\n'
}


test-download-asset-name-positional()
{
    local mockTmp; mockTmp=$(mktemp -d) || return 1

    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/999"
        ref[filename]="$3"
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
            echo "content" > "$t/file.txt"
            tar -czf "$output" -C "$t" file.txt || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download org repo my-asset.tar.gz "$mockTmp" 2>&1) || {
        printf '  FAIL: github-release-download with positional name failed:\n  %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    rm -rf "$mockTmp"
    printf '  PASS\n'
}


test-download-asset-name-auto-detect()
{
    local mockTmp; mockTmp=$(mktemp -d) || return 1

    github-release-get-data()
    {
        printf '%s' "$RELEASE_JSON"
    }

    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/999"
        ref[filename]="$3"
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
            echo "content" > "$t/file.txt"
            tar -czf "$output" -C "$t" file.txt || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download --output-dir "$mockTmp" org repo 2>&1) || {
        printf '  FAIL: github-release-download auto-detect failed:\n  %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    rm -rf "$mockTmp"
    printf '  PASS\n'
}


test-download-output-dir-flag()
{
    local mockTmp; mockTmp=$(mktemp -d) || return 1

    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/999"
        ref[filename]="file.tar.gz"
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
            echo "content" > "$t/single.txt"
            tar -czf "$output" -C "$t" single.txt || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download --asset-name file.tar.gz --output-dir "$mockTmp" org repo 2>&1) || {
        printf '  FAIL: github-release-download with --output-dir failed:\n  %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    [[ "$result" == "$mockTmp/file.tar.gz" ]] || {
        printf '  FAIL: expected output "%s/file.tar.gz", got "%s"\n' "$mockTmp" "$result"
        rm -rf "$mockTmp"
        return 1
    }
    rm -rf "$mockTmp"
    printf '  PASS\n'
}


test-download-output-dir-default-temp()
{
    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/999"
        ref[filename]="file.tar.gz"
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
            echo "content" > "$t/single.txt"
            tar -czf "$output" -C "$t" single.txt || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download --asset-name file.tar.gz org repo 2>&1) || {
        printf '  FAIL: github-release-download with default temp dir failed:\n  %s\n' "$result"
        return 1
    }
    [[ "$result" == */file.tar.gz ]] || {
        printf '  FAIL: expected output ending in "/file.tar.gz", got "%s"\n' "$result"
        return 1
    }
    local dir; dir=$(dirname "$result")
    [[ -d "$dir" ]] || {
        printf '  FAIL: temp directory %s does not exist\n' "$dir"
        return 1
    }
    rm -rf "$dir"
    printf '  PASS\n'
}


test-download-extract-single()
{
    local mockTmp; mockTmp=$(mktemp -d) || return 1

    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/999"
        ref[filename]="release.tar.gz"
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
            echo "single file content" > "$t/single-file.txt"
            tar -czf "$output" -C "$t" single-file.txt || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download --asset-name release.tar.gz --extract --extract-dir "$mockTmp" --extract-name myfile org repo 2>&1) || {
        printf '  FAIL: extract single file failed:\n  %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    [[ -f "$result" ]] || {
        printf '  FAIL: extracted file not found at %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    local content; content=$(cat "$result")
    [[ "$content" == "single file content" ]] || {
        printf '  FAIL: content mismatch, got "%s"\n' "$content"
        rm -rf "$mockTmp"
        return 1
    }
    rm -rf "$mockTmp"
    printf '  PASS\n'
}


test-download-extract-multi()
{
    local mockTmp; mockTmp=$(mktemp -d) || return 1

    github-release-get-package-info()
    {
        local -n ref; ref=$1; shift
        while (( $# > 0 )) && [[ $1 == -* ]]; do
            [[ $1 == -- ]] && { shift; break; }
            shift $(( $1 == -* && $# > 1 ? 2 : 1 ))
        done
        ref[urlPath]="/repos/$1/$2/releases/assets/999"
        ref[filename]="multi.tar.gz"
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
            echo "file one" > "$t/file1.txt"
            echo "file two" > "$t/file2.txt"
            tar -czf "$output" -C "$t" file1.txt file2.txt || { rm -rf "$t"; return 1; }
            rm -rf "$t"
        fi
        return 0
    }

    local result
    result=$(github-release-download --asset-name multi.tar.gz --extract --extract-dir "$mockTmp" --extract-name multidir org repo 2>&1) || {
        printf '  FAIL: extract multi-file failed:\n  %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    [[ -d "$result" ]] || {
        printf '  FAIL: extracted directory not found at %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    [[ -f "$result/file1.txt" ]] || {
        printf '  FAIL: file1.txt not found in %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    [[ -f "$result/file2.txt" ]] || {
        printf '  FAIL: file2.txt not found in %s\n' "$result"
        rm -rf "$mockTmp"
        return 1
    }
    rm -rf "$mockTmp"
    printf '  PASS\n'
}


main()
{
    if (( $# >= 1 )); then
        local cmd=$1; shift
        case "$cmd" in
            run-tests)                                run-tests;;
            test-get-asset-name-picks-tar-gz)         test-get-asset-name-picks-tar-gz;;
            test-get-asset-name-fallsback-to-zip)     test-get-asset-name-fallsback-to-zip;;
            test-get-asset-name-fallsback-to-first)   test-get-asset-name-fallsback-to-first;;
            test-get-asset-name-no-assets)            test-get-asset-name-no-assets;;
            test-get-asset-name-rejects-bad-args)     test-get-asset-name-rejects-bad-args;;
            test-download-asset-name-flag)            test-download-asset-name-flag;;
            test-download-asset-name-positional)      test-download-asset-name-positional;;
            test-download-asset-name-auto-detect)     test-download-asset-name-auto-detect;;
            test-download-output-dir-flag)            test-download-output-dir-flag;;
            test-download-output-dir-default-temp)    test-download-output-dir-default-temp;;
            test-download-extract-single)             test-download-extract-single;;
            test-download-extract-multi)              test-download-extract-multi;;
            *)                                        printf 'Unknown test: %s\n' "$cmd" >&2; exit 1;;
        esac
    else
        run-tests
    fi
}

if ! (return 0 2>/dev/null); then
    main "$@"
fi
