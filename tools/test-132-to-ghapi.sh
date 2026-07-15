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


verify-file ()
{
    local path=$1
    if [[ ! -f "$path" ]]; then
        printf '  file not found (%s)\n' "$path" >&2
        return 1
    fi
    if [[ ! -s "$path" ]]; then
        printf '  file is empty (%s)\n' "$path" >&2
        return 1
    fi
}


get-token ()
{
    gh auth token
}


test-ghr-download-extract-abs-file ()
{
    local token; token=$(get-token) || { printf '  FAIL\n'; return 1; }
    local tmpDir; tmpDir=$(mktemp -d --tmpdir test-extract-abs-file.XXXXXX)
    local outPath="$tmpDir/renamed-program"

    pushd "$tmpDir" >/dev/null || return 1
    ghr-download --token "$token" --extract "$outPath" dylt-dev dylt > /dev/null 2>&1
    popd >/dev/null
    verify-file "$outPath" && { printf '  PASS\n'; return 0; } || { printf '  FAIL\n'; return 1; }
}


test-ghr-download-extract-abs-dir ()
{
    local token; token=$(get-token) || { printf '  FAIL\n'; return 1; }
    local tmpDir; tmpDir=$(mktemp -d --tmpdir test-extract-abs-dir.XXXXXX)
    local outputDir="${tmpDir%/}/outdir/"

    pushd "$tmpDir" >/dev/null || return 1
    ghr-download --token "$token" --extract "$outputDir" dylt-dev dylt > /dev/null 2>&1
    popd >/dev/null

    local files
    files=("${outputDir%/}"/*)
    if [[ -f "${files[0]}" && -s "${files[0]}" ]]; then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


test-ghr-download-extract-rel-file ()
{
    local token; token=$(get-token) || { printf '  FAIL\n'; return 1; }
    local tmpDir; tmpDir=$(mktemp -d --tmpdir test-extract-rel-file.XXXXXX)

    pushd "$tmpDir" >/dev/null || return 1
    mkdir -p sub
    ghr-download --token "$token" --extract "sub/relocated" dylt-dev dylt > /dev/null 2>&1
    popd >/dev/null

    verify-file "$tmpDir/sub/relocated" && { printf '  PASS\n'; return 0; } \
                                         || { printf '  FAIL\n'; return 1; }
}


test-ghr-download-extract-rel-dir ()
{
    local token; token=$(get-token) || { printf '  FAIL\n'; return 1; }
    local tmpDir; tmpDir=$(mktemp -d --tmpdir test-extract-rel-dir.XXXXXX)

    pushd "$tmpDir" >/dev/null || return 1
    mkdir -p sub
    ghr-download --token "$token" --extract "sub/" dylt-dev dylt > /dev/null 2>&1
    popd >/dev/null

    local files
    files=("$tmpDir/sub"/*)
    if [[ -f "${files[0]}" && -s "${files[0]}" ]]; then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


test-ghr-download-extract-empty ()
{
    local token; token=$(get-token) || { printf '  FAIL\n'; return 1; }
    local tmpDir; tmpDir=$(mktemp -d --tmpdir test-extract-empty.XXXXXX)

    pushd "$tmpDir" >/dev/null || return 1
    ghr-download --token "$token" --extract "" dylt-dev dylt > /dev/null 2>&1
    popd >/dev/null

    local files
    files=("$tmpDir"/*)
    if [[ -f "${files[0]}" && -s "${files[0]}" ]]; then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


test-ghr-download-extract-existing ()
{
    local token; token=$(get-token) || { printf '  FAIL\n'; return 1; }
    local tmpDir; tmpDir=$(mktemp -d --tmpdir test-extract-existing.XXXXXX)
    local outPath="$tmpDir/existing-target"
    echo "preexisting" > "$outPath"

    ghr-download --token "$token" --extract "$outPath" dylt-dev dylt > /dev/null 2>&1 && {
        printf '  FAIL\n'
        return 1
    }
    printf '  PASS\n'
}


all()
{
    local tests=(
        test-ghr-version-path-latest
        test-ghr-version-path-versioned
        test-ghr-version-path-bad-input
        test-ghr-download-extract-abs-file
        test-ghr-download-extract-abs-dir
        test-ghr-download-extract-rel-file
        test-ghr-download-extract-rel-dir
        test-ghr-download-extract-empty
        test-ghr-download-extract-existing
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
        test-ghr-download-extract-abs-file)        test-ghr-download-extract-abs-file "$@";;
        test-ghr-download-extract-abs-dir)         test-ghr-download-extract-abs-dir "$@";;
        test-ghr-download-extract-rel-file)        test-ghr-download-extract-rel-file "$@";;
        test-ghr-download-extract-rel-dir)         test-ghr-download-extract-rel-dir "$@";;
        test-ghr-download-extract-empty)           test-ghr-download-extract-empty "$@";;
        test-ghr-download-extract-existing)        test-ghr-download-extract-existing "$@";;
        *)                                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
