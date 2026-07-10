

#-------------------------------------------------------------------------------
#
# gh-api()
#
# Make an authenticated request to the GitHub API. Pagination is automatic.
# All responses and headers are saved to a folder; the folder path is
# printed to stdout.
#
#
# flags
#       [--data]           POST data
#       [--output]         Output specifier
#       [--per-page]       Number of results to retrieve per page
#       [--token]          GitHub API token
#
# --output + --remote-name: last one wins (curl allows, does not define)
#
# positional args
#
#	$1	url
#
# Response shape auto-detection (first page):
#   type: array          -> key = "."
#   object + total_count -> key = array field
#   otherwise            -> key = ".items"
#
gh-api ()
{
    :
}



#-------------------------------------------------------------------------------
#
# gh-api_ ()
#
# Make an authenticated request to the GitHub API.
#
# Two calling forms:
#
#   gh-api_ "flagMap" "urlPath"     full form: flagMap for flags, urlPath for path
#   gh-api_ "/repos/org/repo"       shortcut: just the urlPath, no flags (public)
#
# flagMap uses keys:
#       [accept]         Accept header value
#       [data]           POST data
#       [per-page]       Results per page
#       [token]          GitHub API token
#
# $1  flagMap (assoc array) or urlPath (starts with /)
# $2  urlPath (required when $1 is a flagMap; ignored in shortcut mode)
#
gh-api_ ()
{
    local _urlPath
    local -a _curlFlags=()

    if [[ $1 == /* ]]; then
        # Shortcut: no flags, just urlPath
        _urlPath=${1#/}
    else
        local -n _flagMap=$1
        _urlPath=${2#/}
        gh-unparse-curl-args _flagMap _curlFlags
    fi

    local url="https://api.github.com/$_urlPath"

    # Per-page query parameter (must be set on the URL)
    if [[ -v _flagMap[per-page] ]]; then
        url+="?per_page=${_flagMap[per-page]}"
    fi

    curl "${_curlFlags[@]}" "$url"
}


#-------------------------------------------------------------------------------
#
# gh-parse-args()
#
# Translate CLI flags and positional args into a flagMap (associative array)
# and a positional arguments indexed array, suitable for passing to gh-api_
# or other kernel functions.
#
# Flags and positional args can be interleaved.  Anything that starts with
# -- is treated as a flag; everything else is a positional arg.
#
# Usage:
#   local -A flagMap=()
#   local -a posargs=()
#   gh-parse-args flagMap posargs "$@"
#
# Positional args:
#   $1  nameref to an associative array (flagMap)
#   $2  nameref to an indexed array (posargs)
#
gh-parse-args ()
{
    local -n _flagMap=$1
    local -n _posargs=$2
    shift 2

    # Check that _flagMap is an assoc array (follow nameref)
    [[ $(declare -p _flagMap 2>/dev/null) == "declare -A"* ]] \
    || [[ $(declare -p "${!_flagMap}" 2>/dev/null) == "declare -A"* ]] \
    || { printf "_flagMap is not an associative array\n" >&2; return 1; }

    # Check that _posargs is an indexed array (follow nameref)
    [[ $(declare -p _posargs 2>/dev/null) == "declare -a"* ]] \
    || [[ $(declare -p "${!_posargs}" 2>/dev/null) == "declare -a"* ]] \
    || { printf "_posargs is not an indexed array\n" >&2; return 1; }

    _flagMap=()
    _posargs=()

    while (( $# > 0 )); do
        case $1 in
            --accept|\
            --data|\
            --extract|\
            --output|\
            --output-dir|\
            --per-page|\
            --token|\
            --label|\
            --platform|\
            --version|\
            --workflow)
                (( $# >= 2 )) || { printf '%s specified but no value provided.\n' "$1" >&2; return 1; }
                _flagMap["${1##--}"]=$2
                shift 2
                ;;
            --remote-name)
                _flagMap[remote-name]=1
                shift
                ;;
            --)
                shift
                while (( $# > 0 )); do
                    _posargs+=("$1")
                    shift
                done
                break
                ;;
            --*)
                printf 'Unknown flag: %s\n' "$1" >&2
                return 1
                ;;
            *)
                # Not a flag — positional argument
                _posargs+=("$1")
                shift
                ;;
        esac
    done
}


#-------------------------------------------------------------------------------
#
# gh-unparse-curl-args()
#
# Translate a flagMap (from gh-parse-args) into an array of curl flags.
# Does not construct the URL — the caller passes it separately.
#
# Usage:
#   local -a curlFlags=()
#   gh-unparse-curl-args flagMap curlFlags
#   curl "${curlFlags[@]}" "https://api.github.com/$urlPath"
#
# Positional args:
#   $1  nameref to flagMap (assoc array from gh-parse-args)
#   $2  nameref to array for receiving curl flags
#
gh-unparse-curl-args ()
{
    local -n _flagMap=$1
    local -n _curlFlags=$2

    _curlFlags=()

    # Accept header
    if [[ -v _flagMap[accept] ]]; then
        _curlFlags+=(--header "Accept: ${_flagMap[accept]}")
    fi

    # Auth token
    if [[ -v _flagMap[token] ]]; then
        _curlFlags+=(--header "Authorization: Bearer ${_flagMap[token]}")
    fi

    # POST data
    if [[ -v _flagMap[data] ]]; then
        _curlFlags+=(--data "${_flagMap[data]}")
    fi
}
