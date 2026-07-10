

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
# Make an authenticated request to the GitHub API. Pagination is automatic.
# All responses and headers are saved to a folder; the folder path is
# printed to stdout.
#
# The output folder contains:
#   data.json                                 Merged items across all pages
#   $filename                                 Raw response (non-paginated)
#   $(filename minus ext).headers.txt         Response headers (non-paginated)
#   $filename.nnnnnn                          Raw response page N (paginated)
#   $(filename minus ext).headers.txt.nnnnnn  Headers page N (paginated)
#
# flags
#
# positional args
# 	$1		  assoc array of arguments
#
#
# assoc array elements
#       [data]           POST data
#       [output]         output path specifier
#       [per-page]       Results per page
#       [token]          GitHub API token
#
gh-api_ ()
{
    :
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
# Translate a flagMap + posargs (from gh-parse-args) into arrays suitable
# for passing to curl: an array of curl flags and an array of positional
# args (the URL).
#
# url-base defaults to https://api.github.com.  The URL is constructed from
# the first positional arg (url-path) prepended with the base URL.
#
# Usage:
#   local -a curlFlags=()
#   local -a curlPosArgs=()
#   gh-unparse-curl-args flagMap posargs curlFlags curlPosArgs
#   curl "${curlFlags[@]}" "${curlPosArgs[@]}"
#
# Positional args:
#   $1  nameref to flagMap (assoc array from gh-parse-args)
#   $2  nameref to posargs (indexed array from gh-parse-args)
#   $3  nameref to array for receiving curl flags
#   $4  nameref to array for receiving curl positional args (URL)
#
gh-unparse-curl-args ()
{
    local -n _flagMap=$1
    local -n _posargs=$2
    local -n _curlFlags=$3
    local -n _curlPosargs=$4

    _curlFlags=()
    _curlPosargs=()

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

    # Build the URL
    local urlBase='https://api.github.com'
    local urlPath=''

    if (( ${#_posargs[@]} >= 1 )); then
        urlPath="${_posargs[0]}"
    fi

    # Strip leading slash if present
    urlPath="${urlPath#/}"

    local url="$urlBase/$urlPath"

    # Append per-page query parameter
    if [[ -v _flagMap[per-page] ]]; then
        url+="?per_page=${_flagMap[per-page]}"
    fi

    _curlPosargs+=("$url")
}

# The output folder contains:
#   data.json                                 Merged items across all pages
#   $filename                                 Raw response (non-paginated)
#   $(filename minus ext).headers.txt         Response headers (non-paginated)
#   $filename.nnnnnn                          Raw response page N (paginated)
#   $(filename minus ext).headers.txt.nnnnnn  Headers page N (paginated)
