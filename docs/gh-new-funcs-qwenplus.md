# gh-curl and ghr-list

## gh-curl

```bash
#-------------------------------------------------------------------------------
#
# gh-curl()
#
# Make an authenticated request to the GitHub API. Pagination is automatic.
# All responses and headers are saved to a folder; the folder path is
# printed to stdout.
#
# The output folder contains:
#   data.json                       Merged items across all pages
#   $filename                       Raw response (non-paginated)
#   $(filename minus ext).headers.txt  Response headers (non-paginated)
#   $filename.nnnnnn                Raw response page N (paginated)
#   $(filename minus ext).headers.txt.nnnnnn  Headers page N (paginated)
#
# Flags (emulated, not passed to curl):
#       [--output]         Full path to output file
#       [--output-dir]     Output folder
#       [--remote-name]    Derive filename from Content-Disposition
#       [--accept]         Accept header value
#       [--data]           POST data
#       [--per-page]       Results per page (max 100)
#       [--token]          GitHub API token
#
# --output + --remote-name: last one wins (curl allows, does not define)
#
# Positional args: $urlPath [$urlBase]
#
# Response shape auto-detection (first page):
#   type: array          -> key = "."
#   object + total_count -> key = array field
#   otherwise            -> key = ".items"
#
gh-curl ()
{
    # ---------------------------------------------------------------
    # Parse flags
    # ---------------------------------------------------------------
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 1 && $# <= 2 )) || { printf 'Usage: gh-curl [flags] $urlPath [$urlBase]\n' >&2; return 1; }
    local urlPath=${1##/}
    local urlBase=${2:-'https://api.github.com'}

    # ---------------------------------------------------------------
    # Resolve --output / --output-dir / --remote-name
    # ---------------------------------------------------------------
    # We emulate these flags ourselves — never pass them to curl.
    # --output + --remote-name: last one wins.
    # github-curl-parse-args processes flags left-to-right, so we
    # track which was specified last.
    local userFolder=''
    local userFilename=''
    local lastOutputFlag=''   # 'output' or 'remote-name'

    if [[ -v argmap[output] ]]; then
        lastOutputFlag='output'
        local outSpec="${argmap[output]}"
        if [[ "$outSpec" == */* ]]; then
            userFolder="${outSpec%/*}"
            userFilename="${outSpec##*/}"
        else
            userFilename="$outSpec"
        fi
    fi
    if [[ -v argmap[output-dir] ]]; then
        userFolder="${argmap[output-dir]}"
    fi
    if [[ -v argmap[remote-name] ]]; then
        lastOutputFlag='remote-name'
    fi

    # If --remote-name was last, ignore --output filename
    if [[ "$lastOutputFlag" == 'remote-name' ]]; then
        userFilename=''
    fi

    # ---------------------------------------------------------------
    # Build URL and curl flags
    # ---------------------------------------------------------------
    local acceptDefault='application/vnd.github+json'
    local accept=${argmap[accept]:-$acceptDefault}

    local url="$urlBase/$urlPath"
    if [[ -v argmap[per-page] ]]; then
        local pageSize=${argmap[per-page]}
        if [[ $url == *\?* ]]; then url+="&per_page=$pageSize"
        else url+="?per_page=$pageSize"
        fi
    fi

    local -a curlFlags=(--fail-with-body --location --silent)
    curlFlags+=(--header "Accept: $accept")
    [[ -v argmap[data] ]] && curlFlags+=(--data "${argmap[data]}")

    # Resolve auth token
    local tokenVal
    if [[ -v argmap[token] ]]; then
        tokenVal=${argmap[token]}
    elif [[ -n "${GITHUB_TOKEN-}" ]]; then
        tokenVal=$GITHUB_TOKEN
    elif [[ -n "${GH_TOKEN-}" ]]; then
        tokenVal=$GH_TOKEN
    elif type gh &>/dev/null; then
        tokenVal=$(gh auth token 2>/dev/null) || tokenVal=''
    fi
    [[ -n "$tokenVal" ]] && curlFlags+=(--header "Authorization: Bearer $tokenVal")

    # ---------------------------------------------------------------
    # Derive temp folder prefix from URL path
    # ---------------------------------------------------------------
    # /repos/$org/$repo/releases -> $org.$repo.releases
    # /search/repositories       -> search.repositories
    local prefix="${urlPath#/repos/}"
    prefix="${prefix//\//.}"

    # ---------------------------------------------------------------
    # Create temp output folder (always, even if user specified a folder)
    # ---------------------------------------------------------------
    local tempFolder
    tempFolder=$(create-temp-folder "ghcurl.$prefix") || return

    # Sibling temp files for every download (fixed names, overwritten each page)
    local tmpHeaders="$tempFolder.headers.txt"
    local tmpBody="$tempFolder.response"

    # ---------------------------------------------------------------
    # Pagination state
    # ---------------------------------------------------------------
    local paginateKey='.'
    local keyDetected=false
    local morePages=true
    local isPaginated=false
    local page=0
    local currentUrl="$url"

    # ---------------------------------------------------------------
    # Main download loop
    # ---------------------------------------------------------------
    while $morePages; do
        # Download this page to sibling temp files
        curl "${curlFlags[@]}" \
            --dump-header "$tmpHeaders" \
            --output "$tmpBody" \
            "$currentUrl" \
            || { printf 'gh-curl: page %d failed\n' $((page + 1)) >&2; break; }

        ((page++))

        # ---------------------------------------------------------------
        # Auto-detect paginateKey from first page response shape
        # ---------------------------------------------------------------
        if ! $keyDetected; then
            if jq -e 'type == "array"' "$tmpBody" >/dev/null 2>&1; then
                paginateKey='.'
            elif jq -e 'type == "object" and has("total_count")' "$tmpBody" >/dev/null 2>&1; then
                paginateKey=$(jq -r '
                    to_entries |
                    map(select(.value | type == "array") | "." + .key) |
                    first // ".items"
                ' "$tmpBody")
            else
                paginateKey='.items'
            fi
            keyDetected=true
        fi

        # ---------------------------------------------------------------
        # Determine filename from Content-Disposition header
        # (always re-check — it could change between pages)
        # ---------------------------------------------------------------
        local filename=''
        while IFS= read -r hdrLine; do
            hdrLine=${hdrLine%$'\r'}
            if [[ "${hdrLine,,}" =~ ^content-disposition:[[:space:]]*attachment\;[[:space:]]*filename=\"?([^\";[:space:]]+)\"? ]]; then
                filename="${BASH_REMATCH[1]}"
                break
            fi
        done < "$tmpHeaders"

        # Fallback: rightmost URL path segment
        if [[ -z "$filename" ]]; then
            filename="${currentUrl##*/}"
            filename="${filename%%\?*}"
        fi

        # Override with user-specified filename if --output was given
        if [[ -n "$userFilename" ]]; then
            filename="$userFilename"
        fi

        # ---------------------------------------------------------------
        # Determine page numbering
        # ---------------------------------------------------------------
        local headerStem="${filename%.*}"
        local pageStr=''

        if (( page == 1 )); then
            # First page: check if paginated
            isPaginated=false
            if jq -e '.incomplete_results == true' "$tmpBody" >/dev/null 2>&1; then
                isPaginated=true
            else
                while IFS= read -r hdrLine; do
                    hdrLine=${hdrLine%$'\r'}
                    if [[ "${hdrLine,,}" =~ \<([^\>]*)\>[[:space:]]*\;[[:space:]]*rel=\"next\" ]]; then
                        currentUrl="${BASH_REMATCH[1]}"
                        isPaginated=true
                        break
                    fi
                done < "$tmpHeaders"
            fi
            if $isPaginated; then
                pageStr='000001'
            fi
        else
            # Subsequent pages always numbered
            printf -v pageStr '%06d' "$page"
            # Parse rel="next" for next iteration
            currentUrl=''
            while IFS= read -r hdrLine; do
                hdrLine=${hdrLine%$'\r'}
                if [[ "${hdrLine,,}" =~ \<([^\>]*)\>[[:space:]]*\;[[:space:]]*rel=\"next\" ]]; then
                    currentUrl="${BASH_REMATCH[1]}"
                    break
                fi
            done < "$tmpHeaders"
        fi

        # ---------------------------------------------------------------
        # Move temp files into tempFolder with final names
        # ---------------------------------------------------------------
        if [[ -n "$pageStr" ]]; then
            mv "$tmpBody"    "$tempFolder/$filename.$pageStr"
            mv "$tmpHeaders" "$tempFolder/$headerStem.headers.txt.$pageStr"
        else
            mv "$tmpBody"    "$tempFolder/$filename"
            mv "$tmpHeaders" "$tempFolder/$headerStem.headers.txt"
        fi

        # ---------------------------------------------------------------
        # Determine if there are more pages
        # ---------------------------------------------------------------
        if (( page == 1 )) && $isPaginated; then
            morePages=true
        elif [[ -n "$currentUrl" ]]; then
            morePages=true
        else
            morePages=false
        fi
    done

    # ---------------------------------------------------------------
    # Build data.json from all response files
    # ---------------------------------------------------------------
    local -a respFiles=()
    local f
    shopt -s nullglob
    for f in "$tempFolder"/*; do
        # Skip headers files
        [[ "$f" == *.headers.txt* ]] && continue
        # Skip data.json itself (in case of re-run)
        [[ "$f" == */data.json ]] && continue
        respFiles+=("$f")
    done
    shopt -u nullglob

    if (( ${#respFiles[@]} == 1 )); then
        jq "$paginateKey" "${respFiles[0]}" > "$tempFolder/data.json" 2>/dev/null
    elif (( ${#respFiles[@]} > 1 )); then
        for f in "${respFiles[@]}"; do
            jq "$paginateKey" "$f"
        done | jq -s 'add' > "$tempFolder/data.json" 2>/dev/null
    fi

    # ---------------------------------------------------------------
    # Move to user-specified folder if needed, then print output path
    # ---------------------------------------------------------------
    if [[ -n "$userFolder" ]]; then
        mkdir -p "$userFolder" || return
        shopt -s dotglob
        mv "$tempFolder"/* "$userFolder"/ 2>/dev/null
        shopt -u dotglob
        rmdir "$tempFolder" 2>/dev/null
        printf '%s' "$userFolder"
    else
        printf '%s' "$tempFolder"
    fi
}
```

## ghr-list

```bash
#-------------------------------------------------------------------------------
#
# ghr-list()
#
# List release version tags for a GitHub repository.
# Delegates to gh-curl which handles pagination, file naming, and
# folder management automatically.
#
# Flags (passed through to gh-curl):
#       [--output]         Response filename override
#       [--output-dir]     Output folder override
#       [--remote-name]    Derive filename from Content-Disposition
#       [--token]          Auth token for non-public repos
#
# Positional args: $org/$repo
#
# Output: one tag_name per line
#
ghr-list ()
{
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 1 )) || { printf 'Usage: ghr-list $org/$repo\n' >&2; return 1; }

    # Use ghr-path to validate org/repo and get the list endpoint
    local listPath
    listPath=$(ghr-path "$1") || return

    local -a flags=()
    [[ -v argmap[output] ]] && flags+=(--output "${argmap[output]}")
    [[ -v argmap[output-dir] ]] && flags+=(--output-dir "${argmap[output-dir]}")
    [[ -v argmap[remote-name] ]] && flags+=(--remote-name)
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")

    local folder
    folder=$(gh-curl "${flags[@]}" "$listPath") || {
        printf 'gh-curl failed for %s\n' "$1" >&2
        return 1
    }
    jq -r '.[].tag_name' "$folder/data.json"
}
```
