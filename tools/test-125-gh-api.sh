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


# Assert stdout is valid JSON with an expected key.  Reads first line of
# stdin, parses with jq, checks for expectedKey.
check-json-data ()
{
    local expectedKey=${1:-tag_name}
    local data
    data=$(cat)
    if [[ -z "$data" ]]; then
        printf '  FAIL: empty output from gh-api_\n'
        return 1
    fi
    jq -e --arg key "$expectedKey" 'has($key)' <<< "$data" > /dev/null 2>&1 || {
        printf '  FAIL: not valid JSON or missing "%s"\n' "$expectedKey"
        return 1
    }
    local val
    val=$(jq -r --arg key "$expectedKey" '.[$key]' <<< "$data" 2>/dev/null)
    printf '  PASS (data: %s)\n' "$val"
}


# Silent helpers — return 0/1, write errors to stderr only.
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

verify-json-file ()
{
    local path=$1
    verify-file "$path" || return 1
    jq . "$path" > /dev/null 2>&1 || {
        printf '  not valid JSON (%s)\n' "$path" >&2
        return 1
    }
}

verify-paginated ()
{
    local data=$1
    local count
    count=$(jq 'length' <<< "$data" 2>/dev/null) || return 1
    if (( count <= 30 )); then
        printf '  length=%d, expected >30\n' "$count" >&2
        return 1
    fi
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


test-gh-api-save-file-happy ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-gh-api-save-file.XXXXXX)
    mkdir -p "$tmpDir/dst"
    echo "hello" > "$tmpDir/src.txt"

    gh-api-save-file "$tmpDir/src.txt" "$tmpDir/dst/saved.txt" || {
        printf '  FAIL: save returned non-zero\n'
        return 1
    }

    [[ -f "$tmpDir/dst/saved.txt" ]] || { printf '  FAIL: file not created\n'; return 1; }
    printf '  PASS\n'
}


test-gh-api-save-file-collision ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-gh-api-save-file.XXXXXX)
    mkdir -p "$tmpDir/dst"
    echo "original" > "$tmpDir/dst/existing.txt"
    echo "hello" > "$tmpDir/src.txt"

    gh-api-save-file "$tmpDir/src.txt" "$tmpDir/dst/existing.txt" && {
        printf '  FAIL: expected collision error\n'
        return 1
    }
    printf '  PASS\n'
}


test-gh-api-save-file-nosuchdir ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-gh-api-save-file.XXXXXX)
    echo "hello" > "$tmpDir/src.txt"

    gh-api-save-file "$tmpDir/src.txt" "$tmpDir/missing/sub/file.txt" && {
        printf '  FAIL: expected cp error\n'
        return 1
    }
    printf '  PASS\n'
}


test-gh-api-save-file-dirambiguity ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-gh-api-save-file.XXXXXX)
    mkdir -p "$tmpDir/dstdir"
    echo "hello" > "$tmpDir/src.txt"

    gh-api-save-file "$tmpDir/src.txt" "$tmpDir/dstdir" && {
        printf '  FAIL: expected dir ambiguity error\n'
        return 1
    }
    printf '  PASS\n'
}


# test an abspath dylt package download with accepts=None
# function should download json initially, then
# recover and lookup the proper Accepts mediatype and then successfuly download
# expected results are the same as for any abspath download
test-gh-api-kf-file-accepts-none ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-accepts-none.XXXXXX)

    local token; token=$(get-token) || return

    local outputPath="$tmpDir/my-download-target.tgz"

    local -A flagMap=()
    # No accept set — relies on default application/vnd.github+json.
    # gh-api_ should detect the file endpoint from the response,
    flagMap[token]="$token"
    # look up the media type, and retry with the correct Accept.
    flagMap[output]="$outputPath"

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    local output
    output=$(download-file flagMap "$urlPath") || return 1

    check-file "$outputPath" || return 1
}


# test an abspath dylt package download with accepts=json
# function should download json initially, then
# recover and lookup the proper Accepts mediatype and then successfuly download
# expected results are the same as for any abspath download
test-gh-api-kf-file-accepts-json ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-accepts-json.XXXXXX)

    local token; token=$(get-token) || return

    local outputPath="$tmpDir/my-download-target.tgz"

    local -A flagMap=()
    flagMap[accept]='application/json'
    flagMap[token]="$token"
    flagMap[output]="$outputPath"

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    local output
    output=$(download-file flagMap "$urlPath") || return 1

    check-file "$outputPath" || return 1
}


# test an abspath dylt package download with accepts=application/octet-stream
# function should download application-octet/stream, and succeed
# expected results are the same as for any abspath download
test-gh-api-kf-file-accepts-octo ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-accepts-octo.XXXXXX)

    local token; token=$(get-token) || return

    local outputPath="$tmpDir/my-download-target.tgz"

    local -A flagMap=()
    flagMap[accept]='application/octet-stream'
    flagMap[token]="$token"
    flagMap[output]="$outputPath"

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    local output
    output=$(download-file flagMap "$urlPath") || return 1

    check-file "$outputPath" || return 1
}

# test an abspath dylt package download with accepts=xxxINVALIDxxx
# not sure what should happen honestly
# expected results are the same as for any abspath download
test-gh-api-kf-file-accepts-xxx ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-accepts-xxx.XXXXXX)

    local token; token=$(get-token) || return

    local outputPath="$tmpDir/my-download-target.tgz"

    local -A flagMap=()
    flagMap[accept]='application/xxxINVALIDxxx'
    flagMap[token]="$token"
    flagMap[output]="$outputPath"

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    local output
    output=$(download-file flagMap "$urlPath") || return 1

    check-file "$outputPath" || return 1
}


# test a JSON data endpoint with default Accept (no explicit accept set)
# gh-api_ should return JSON data via stdout, not a file download
test-gh-api-kf-data-accepts-none ()
{
    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || {
        printf '  FAIL: gh-api_ returned non-zero\n'
        return 1
    }

    printf '%s\n' "$output" | check-json-data 'tag_name' || return 1
}


# test a JSON data endpoint with explicit JSON Accept
# should return JSON data via stdout
test-gh-api-kf-data-accepts-json ()
{
    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"
    flagMap[accept]='application/vnd.github+json'

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || {
        printf '  FAIL: gh-api_ returned non-zero\n'
        return 1
    }

    printf '%s\n' "$output" | check-json-data 'tag_name' || return 1
}


# test a JSON data endpoint with invalid Accept
# 415 → retry with JSON → stdout JSON data
test-gh-api-kf-data-accepts-xxx ()
{
    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"
    flagMap[accept]='application/xxxINVALIDxxx'

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || {
        printf '  FAIL: gh-api_ returned non-zero\n'
        return 1
    }

    printf '%s\n' "$output" | check-json-data 'tag_name' || return 1
}


# fetch /organizations and verify we get more than one page of results
test-gh-api-kf-data-paging ()
{
    local token; token=$(get-token) || return

    # Belt-and-suspenders: verify /organizations has more than one page
    # of results by fetching per_page=50 directly via curl.
    local verifyCount
    verifyCount=$(curl --silent --header "Authorization: Bearer $token" \
        "https://api.github.com/organizations?per_page=50" | jq 'length')
    if [[ "$verifyCount" -le 30 ]]; then
        printf '  FAIL: conditions not met (orgs per_page=50 returned %d, expected >30)\n' "$verifyCount"
        return 1
    fi

    local -A flagMap=()
    flagMap[token]="$token"
    local urlPath="/organizations"

    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || { printf '  FAIL\n'; return 1; }

    verify-paginated "$output" && { printf '  PASS\n'; return 0; } \
                               || { printf '  FAIL\n'; return 1; }
}


# data output: no --output → stdout JSON
test-gh-api-kf-data-output-none ()
{
    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    local output
    output=$(gh-api_ flagMap "$urlPath" 2>/dev/null) || {
        printf '  FAIL\n'
        return 1
    }

    printf '%s\n' "$output" | check-json-data 'tag_name' || {
        printf '  FAIL\n'
        return 1
    }
    printf '  PASS\n'
}


# data output: --output /abs/path/file.json → file saved
test-gh-api-kf-data-output-absfilename ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-data-output-absfilename.XXXXXX)

    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"
    flagMap[output]="$tmpDir/data.json"

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    gh-api_ flagMap "$urlPath" > /dev/null 2>&1 || true
    verify-json-file "$tmpDir/data.json" && {
        printf '  PASS\n'
        return 0
    } || {
        printf '  FAIL\n'
        return 1
    }
}


# data output: --output sub/file.json → relative file saved
test-gh-api-kf-data-output-relfilename ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-data-output-relfilename.XXXXXX)

    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"
    flagMap[output]="sub/data.json"

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    pushd "$tmpDir" >/dev/null || return 1
    mkdir -p sub
    gh-api_ flagMap "$urlPath" > /dev/null 2>&1 || true
    popd >/dev/null

    verify-json-file "$tmpDir/sub/data.json" && {
        printf '  PASS\n'
        return 0
    } || {
        printf '  FAIL\n'
        return 1
    }
}


# data output: --output /abs/path/dir/ → /abs/path/dir/data.json
test-gh-api-kf-data-output-absfolder ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-data-output-absfolder.XXXXXX)
    local outputDir="${tmpDir%/}/outdir/"
    mkdir -p "${outputDir%/}"

    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"
    flagMap[output]="$outputDir"

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    gh-api_ flagMap "$urlPath" > /dev/null 2>&1 || true

    verify-json-file "${outputDir}data.json" && {
        printf '  PASS\n'
        return 0
    } || {
        printf '  FAIL\n'
        return 1
    }
}


# data output: --output sub/ → sub/data.json
test-gh-api-kf-data-output-relfolder ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-data-output-relfolder.XXXXXX)

    local -A flagMap=()
    local token; token=$(get-token) || return
    flagMap[token]="$token"
    flagMap[output]="sub/"

    local urlPath="/repos/dylt-dev/dylt/releases/latest"

    pushd "$tmpDir" >/dev/null || return 1
    mkdir -p sub
    gh-api_ flagMap "$urlPath" > /dev/null 2>&1 || true
    popd >/dev/null

    verify-json-file "$tmpDir/sub/data.json" && {
        printf '  PASS\n'
        return 0
    } || {
        printf '  FAIL\n'
        return 1
    }
}


# Walk the user through an end-to-end system test of gh-api_ with
# a file download endpoint.  Uses the dylt release checksums file
# (~900 bytes).  No --output specified — file lands in current dir
# with Content-Disposition filename.
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-no-output
test-gh-api-kf-file-output-none ()
{
    # Isolated temp directory — we pushd into it so the download
    # lands here by default (gh-api-resolve-output-spec with empty output
    # produces ./{cdFilename}).
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-no-output.XXXXXX)

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
    # assert it was correctly extracted and used by gh-api-resolve-output-spec.
    local expectedFile="dylt_0.0.11-nightly.20260617-test_checksums.txt"
    local expectedPath="$tmpDir/$expectedFile"

    check-file "$expectedPath" || return 1
    printf '  Temp folder: %s\n' "$tmpDir"
}


# Walk the user through gh-api_ download path with --output pointing
# to a directory (trailing slash).  The file should land in that
# directory with the Content-Disposition filename.
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-file-output-folder
test-gh-api-kf-file-output-absfolder ()
{
    # Isolated temp directory for test artifacts (raw files, headers)
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-output-folder.XXXXXX)

    # Separate output directory — where the downloaded file should
    # land when --output points to a folder.
    local outputDir
    outputDir=$(mktemp -d --tmpdir gh-api-kf-file-output-folder-dest.XXXXXX)

    # Ensure trailing slash so gh-api-resolve-output-spec treats it as a
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
test-gh-api-kf-file-output-absfilename ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-output-path.XXXXXX)

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
test-gh-api-kf-file-output-relfilename ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-output-filename.XXXXXX)

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
# Invoke: bash test-125-gh-api.sh test-gh-api-kf-file-output-relfolder
test-gh-api-kf-file-output-relfolder ()
{
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-kf-file-output-relfolder.XXXXXX)

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


generate-bbolt-fixtures ()
{
    local fixtureDir=$1
    mkdir -p "$fixtureDir"
    local token
    token=$(gh auth token) || return 1
    local url="https://api.github.com/search/repositories?q=bbolt&per_page=30"
    local page=0

    while [[ -n "$url" ]]; do
        local file="$fixtureDir/page-$(printf '%06d' "$page").json"
        curl --silent --dump-header "$fixtureDir/headers.txt" \
             --header "Authorization: Bearer $token" \
             --output "$file" "$url"
        url=$(gh-api-lookup-next-link < "$fixtureDir/headers.txt")
        (( page++ ))
    done
}


test-gh-api-merge-pages ()
{
    local fixtureDir="$SCRIPT_DIR/fixtures/bbolt"
    mkdir -p "$fixtureDir"

    if ! compgen -G "$fixtureDir/page-*.json" >/dev/null 2>&1; then
        generate-bbolt-fixtures "$fixtureDir" || { printf '  FAIL\n'; return 1; }
    fi

    local files=( "$fixtureDir"/page-*.json )
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-gh-api-merge.XXXXXX)
    local mergedFile="$tmpDir/merged.json"

    gh-api-merge-pages --jq-path items "${files[@]}" > "$mergedFile" \
        || { printf '  FAIL\n'; return 1; }

    local total
    total=$(jq '.total_count' "$mergedFile") || { printf '  FAIL\n'; return 1; }
    local count
    count=$(jq '.items | length' "$mergedFile") || { printf '  FAIL\n'; return 1; }

    if (( count != total )); then
        printf '  FAIL\n'
        return 1
    fi

    printf '  PASS\n'
}


# UF-level test: file download recovers from broken Accept
test-gh-api-file-recover ()
{
    local token; token=$(get-token) || return
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-file-recover.XXXXXX)

    gh-api --token "$token" \
           --accept 'application/xxxINVALIDxxx' \
           --output "$tmpDir/download.tgz" \
           /repos/dylt-dev/dylt/releases/assets/449914893 > /dev/null 2>&1

    verify-file "$tmpDir/download.tgz" && { printf '  PASS\n'; return 0; } \
                                        || { printf '  FAIL\n'; return 1; }
}


# UF-level test: paginated data merge via UF
test-gh-api-data-paginated ()
{
    local token; token=$(get-token) || return
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir gh-api-data-paginated.XXXXXX)

    gh-api --token "$token" \
           --jq-path items \
           --output "$tmpDir/merged.json" \
           /search/repositories?q=bbolt > /dev/null 2>&1

    local total
    total=$(jq '.total_count' "$tmpDir/merged.json") || { printf '  FAIL\n'; return 1; }
    local count
    count=$(jq '.items | length' "$tmpDir/merged.json") || { printf '  FAIL\n'; return 1; }

    if (( count == total )); then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


test-ghr-download-output-none ()
{
    local token; token=$(get-token) || return
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-ghr-dl-none.XXXXXX)

    # pushd so file lands in tmpDir with CD filename
    pushd "$tmpDir" >/dev/null || return 1
    ghr-download --token "$token" dylt-dev dylt > /dev/null 2>&1
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


test-ghr-download-output-absdir ()
{
    local token; token=$(get-token) || return
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-ghr-dl-dir.XXXXXX)
    local outputDir="${tmpDir%/}/dl/"
    mkdir -p "${outputDir%/}"

    ghr-download --token "$token" --output "$outputDir" dylt-dev dylt > /dev/null 2>&1 || {
        printf '  FAIL\n'
        return 1
    }

    local files
    files=("${outputDir%/}"/*)
    if [[ -f "${files[0]}" && -s "${files[0]}" ]]; then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


test-ghr-download-output-absfile ()
{
    local token; token=$(get-token) || return
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-ghr-dl-file.XXXXXX)
    local outputPath="$tmpDir/my-download.tar.gz"

    ghr-download --token "$token" --output "$outputPath" dylt-dev dylt > /dev/null 2>&1 || {
        printf '  FAIL\n'
        return 1
    }

    if [[ -f "$outputPath" && -s "$outputPath" ]]; then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


test-ghr-download-version ()
{
    local token; token=$(get-token) || return
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-ghr-dl-ver.XXXXXX)

    ghr-download --token "$token" --version v0.0.11-nightly.20260617-test \
                 --output "$tmpDir/" dylt-dev dylt > /dev/null 2>&1 || {
        printf '  FAIL\n'
        return 1
    }

    local files
    files=("$tmpDir"/*)
    if [[ -f "${files[0]}" && -s "${files[0]}" ]]; then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


test-ghr-download-version-nonexist ()
{
    local token; token=$(get-token) || return

    ghr-download --token "$token" --version v999.999.999 dylt-dev dylt > /dev/null 2>&1 && {
        printf '  FAIL\n'
        return 1
    }
    printf '  PASS\n'
}


test-ghr-download-version-previous ()
{
    local token; token=$(get-token) || return
    local tmpDir
    tmpDir=$(mktemp -d --tmpdir test-ghr-dl-prev.XXXXXX)

    ghr-download --token "$token" --version v0.0.8-nightly.20250306124812 \
                 --output "$tmpDir/" dylt-dev dylt > /dev/null 2>&1 || {
        printf '  FAIL\n'
        return 1
    }

    local files
    files=("$tmpDir"/*)
    if [[ -f "${files[0]}" && -s "${files[0]}" ]]; then
        printf '  PASS\n'
    else
        printf '  FAIL\n'
        return 1
    fi
}


all()
{
    local tests=(
        test-gh-api-save-file-happy
        test-gh-api-save-file-collision
        test-gh-api-save-file-nosuchdir
        test-gh-api-save-file-dirambiguity
        test-gh-api-kf-file-output-none
        test-gh-api-kf-file-output-absfolder
        test-gh-api-kf-file-output-absfilename
        test-gh-api-kf-file-output-relfilename
        test-gh-api-kf-file-output-relfolder
        test-gh-api-kf-file-accepts-none
        test-gh-api-kf-file-accepts-json
        test-gh-api-kf-file-accepts-octo
        test-gh-api-kf-file-accepts-xxx
        test-gh-api-kf-data-accepts-none
        test-gh-api-kf-data-accepts-json
        test-gh-api-kf-data-accepts-xxx
        #test-gh-api-kf-data-paging
        test-gh-api-kf-data-output-none
        test-gh-api-kf-data-output-absfilename
        test-gh-api-kf-data-output-relfilename
        test-gh-api-kf-data-output-absfolder
        test-gh-api-kf-data-output-relfolder
        test-gh-api-merge-pages
        test-gh-api-file-recover
        test-gh-api-data-paginated
        test-ghr-download-output-none
        test-ghr-download-output-absdir
        test-ghr-download-output-absfile
        test-ghr-download-version
        test-ghr-download-version-nonexist
        test-ghr-download-version-previous
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
        test-gh-api-kf-file-output-none)               test-gh-api-kf-file-output-none "$@";;
        test-gh-api-kf-file-output-absfolder)          test-gh-api-kf-file-output-absfolder "$@";;
        test-gh-api-kf-file-output-absfilename)        test-gh-api-kf-file-output-absfilename "$@";;
        test-gh-api-kf-file-output-relfilename)        test-gh-api-kf-file-output-relfilename "$@";;
        test-gh-api-kf-file-output-relfolder)          test-gh-api-kf-file-output-relfolder "$@";;
        test-gh-api-kf-file-accepts-none)              test-gh-api-kf-file-accepts-none "$@";;
        test-gh-api-kf-file-accepts-json)              test-gh-api-kf-file-accepts-json "$@";;
        test-gh-api-kf-file-accepts-octo)              test-gh-api-kf-file-accepts-octo "$@";;
        test-gh-api-kf-file-accepts-xxx)               test-gh-api-kf-file-accepts-xxx "$@";;
        test-gh-api-kf-data-accepts-none)               test-gh-api-kf-data-accepts-none "$@";;
        test-gh-api-kf-data-accepts-json)               test-gh-api-kf-data-accepts-json "$@";;
        test-gh-api-kf-data-accepts-xxx)                test-gh-api-kf-data-accepts-xxx "$@";;
        test-gh-api-kf-data-paging)                     test-gh-api-kf-data-paging "$@";;
        test-gh-api-kf-data-output-none)                test-gh-api-kf-data-output-none "$@";;
        test-gh-api-kf-data-output-absfilename)          test-gh-api-kf-data-output-absfilename "$@";;
        test-gh-api-kf-data-output-relfilename)          test-gh-api-kf-data-output-relfilename "$@";;
        test-gh-api-kf-data-output-absfolder)            test-gh-api-kf-data-output-absfolder "$@";;
        test-gh-api-kf-data-output-relfolder)            test-gh-api-kf-data-output-relfolder "$@";;
        test-gh-api-merge-pages)                        test-gh-api-merge-pages "$@";;
        test-gh-api-file-recover)                      test-gh-api-file-recover "$@";;
        test-gh-api-data-paginated)                    test-gh-api-data-paginated "$@";;
        test-ghr-download)                             test-ghr-download "$@";;
        test-ghr-download-output-none)                 test-ghr-download-output-none "$@";;
        test-ghr-download-output-absdir)               test-ghr-download-output-absdir "$@";;
        test-ghr-download-output-absfile)               test-ghr-download-output-absfile "$@";;
        test-ghr-download-version)                     test-ghr-download-version "$@";;
        test-ghr-download-version-nonexist)            test-ghr-download-version-nonexist "$@";;
        test-ghr-download-version-previous)            test-ghr-download-version-previous "$@";;
        test-gh-api-save-file-happy)              test-gh-api-save-file-happy "$@";;
        test-gh-api-save-file-collision)          test-gh-api-save-file-collision "$@";;
        test-gh-api-save-file-nosuchdir)          test-gh-api-save-file-nosuchdir "$@";;
        test-gh-api-save-file-dirambiguity)       test-gh-api-save-file-dirambiguity "$@";;
        *)                                 printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi





