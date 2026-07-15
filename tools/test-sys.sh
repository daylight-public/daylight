#! /usr/bin/env bash


SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1



prompt_yn()
{
    local promptText=${1:-'Proceed?'}
    local response
    printf '  %s [Y/n] ' "$promptText"
    read -n 1 response
    echo
    [[ "$response" =~ ^[Yy]?$ ]]
}


# Walk through gh-api_ download path using dylt release asset (~900 bytes)
# Invoke:  bash test-125-sys.sh test-download-dylt
test-download-dylt ()
{
    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh not available or not authenticated\n'
        return 1
    }

    local -A flagMap=()
    flagMap[accept]='application/octet-stream'
    flagMap[token]="$token"

    printf '  flagMap keys:\n'
    for key in "${!flagMap[@]}"; do
        printf '    [%s] = %s\n' "$key" "${flagMap[$key]}"
    done

    local urlPath="/repos/dylt-dev/dylt/releases/assets/449914893"

    prompt_yn 'Proceed with unparse?' || { printf '  Aborted\n'; return 0; }
    echo

    local -a curlFlags=()
    gh-api-unparse-curl-args flagMap curlFlags || { printf '  Aborted\n'; return 0; }

    printf '  Unparsed flags:\n'
    for f in "${curlFlags[@]}"; do
        printf '    %s\n' "$f"
    done

    prompt_yn 'Proceed with curl?' || { printf '  Aborted\n'; return 0; }
    echo

    local prefix
    prefix=$(gh-api-create-tmp-folder-prefix "$urlPath") || { printf '  Aborted\n'; return 0; }
    local tmpFolder
    tmpFolder=$(mktemp -t --directory "$prefix") || { printf '  Aborted\n'; return 0; }
    printf '  Temp folder: %s\n' "$tmpFolder"

    local url="https://api.github.com/$urlPath"

    printf '  curl call:\n'
    printf '    curl --fail-with-body --location --silent'
    printf " --dump-header '%s/headers.txt' --output '%s/response.txt'" "$tmpFolder" "$tmpFolder"
    for f in "${curlFlags[@]}"; do
        printf " '%s'" "$f"
    done
    printf " '%s'\n" "$url"

    prompt_yn 'Execute curl?' || { printf '  Aborted\n'; return 0; }
    echo

    curl --fail-with-body --location --silent \
        --dump-header "$tmpFolder/headers.txt" \
        --output "$tmpFolder/response.txt" \
        "${curlFlags[@]}" "$url" || {
        printf '  FAIL: curl exited with error\n'
        return 1
    }

    ls -1 "$tmpFolder"
    echo
    prompt_yn "tmpFolder contents ($tmpFolder). Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
    echo

    local headersPath="$tmpFolder/headers.txt"
    [[ -f "$headersPath" ]] || { printf '  FAIL: headers file not found\n'; return 1; }
    echo "headers file contents"
    echo
    cat "$headersPath"
    echo
    prompt_yn "headers file. Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
    echo

    hasCd=$(gh-api-lookup-content-disposition < "$tmpFolder/headers.txt")
    hasNext=$(gh-api-lookup-next-link < "$tmpFolder/headers.txt")
    printf '%-32s %s\n' "Has CD Header" "$hasCd"
    printf '%-32s %s\n' "Has Next Link" "$hasNext"
    echo
    prompt_yn "response facts. Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
    echo

    printf '  PASS\n'
}


# Walk the user through an end-to-end system test of gh-api_.
# This function tests a single known endpoint with the token resolved
# automatically from gh auth token.
# Invoke:  bash test-125-sys.sh test-list-orgs





# Walk the user through an end-to-end system test of gh-api_.
# This function tests a single known endpoint with the token resolved
# automatically from gh auth token.
# Invoke:  bash test-125-sys.sh test-list-orgs
test-list-orgs ()
{
    # Resolve token from gh automatically — system test users are expected
    # to have gh installed and authenticated.
    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh not available or not authenticated\n'
        return 1
    }

    local -A flagMap=()
    local -a posargs=()
    gh-api-parse-args flagMap posargs --token "$token"

    # Confirm parsing results
    [[ -v flagMap[token] ]] || { printf '  FAIL: token not in flagMap\n'; return 1; }
    printf '  PASS (parse)\n'

    # Visual inspection of parsed data
    printf '  flagMap keys:\n'
    for key in "${!flagMap[@]}"; do
        printf '    [%s] = %s\n' "$key" "${flagMap[$key]}"
    done

    prompt_yn 'Proceed with unparse?' || { printf '  Aborted\n'; return 0; }
	echo

    # Unparse and display for visual inspection
    local -a curlFlags=()
    gh-api-unparse-curl-args flagMap curlFlags || { printf '  Aborted\n'; return 0; }

    printf '  Unparsed flags:\n'
    for f in "${curlFlags[@]}"; do
        printf '    %s\n' "$f"
    done

    prompt_yn 'Proceed with curl?' || { printf '  Aborted\n'; return 0; }
	echo

    # Hardcoded URL path — this test exercises a specific endpoint
    local url="https://api.github.com/organizations"

    # Create temp folder for header dumps
    local prefix
    prefix=$(gh-api-create-tmp-folder-prefix "$url") || { printf '  Aborted\n'; return 0; }
    local tmpFolder
    tmpFolder=$(mktemp -t --directory "$prefix") || { printf '  Aborted\n'; return 0; }
    printf '  Temp folder: %s\n' "$tmpFolder"
    prompt_yn 'temp folder look ok?' || { printf '  Aborted\n'; return 0; }
	echo

    # Display the full curl command
    printf '  curl call:\n'
    printf '    curl --fail-with-body --location --silent'
    printf " --dump-header '%s/headers.txt' --output '%s/response.txt'" "$tmpFolder" "$tmpFolder"
    for f in "${curlFlags[@]}"; do
        printf " '%s'" "$f"
    done
    printf " '%s'\n" "$url"

    prompt_yn 'Execute curl?' || { printf '  Aborted\n'; return 0; }
	echo

    # Execute the actual curl call
    curl --fail-with-body --location --silent \
        --dump-header "$tmpFolder/headers.txt" \
        --output "$tmpFolder/response.txt" \
        "${curlFlags[@]}" "$url" || {
        printf '  FAIL: curl exited with error\n'
        return 1
    }

	# list tmp folder contents after download
	ls -1 "$tmpFolder"
	echo
	prompt_yn "tmpFolder contents ($tmpFolder). Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
	echo

    printf '  PASS\n'
	
	# cat headers file
	local headersPath="$tmpFolder/headers.txt"
	[[ -f "$headersPath" ]] || { printf 'headers file not found (%s)\n' "$headersPath"; return 1; }
	echo "headers file contents"
	echo
	cat "$headersPath"
	echo
	prompt_yn "headers file. Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
	echo

	# cat response file
	local responsePath="$tmpFolder/response.txt"
	[[ -f "$responsePath" ]] || { printf 'response file not found (%s)\n' "$responsePath"; return 1; }
	echo "response file contents"
	echo
	cat "$responsePath"
	echo
	prompt_yn "response file. Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
	echo

	# show status of download
	hasCdHeader=$(gh-api-lookup-content-disposition < "$tmpFolder/headers.txt")
	hasNextLink=$(gh-api-lookup-next-link < "$tmpFolder/headers.txt")
	printf '%-32s %s\n' "Has CD Header" "$hasCdHeader"
	printf '%-32s %s\n' "Has Next Link" "$hasNextLink"
	echo
	prompt_yn "response facts. Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
	echo


    printf '  PASS\n'
}


test-download-release-version ()
{
    local orgRepo=$1
    [[ -n "$orgRepo" ]] || { printf 'Usage: test-download-release-version <org/repo>\n' >&2; return 1; }

    local token
    token=$(gh auth token) || { printf '  FAIL: gh not available or not authenticated\n'; return 1; }

    printf 'Step 1: Listing releases for %s\n' "$orgRepo"
    prompt_yn 'Proceed?' || { printf '  Aborted\n'; return 0; }

    local tags
    tags=$(ghr-list --token "$token" "$orgRepo") || { printf '  FAIL: ghr-list failed\n'; return 1; }
    local firstTag
    firstTag=$(head -1 <<< "$tags")
    printf '  First release: %s\n' "$firstTag"

    local org="${orgRepo%%/*}"
    local repo="${orgRepo##*/}"

    printf '\nStep 2: Downloading %s with ghr-download\n' "$firstTag"
    prompt_yn 'Proceed?' || { printf '  Aborted\n'; return 0; }

    local output
    output=$(ghr-download --token "$token" --version "$firstTag" "$org" "$repo") || {
        printf '  FAIL: ghr-download failed\n'; return 1
    }
    printf '  Downloaded: %s\n' "$output"
    printf '  PASS\n'
}


usage()
{
	printf 'Usage\n'
	printf '\t%s --flags posargs\n' test-list-orgs
	printf '\t%s <org/repo>\n' test-download-release-version
	printf '\n'
}


main()
{
    case ${1:-} in
        test-download-dylt) shift; test-download-dylt "$@";;
        test-list-orgs) shift; test-list-orgs "$@";;
        test-download-release-version) shift; test-download-release-version "$@";;
        "")             usage "$@";;
        *)              printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
