#! /usr/bin/env bash


SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1



prompt_yn()
{
    local promptText=${1:-'Proceed?'}
    local response
    printf '  %s [Y/n] ' "$promptText"
    read -n 1 response
    echo
    [[ "$response" =~ ^[Yy]?$ ]]
}


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
    gh-parse-args flagMap posargs --token "$token"

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
    gh-unparse-curl-args flagMap curlFlags || { printf '  Aborted\n'; return 0; }

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
    prefix=$(ghapi-create-tmp-folder-prefix "$url") || { printf '  Aborted\n'; return 0; }
    local tmpFolder
    tmpFolder=$(mktemp -t --directory "$prefix") || { printf '  Aborted\n'; return 0; }
    printf '  Temp folder: %s\n' "$tmpFolder"
    prompt_yn 'temp folder look ok?' || { printf '  Aborted\n'; return 0; }
	echo

    # Display the full curl command
    printf '  curl call:\n'
    printf '    curl --fail-with-body --location --silent'
    printf " --dump-header '%s/headers.txt'" "$tmpFolder"
    for f in "${curlFlags[@]}"; do
        printf " '%s'" "$f"
    done
    printf " '%s'\n" "$url"

    prompt_yn 'Execute curl?' || { printf '  Aborted\n'; return 0; }
	echo

    # Execute the actual curl call
    curl --fail-with-body --location --silent \
        --dump-header "$tmpFolder/headers.txt" \
        "${curlFlags[@]}" "$url" || {
        printf '  FAIL: curl exited with error\n'
        return 1
    }

    printf '\n'
    prompt_yn 'Verify output. Looks OK?' || { printf '  FAIL: user rejected output\n'; return 1; }
	echo

	# list tmp folder contents after download
	ls -1 "$tmpFolder"
	echo
	prompt_yn "tmpFolder contents ($tmpFolder). Looks OK?" || { printf '  FAIL: user rejected output\n'; return 1; }
	echo

    printf '  PASS\n'
}


usage()
{
	printf 'Usage\n'
	printf '\t%s --flags posargs\n' test-list-orgs
	printf '\n'
}


main()
{
    case ${1:-} in
        test-list-orgs) shift; test-list-orgs "$@";;
        "")             usage "$@";;
        *)              printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
