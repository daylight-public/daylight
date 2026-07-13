#-------------------------------------------------------------------------------
#
# ghapi-create-tmp-folder-prefix()
#
# Create a temp-folder template prefix from a GitHub API URL or path.
# Drops protocol and domain, truncates each path segment to 8 characters,
# joins them with '.', and appends .XXXXXX.
#
#   ghapi-create-tmp-folder-prefix "/organizations"
#     →  organizat.XXXXXX
#
#   ghapi-create-tmp-folder-prefix "https://api.github.com/repos/etcd-io/etcd/releases"
#     →  repos.etcd-i.XXXXXX
#
ghapi-create-tmp-folder-prefix ()
{
    local input=$1
    local path

    # Strip protocol + domain if present
    path="${input#https://api.github.com}"

    # Strip leading and trailing slashes
    path="${path#/}"
    path="${path%/}"

    # Strip query string if present
    path="${path%%\?*}"

    # Fallback if path was empty after stripping
    if [[ -z "$path" ]]; then
        printf 'default.XXXXXX'
        if [[ -t 1 ]]; then
            printf '\n'
        fi
        return
    fi

    # Split on '/' using read -d '/', take first 8 chars of each segment,
    # join with '.'.  Append a trailing slash so last segment terminates.
    local prefix=''
    local segment
    while read -r -d '/' segment || [[ -n "$segment" ]]; do
        local slug="${segment:0:8}"
        if [[ -z "$prefix" ]]; then
            prefix="$slug"
        else
            prefix="$prefix.$slug"
        fi
    done <<< "$path/"

    printf 'ghapi.%s.XXXXXX' "$prefix"
    if [[ -t 1 ]]; then
        printf '\n'
    fi
}


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

    # create a temp folder for downloaded content
    local prefix
    prefix=$(ghapi-create-tmp-folder-prefix "$url") || { printf '  Aborted\n'; return 0; }
    local tmpFolder
    tmpFolder=$(mktemp -t --directory "$prefix") || { printf '  Aborted\n'; return 0; }

    # execute the actual curl call
    curl --fail-with-body \
         --location \
         --silent \
         --dump-header "$tmpFolder/headers.txt" \
         --output "$tmpFolder/response.txt" \
         "${curlFlags[@]}" "$url" || {
            printf '  FAIL: curl exited with error\n'
            return 1
    }

    # check if it's a download or not 
	hasCdHeader=$(lookup-content-disposition < "$tmpFolder/headers.txt" || return)

    if [[ -n "$hasCdHeader" ]]; then
        echo "this is a download"
    else
        echo "this is data"
    fi

    # check if it's a download
    #   Yes - get the file do its destination
    #   No - while next; do download-next-page
    #        concatenate responses
    #        write responses to stdout

    # Resolve output specifier if provided
#     if [[ -v _flagMap[output] ]]; then
#         resolve-output-spec "${_flagMap[output]}" _curlFlags || return
#     fi

#    local url="https://api.github.com/$_urlPath"
#    if [[ -v _flagMap[per-page] ]]; then
#        url+="?per_page=${_flagMap[per-page]}"
#    fi

#    curl --fail-with-body --location --silent "${_curlFlags[@]}" "$url"
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


#-------------------------------------------------------------------------------
#
# lookup-content-disposition()
#
# Read a headers file from stdin and extract the filename from the
# Content-Disposition header.  Internally uses lookup-header to find
# the raw header line, then parses the filename value from it.
#
# Content-Disposition values use the format defined in RFC 6266:
#
#   content-disposition: attachment; filename=etcd-v3.6.13-darwin-amd64.zip
#   content-disposition: attachment; filename="etcd-v3.6.13-darwin-amd64.zip"
#
# The filename may be quoted or unquoted.  This function tries the
# quoted form first (filename="..."), then falls back to unquoted
# (filename=... without whitespace or semicolons).  This mirrors how
# curl --remote-header-name parses Content-Disposition.
#
# Stdin:            a headers file in HTTP format
#
# Stdout:           the filename from Content-Disposition, or nothing
#                   if no matching header was found or no filename
#                   could be extracted
#
# Returns:          0   filename found and printed
#                   1   Content-Disposition header not found
#                   2   header found but no extractable filename
#
lookup-content-disposition ()
{
    # Use lookup-header to get the raw Content-Disposition line
    local line
    line=$(lookup-header 'content-disposition') || return 1

    local filename

    # Try quoted filename first:  filename="value"
    # This is the more common form in modern responses.
    if [[ "$line" =~ filename=\"([^\"]+)\" ]]; then
        filename="${BASH_REMATCH[1]}"

    # Fall back to unquoted:  filename=value
    # The value extends to the next semicolon, whitespace, or end of line.
    elif [[ "$line" =~ filename=([^\";[:space:]]+) ]]; then
        filename="${BASH_REMATCH[1]}"

    else
        return 2
    fi

    printf '%s' "$filename"
    if [[ -t 1 ]]; then
        printf '\n'
    fi
}


#-------------------
#
# lookup-header()
#
# Read a header file (as produced by curl --dump-header) from stdin and look
# up a header by name.  Returns the full header line on stdout.
#
# Positional args:  $1   header name to search for (case-insensitive)
#
# Stdin:            a headers file in HTTP format (CRLF line endings
#                   produced by curl --dump-header are handled)
#
# Stdout:           the matching header line, with trailing CRLF stripped,
#                   or nothing if not found
#
# Returns:          0   header found
#                   1   header not found
#
# How it works:
#   Reads stdin line by line.  For each line, strips the trailing CR
#   byte (\r) that curl --dump-header adds as part of CRLF line endings.
#   Both the search term and the line are lower-cased via bash's ${var,,}
#   parameter expansion to get a case-insensitive match.  The regex
#   /^name:.*/ anchors at the start — header names only appear at the
#   beginning of a line in HTTP header dumps, so no false matches.
#
# Edge cases:
#   Extra colon — if the user passes "content-type:" or "content-type",
#                 both work because the regex expects a colon anyway.
#   Arbitrary values — header values can contain colons, spaces, special
#                      characters; the (.*) capture handles them all.
#   CRLF endings — curl's --dump-header uses CRLF; the CR is stripped
#                  before matching and before printing.
#   Case mismatch — HTTP headers are case-insensitive by spec; ${,,}
#                   on both sides normalizes for comparison while
#                   preserving the original line for output.
#   Empty value — header: (with nothing after the colon) is a valid HTTP
#                 header; the regex matches and the line is printed.
#   Multiple matches — only the first match is returned, which matches
#                      curl's behavior (first header wins on duplicates).
#
lookup-header ()
{
    local headerName=$1
    local search="${headerName,,}"
    local line

	# confirm stdin is non-interactive / won't hang waiting for data
	[[ ! -t 0 ]] || { printf 'stdin cannot be a terminal\n'; return 1; }

	while IFS= read -r line; do
        line=${line%$'\r'}

        # Compare lower-cased to lower-cased (HTTP headers are
        # case-insensitive per RFC 7230).  The ${var,,} expansion
        # converts var to all lowercase.
        if [[ "${line,,}" =~ ^"$search":(.*) ]]; then
            printf '%s' "$line"
            return 0
        fi
    done

    return 1
}



#-------------------------------------------------------------------------------
#
# lookup-next-link()
#
# Read a headers file from stdin and extract the URL from the Link
# header with rel="next".  Internally uses lookup-header to find the
# raw header line, then parses the next-link URL from it.
#
# RFC 8288 Link header format:
#
#   link: <https://api.github.com/...?page=2>; rel="next",
#         <https://api.github.com/...?page=288>; rel="last"
#
# Whitespace around the semicolon is optional per the RFC.
#
# Stdin:            a headers file in HTTP format
#
# Stdout:           the next link URL, or nothing if no Link header
#                   or no rel="next" link was found
#
# Returns:          0   next link found and printed
#                   1   Link header not found
#                   2   header found but no rel="next" link
#
lookup-next-link ()
{
    local line
    line=$(lookup-header 'link') || return 1

    # Extract the URL angle bracket before ; rel="next"
    # Whitespace around ; is optional per RFC 8288: <url>;rel="next",
    # <url> ; rel="next", <url>; rel="next", etc.
    if [[ "$line" =~ \<([^\>]+)\>[[:space:]]*\;[[:space:]]*rel=\"next\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        if [[ -t 1 ]]; then
            printf '\n'
        fi
        return 0
    fi

    return 2
}


