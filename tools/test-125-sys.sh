#! /usr/bin/env bash


SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1



prompt_yn()
{
    local promptText=${1:-'Proceed?'}
    local response
    printf '  %s [y/N] ' "$promptText"
    read -r response
    [[ "$response" =~ ^[Yy] ]]
}


# Walk the user through an end-to-end system test of gh-api_.
# The caller provides the full command line as arguments:
#   bash test-125-sys.sh test-list-orgs --token abc /user/orgs
#
# Steps:
#   Parse args via gh-parse-args, confirm flagMap and posargs
#   Visual inspection of parsed data
#   Unparse to curl flags, user inspects
#   Execute curl, user verifies output
test-list-orgs ()
{
    # Resolve token from gh automatically — system test users are expected
    # to have gh installed and authenticated.
    local token
    token=$(gh auth token) || {
        printf '  FAIL: gh not available or not authenticated\n'
        return 1
    }

    # Caller provides path and optional flags; token is injected automatically.
    local -A flagMap=()
    local -a posargs=()
    gh-parse-args flagMap posargs --token "$token" "$@"

    # Confirm parsing results
    [[ -v flagMap[token] ]] || { printf '  FAIL: token not in flagMap\n'; return 1; }
    printf '  PASS (parse)\n'

    # Visual inspection of parsed data
    printf '  flagMap keys:\n'
    for key in "${!flagMap[@]}"; do
        printf '    [%s] = %s\n' "$key" "${flagMap[$key]}"
    done
    printf '  posargs:\n'
    for arg in "${posargs[@]}"; do
        printf '    %s\n' "$arg"
    done

    prompt_yn 'Proceed with unparse?' || { printf '  Aborted\n'; return 0; }

    # Unparse and display for visual inspection
    local -a curlFlags=()
    gh-unparse-curl-args flagMap curlFlags

    printf '  Unparsed flags:\n'
    for f in "${curlFlags[@]}"; do
        printf '    %s\n' "$f"
    done

    prompt_yn 'Proceed with curl?' || { printf '  Aborted\n'; return 0; }

    # Build URL from the first positional arg
    local url="https://api.github.com/organizations"

    # Display the full curl command
    printf '  curl call:\n'
    printf '    %s' "curl --fail-with-body --location --silent"
    for f in "${curlFlags[@]}"; do
        printf " '%s'" "$f"
    done
    printf " '%s'\n" "$url"

    prompt_yn 'Execute curl?' || { printf '  Aborted\n'; return 0; }

    # Execute the actual curl call
    curl --fail-with-body --location --silent "${curlFlags[@]}" "$url" || {
        printf '  FAIL: curl exited with error\n'
        return 1
    }

    printf '\n'
    prompt_yn 'Verify output. Looks OK?' || { printf '  FAIL: user rejected output\n'; return 1; }

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
