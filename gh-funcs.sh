

#-------------------------------------------------------------------------------
#
# gh-api()
#
# Make an authenticated request to the GitHub API.
#
# flags
#       [--data]           POST data
#       [--output]         Output specifier
#       [--per-page]       Number of results to retrieve per page
#       [--token]          GitHub API token
#
# positional args
#
#	$1	url
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
# Requires a flagMap (associative array) and a urlPath.
# Even for public endpoints with no flags, pass an empty flagMap.
#
# Call:  gh-api_ "flagMap" "urlPath"
#
# flagMap uses keys:
#       [accept]         Accept header value
#       [data]           POST data
#       [per-page]       Results per page
#       [token]          GitHub API token
#
gh-api_ ()
{
    local -n _flagMap=$1
    local _urlPath=${2#/}
    local -a _curlFlags=()

    gh-unparse-curl-args _flagMap _curlFlags

    # Resolve output specifier if provided
    if [[ -v _flagMap[output] ]]; then
        resolve-output-spec "${_flagMap[output]}" _curlFlags || return
    fi

    local url="https://api.github.com/$_urlPath"
    if [[ -v _flagMap[per-page] ]]; then
        url+="?per_page=${_flagMap[per-page]}"
    fi

    curl --fail-with-body --location --silent "${_curlFlags[@]}" "$url"
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
# Handles flagMap keys:
#       [accept]   → --header "Accept: ..."
#       [token]    → --header "Authorization: Bearer ..."
#       [data]     → --data "..."
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


#-------------------------------------------------------------------------------
#
# resolve-output-spec()
#
# Translate an --output flagMap value into the corresponding curl flags
# for controlling where the response body is saved.
#
# Semantics per the gh-funcs design doc:
#
#   empty              → --remote-name                 (current dir, CD naming)
#   ends with /        → directory mode                (fail if dir missing)
#   is existing dir    → directory mode, no slash      (fail if dir missing)
#   is existing file   → fail (no clobber)
#   else               → file mode                     (parent dir must exist)
#
# Positional args:
#   $1  output value from flagMap (or empty string)
#   $2  nameref to array for receiving curl flags
#
resolve-output-spec ()
{
    local outputValue=$1
    local -n _curlFlags=$2

    if [[ -z "$outputValue" ]]; then
        # No output specified — use remote name
        _curlFlags+=(--remote-name)
        return
    fi

    # Strip trailing slash for consistent checks, but remember
    # whether one was provided (explicit directory indicator).
    local explicitDir=false
    if [[ "$outputValue" == */ ]]; then
        explicitDir=true
        outputValue="${outputValue%/}"
    fi

    if $explicitDir; then
        # Ends with / — explicit directory mode
        if [[ ! -d "$outputValue" ]]; then
            printf 'resolve-output-spec: directory does not exist: %s\n' "$outputValue" >&2
            return 1
        fi
        _curlFlags+=(--output-dir "$outputValue" --remote-name)
        return
    fi

    if [[ -d "$outputValue" ]]; then
        # Existing directory, no trailing slash
        _curlFlags+=(--output-dir "$outputValue" --remote-name)
        return
    fi

    if [[ -e "$outputValue" ]]; then
        # File already exists — no clobber
        printf 'resolve-output-spec: file already exists: %s\n' "$outputValue" >&2
        return 1
    fi

    # File mode — parent directory must exist
    local parentDir
    parentDir=$(dirname "$outputValue")
    if [[ ! -d "$parentDir" ]]; then
        printf 'resolve-output-spec: parent directory does not exist: %s\n' "$parentDir" >&2
        return 1
    fi

    _curlFlags+=(--output "$outputValue")
}
