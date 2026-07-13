#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1


get-token ()
{
    # Resolve the token from gh auth — system test users are expected
    # to have gh installed and authenticated.
    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh auth token failed\n'
        return 1
    }
	printf '%s' "$token"
	if [[ -t 1 ]]; then printf '\n'; fi
}


print-filesize ()
{
	local path=$1

    local fileSize
    fileSize=$(stat -c%s "$path" 2>/dev/null)
    printf '  PASS (file: %s, size: %d)\n' "$path" "$fileSize"
}


# Assert a file exists and is non-empty; print PASS with size on success.
check-file ()
{
    local path=$1
    if [[ ! -f "$path" ]]; then
        printf '  FAIL: file not found (%s)\n' "$path"
        return 1
    fi
    if [[ ! -s "$path" ]]; then
        printf '  FAIL: file is empty\n' "$path"
        return 1
    fi
    print-filesize "$path"
}


# Call gh-api_ and capture stdout + exit code.  Prints error on failure.
download-file ()
{
    local res
    res=$(gh-api_ "$1" "$2" 2>/dev/null) || {
        printf '  FAIL: gh-api_ returned non-zero\n'
        return 1
    }
    printf '%s' "$res"
}



# Walk the user through an end-to-end system test of gh-api_ with
# a file download endpoint.  Uses the dylt release checksums file
# (~900 bytes).  No --output specified — file lands in current dir
# with Content-Disposition filename.
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-no-output
test-gh-api-kf-output-none ()
{
    # Isolated temp directory — we pushd into it so the download
    # lands here by default (resolve-output-spec with empty output
    # produces ./{cdFilename}).
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir ghapi-kf-no-output.XXXXXX)

	# set --token
	local token; token=$(get-token) || return

	# Build the flagMap the same way gh-api (UF) would after parsing
    # CLI args: token for auth, octet-stream to trigger the redirect
    # to cloud storage, which returns Content-Disposition.
    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'

    # dylt checksums asset — smallest available (~900 bytes)
    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    pushd "$tmpDir" >/dev/null || return 1

    local output
    output=$(download-file flagMap "$urlPath") || { popd >/dev/null; return 1; }

    popd >/dev/null

    # The CD filename from the release asset — hardcoded so we can
    # assert it was correctly extracted and used by resolve-output-spec.
    local expectedFile="dylt_0.0.11-nightly.20260617-test_checksums.txt"
    local expectedPath="$tmpDir/$expectedFile"

    check-file "$expectedPath" || return 1
    printf '  Temp folder: %s\n' "$tmpDir"
}


# Walk the user through gh-api_ download path with --output pointing
# to a directory (trailing slash).  The file should land in that
# directory with the Content-Disposition filename.
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-output-folder
test-gh-api-kf-output-absfolder ()
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

	# set token
	local token; token=$(get-token) || return

    # flagMap includes --output pointing to the destination folder
    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'
    flagMap[output]="$outputDir"

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    # call gh-api_ to download the file
    local output
    output=$(download-file flagMap "$urlPath") || return 1

    local expectedFile="dylt_0.0.11-nightly.20260617-test_checksums.txt"
    local expectedPath="${outputDir%/}/$expectedFile"

    check-file "$expectedPath" || return 1
}


#
#	test a download to an absolute path.
#	The folder will be a temporary folder
#	The filename will be my-download-target.tgz
#	The expected path for the download will be "$tmpFolder/$filename"
#
test-gh-api-kf-output-absfilename ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir ghapi-kf-output-path.XXXXXX)

    local token; token=$(get-token) || return

    local outputPath="$tmpDir/my-download-target.tgz"

    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'
    flagMap[output]="$outputPath"

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    local output
    output=$(download-file flagMap "$urlPath") || return 1

    check-file "$outputPath" || return 1
}


#
#	test a download to an relative filename.
#	The folder current dir, ie make a tmp dstFolder and hop in
#	The filename will be my-download-target.tgz
#	The expected path for the download will be "$dstFolder/$filename"
#
test-gh-api-kf-output-relfilename ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir ghapi-kf-output-filename.XXXXXX)

    local dstDir="$tmpDir/dst"
    mkdir -p "$dstDir"

    local token; token=$(get-token) || return

    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'
    flagMap[output]='my-download-target.tgz'

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    pushd "$dstDir" >/dev/null || return 1
    local output
    output=$(download-file flagMap "$urlPath") || { popd >/dev/null; return 1; }
    popd >/dev/null

    check-file "$dstDir/my-download-target.tgz" || return 1
}


# Walk the user through gh-api_ download path with --output pointing
# to a relative directory (trailing slash).  The file should land in that
# directory with the Content-Disposition filename.
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-output-relfolder
test-gh-api-kf-output-relfolder ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir ghapi-kf-output-relfolder.XXXXXX)

    # Relative subdirectory — pushd into tmpDir so sub/ resolves correctly
    mkdir -p "$tmpDir/sub"

    local token; token=$(get-token) || return

    local -A flagMap=()
    flagMap[token]="$token"
    flagMap[accept]='application/octet-stream'
    flagMap[output]='sub/'

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    pushd "$tmpDir" >/dev/null || return 1
    local output
    output=$(download-file flagMap "$urlPath") || { popd >/dev/null; return 1; }
    popd >/dev/null

    local expectedFile="dylt_0.0.11-nightly.20260617-test_checksums.txt"
    check-file "$tmpDir/sub/$expectedFile" || return 1
}


all()
{
    local tests=(
        test-gh-api-kf-output-none
        test-gh-api-kf-output-absfolder
        test-gh-api-kf-output-absfilename
        test-gh-api-kf-output-relfilename
        test-gh-api-kf-output-relfolder
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
        test-gh-api-kf-output-none)               test-gh-api-kf-output-none "$@";;
        test-gh-api-kf-output-absfolder)          test-gh-api-kf-output-absfolder "$@";;
        test-gh-api-kf-output-absfilename)        test-gh-api-kf-output-absfilename "$@";;
        test-gh-api-kf-output-relfilename)        test-gh-api-kf-output-relfilename "$@";;
        test-gh-api-kf-output-relfolder)          test-gh-api-kf-output-relfolder "$@";;
        *)                                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi





