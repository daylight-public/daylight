#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1


# Walk the user through an end-to-end system test of gh-api_ with
# a file download endpoint.  Uses the dylt release checksums file
# (~900 bytes).  No --output specified — file lands in current dir
# with Content-Disposition filename.
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-no-output
test-gh-api-kf-no-output ()
{
    # Isolated temp directory — we pushd into it so the download
    # lands here by default (resolve-output-spec with empty output
    # produces ./{cdFilename}).
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir ghapi-kf-no-output.XXXXXX)
    pushd "$tmpDir" >/dev/null || return 1

    # Resolve the token from gh auth — system test users are expected
    # to have gh installed and authenticated.
    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh auth token failed\n'
        popd >/dev/null
        return 1
    }

    # Build the flagMap the same way gh-api (UF) would after parsing
    # CLI args: token for auth, octet-stream to trigger the redirect
    # to cloud storage, which returns Content-Disposition.
    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'

    # dylt checksums asset — smallest available (~900 bytes)
    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    # Call the kernel function directly.  gh-api_ handles everything:
    # curl, CD detection, resolve-output-spec, copy, and path output.
    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || {
        printf '  FAIL: gh-api_ returned non-zero\n'
        popd >/dev/null
        return 1
    }

    # The CD filename from the release asset — hardcoded so we can
    # assert it was correctly extracted and used by resolve-output-spec.
    local expectedFile="dylt_0.0.11-nightly.20260617-test_checksums.txt"

    # Assert the file exists in the current directory (no --output
    # means it lands here via resolve-output-spec's default behavior)
    if [[ ! -f "$expectedFile" ]]; then
        printf '  FAIL: downloaded file not found (%s)\n' "$expectedFile"
        ls "$tmpDir"
        popd >/dev/null
        return 1
    fi

    # Assert the file is non-empty (895 bytes expected for checksums)
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


# Walk the user through gh-api_ download path with --output pointing
# to a directory (trailing slash).  The file should land in that
# directory with the Content-Disposition filename.
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-output-folder
test-gh-api-kf-output-folder ()
{
    # Isolated temp directory for test artifacts (raw files, headers)
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir ghapi-kf-output-folder.XXXXXX)

    # Separate output directory — where the downloaded file should
    # land when --output points to a folder.
    local outputDir
    outputDir=$(mktemp -d --tmpdir ghapi-kf-output-folder-dest.XXXXXX)

    # Ensure trailing slash so resolve-output-spec treats it as a
    # directory, not a file path, appending the CD filename.
    outputDir="${outputDir%/}/"

    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh auth token failed\n'
        return 1
    }

    # flagMap includes --output pointing to the destination folder
    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'
    flagMap[output]="$outputDir"

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    # No pushd/popd needed — the output goes to a separate directory.
    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || {
        printf '  FAIL: gh-api_ returned non-zero\n'
        return 1
    }

    local expectedFile="dylt_0.0.11-nightly.20260617-test_checksums.txt"
    local expectedPath="${outputDir%/}/$expectedFile"

    # Assert the file exists in the output directory
    if [[ ! -f "$expectedPath" ]]; then
        printf '  FAIL: file not found at %s\n' "$expectedPath"
        ls "$outputDir"
        return 1
    fi

    # Assert the file is non-empty
    if [[ ! -s "$expectedPath" ]]; then
        printf '  FAIL: file is empty\n'
        return 1
    fi

    local fileSize
    fileSize=$(stat -c%s "$expectedPath" 2>/dev/null)
    printf '  PASS (file: %s, size: %d)\n' "$output" "$fileSize"
}


main()
{
    case ${1:-} in
        test-gh-api-kf-no-output)      test-gh-api-kf-no-output "$@";;
        test-gh-api-kf-output-folder)  test-gh-api-kf-output-folder "$@";;
        "")                            printf 'Usage: %s <test-name>\n' "$0" >&2; exit 1 ;;
        *)                             printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi





