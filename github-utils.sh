# github-utils.sh -- generated from daylight.sh on Thu Jun 18 19:43:25 UTC 2026. Do not edit directly.

#-------------------------------------------------------------------------------
#
# github-app-get-client-id()
#
# Get the OAuth client ID for a GitHub App
#
github-app-get-client-id ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: github-app-get-id $appSlug\n' >&2; return 1; }
    local appSlug=$1

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    local -A info
    github-app-get-info "${flags[@]}" info "$appSlug" || return
    local clientId=${info[client_id]}
    printf '%s' "$clientId"
}

#-------------------------------------------------------------------------------
#
# github-app-get-data()
#
# Get GitHub App installation data from the API
#
github-app-get-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: github-app-get-data $appSlug\n' >&2; return 1; }
    local appSlug=$1

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    github-curl "${flags[@]}" "/apps/$appSlug" || return
}

#-------------------------------------------------------------------------------
#
# github-app-get-id()
#
# Get the ID of a GitHub App
#
github-app-get-id ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: github-app-get-id $appSlug\n' >&2; return 1; }
    local appSlug=$1

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    local -A info
    github-app-get-info "${flags[@]}" info "$appSlug" || return
    local id=${info[id]}
    printf '%s' "$id"
}

#-------------------------------------------------------------------------------
#
# github-app-get-info()
#
# Get detailed info about a GitHub App
#
github-app-get-info ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-app-get-data $infovar $appSlug\n' >&2; return 1; }
    local -n _info=$1
    local appSlug=$2

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    local tmpCurl; tmpCurl=$(mktemp --tmpdir curl.XXXXXX) || return
    github-app-get-data "${flags[@]}" "$appSlug" >"$tmpCurl" || return
    local tmpJq; tmpJq=$(mktemp --tmpdir jq.XXXXXX) || return
    jq -r '[.id, .client_id, .slug] | @tsv' <"$tmpCurl" >"$tmpJq" || return
    read -r -a args < "$tmpJq" || return

    _info[id]=${args[0]}
    _info[client_id]=${args[1]}
    # shellcheck disable=SC2154
    _info[slug]=${args[2]}
}

#-------------------------------------------------------------------------------
#
# github-create-flags()
#
# Create curl flags from a parsed argument map
#
github-create-flags ()
{
    # shellcheck disable=SC2016
    (( $# >=2 )) || { printf 'Usage: github-create-flags argmap flags [$flag1 $flag2 ... $flagn]\n' >&2; return 1; }
    # Check that argmap is either an assoc array or a nameref to an assoc array
    [[ $1 != argmap ]] && { local -n argmap; argmap=$1; }
    [[ $(declare -p argmap 2>/dev/null) == "declare -A"* ]] \
    || [[ $(declare -p "${!argmap}" 2>/dev/null) == "declare -A"* ]] \
    || { printf "%s is not an associative array, and it's not a nameref to an associative array either\n" "argmap" >&2; return 1; }
    # Check that flags is either an array or a nameref to an array
    [[ $2 != flags ]] && { local -n flags; argmap=$2; }
    [[ $(declare -p flags 2>/dev/null) == "declare -a"* ]] \
    || [[ $(declare -p "${!flags}" 2>/dev/null) == "declare -a"* ]] \
    || { printf "%s is not an array, and it's not a nameref to an array either\n" "flags" >&2; return 1; }

    flags=()
    local argname arg
    shift 2
    if (( $# == 0 )); then
        for argname in "${!argmap[@]}"; do
            arg=${argmap["$argname"]}
            flags+=("$argname" "$arg")
        done
    else
        while (( $# > 0 )); do
            argname=$1
            if [[ -v argmap["$argname"] ]]; then
                arg=${argmap["$argname"]}
                flags+=("--${argname}" "$arg")
            fi
            shift
        done
    fi
}

#-------------------------------------------------------------------------------
#
# github-create-url()
#
# Create a full GitHub API URL from a path
#
github-create-url ()
{
    local urlPath=$1
    local urlBase=${2:-'https://api.github.com'}

    # Trim leading slash
    if [[ $urlPath == /* ]]; then
        urlPath=${urlPath:1}
    fi
    # concatenate urlBase and Path
    local url="$urlBase/$urlPath"
    printf '%s' "$url" || return
}

#-------------------------------------------------------------------------------
#
# github-create-user-access-token()
#
# Create a GitHub user access token via API
#
github-create-user-access-token ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-create-user-access-token tokenvar $appslug\n' >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $1 != tokenvar ]] && { local -n tokenvar; tokenvar=$1; }
    local appSlug=$2

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    
    # Get the clientId for the dylt-cli GitHub App CLI, which must be installed 
    local clientId; clientId=$(github-app-get-client-id "${flags[@]}" "$appSlug") || return

    # Use client id to invoke device code flow
    flags+=(--data '')
    urlPath="/login/device/code?client_id=$clientId"
    urlBase="https://github.com"
    local -a args
    read -r -a args < <(github-curl "${flags[@]}" "$urlPath" "$urlBase" \
                        | jq -r '[.device_code, .user_code, .verification_uri] | @tsv') \
                        || { printf 'Call failed: github-curl()\n'; return; }
    local deviceCode=${args[0]}
    local userCode=${args[1]}
    local verificationUri=${args[2]}

    # Prompt user to do stuff in the browser
    echo
    printf '%-40s%s\n' "User Code" "$userCode"
    printf '%-40s%s\n' "Verification Uri" "$verificationUri"
    if command -v pbcopy >/dev/null; then
        printf '%s' "$userCode" | pbcopy
    fi
    if command -v open >/dev/null; then
        echo
        read -r -p "Hit <Enter> to open $verificationUri in your browser ..." _
        open "$verificationUri"
    fi
    echo
    
    # Post to the thing and grab the access token
    local prompt; prompt=$(printf 'Go to %s and enter %s. Then return here and press <Enter> ...' "$verificationUri" "$userCode") || return
    read -r -p  "$prompt" _
    local grantType='urn:ietf:params:oauth:grant-type:device_code'
    urlPath="$(printf '/login/oauth/access_token?client_id=%s&device_code=%s&grant_type=%s' "$clientId" "$deviceCode" "$grantType")"
    urlBase="https://github.com"
    read -r -a args < <(github-curl "${flags[@]}" "$urlPath" "$urlBase" \
                        | jq -r '[.access_token] | @tsv') \
                        || return
    # return the access token
    # shellcheck disable=SC2034
    tokenvar=${args[0]}
}

#-------------------------------------------------------------------------------
#
# github-curl()
#
# Make an authenticated request to the GitHub API
#
github-curl ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 1 && $# <= 2 )) || { printf 'Usage: github-curl [flags] $urlPath [$urlBase]\n' >&2; return 1; }
    local urlPath=${1##/} # Trim leading slash if necessary
    local urlBase=${2:-'https://api.github.com'}

    # Set headers to flag values or default
    local acceptDefault='application/vnd.github+json'
    local accept=${argmap[accept]:-$acceptDefault}
    local outputDefault='-'
    local output=${argmap[output]:-$outputDefault}
    # Set url and token, if present
    local url="$urlBase/$urlPath"
    # Can't really parameterize on token -- we need separate curl calls for with token, and without
    local -a flags=(--fail-with-body --location --silent)
    flags+=(--header "Accept: $accept")
    flags+=(--output "$output")
    [[ -v argmap[data] ]] && flags+=(--data "$(printf "'%s'" "${argmap[data]}")")
    local tokenVal
    if [[ -v argmap[token] ]]; then
        tokenVal=${argmap[token]}
    elif [[ -n "${GITHUB_TOKEN-}" ]]; then
        tokenVal=$GITHUB_TOKEN
    fi
    [[ -n "$tokenVal" ]] && flags+=(--header "Authorization: Bearer $tokenVal")
    curl "${flags[@]}" "$url" \
        || { printf 'curl failed inside github-curl\n' >&2; return 1; }
}

#-------------------------------------------------------------------------------
#
# github-curl-post()
#
# @deprecated
# Use github-curl with --data 'your-data'
#
github-curl-post ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: github-curl-post $urlPath $postData [$urlBase]\n' >&2; return 1; }
    local urlPath=${1##/} # Trim leading slash if necessary
    local postData=$2
    local urlBase=${3:-'https://api.github.com'}

    local acceptDefault='application/vnd.github+json'
    local accept=${argmap[accept]:-$acceptDefault}
    local outputDefault='-'
    local output=${argmap[output]:-$outputDefault}
    # Set url and token, if present
    local url="$urlBase/$urlPath"
    local token=${argmap[token]}
    # Can't really parameterize on token -- we need separate curl calls for with token, and without
    if [[ -n $token ]]; then
        curl --fail-with-body \
             --location \
             --silent \
             --data "'$postData'" \
             --header "Accept: $accept" \
             --header "Authorization: Token $token" \
             --output "$output" \
             "$url" \
        || return
    else
        curl --fail-with-body \
             --location \
             --silent \
             --data "'$postData'" \
             --header "Accept: $accept" \
             --output "$output" \
             "$url" \
        || return
    fi
}

#-------------------------------------------------------------------------------
#
# github-detect-platform()
#
# Detect the OS and architecture as a platform string
#
github-detect-platform ()
{
    (( $# == 0 )) || { printf 'Usage: github-detect-platform\n' >&2; return 1; }
    local os arch

    case "$(uname -s)" in
        Linux)                     os="linux" ;;
        Darwin)                    os="darwin" ;;
        MINGW*|MSYS*|CYGWIN*)     os="windows" ;;
        *) printf 'Unsupported OS: %s\n' "$(uname -s)" >&2; return 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)             arch="amd64" ;;
        aarch64|arm64)            arch="arm64" ;;
        armv7l|armv6l)            arch="arm" ;;
        *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; return 1 ;;
    esac

    printf '%s-%s' "$os" "$arch"
}

#-------------------------------------------------------------------------------
#
# github-download-latest-release()
#
# Download the latest release asset from a GitHub repository
#
github-download-latest-release ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: download-latest-release $org $repo $name $downloadFolder\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local downloadFolder=$4

    # Get release package data as assoc array
    local -A releaseInfo
    github-get-release-package-info releaseInfo "$org" "$repo" "$name" || return
    local url=${releaseInfo[url]}
    local accept='Accept: application/octet-stream'
    local output="$downloadFolder/$name"
    local token=${argmap[token]}
    if [[ -n $token ]]; then
        github-curl --token "$token" --accept "$accept" --output "$output"
    else
        github-curl --accept "$accept" --output "$output"
    fi
    printf '%s' "$releasePath"
}

#-------------------------------------------------------------------------------
#
# github-get-release-data()
#
# @deprecated
# Use github-release-get-data
#
github-get-release-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 4 )); } || { printf 'Usage: github-get-release-data [flags] $org $repo [$releaseTag [$platform]]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local tag=${3:-""}
    
    local urlPath; urlPath="$(github-get-releases-url-path "$org" "$repo" "$tag")" || return
	local tmpCurl; tmpCurl=$(create-temp-file github.get.release.data.json) || return
    # build argstring for github-curl
    local argstring=''
    [[ -n ${argmap[token]} ]] && argstring+="--token ${argmap[token]}"
    # github-curl -- note $argstring is unquoted
    github-curl "$argstring" "$urlPath" >"$tmpCurl" || return
	printf '%s' "$tmpCurl"
}

#-------------------------------------------------------------------------------
#
# github-get-release-name-list()
#
# @deprecated
# Use github-release-get-name-list
#
github-get-release-name-list ()
{
    # shellcheck disable=SC2016
    { (( $# >= 3 )) && (( $# <= 4 )); } || { printf 'Usage: github-get-release-name-list listVar $org $repo [$tag]\n' >&2; return 1; }
    local -n listVar; listVar=$1
    # ${@:2} skips the first two args, which are $0 and the $listVar nameref 
    local tmpCurl; tmpCurl=$(github-get-release-data "${@:2}") || return
    # shellcheck disable=SC2034
	local tmpJq; tmpJq=$(create-temp-file jq.get.release.name.list.txt) || return
	jq -r '[.assets[].name] | sort | @tsv' \
        <"$tmpCurl" \
        >"$tmpJq" \
        || return

	# shellcheck disable=SC2034
    read -r -a listVar <"$tmpJq" || return
}

#-------------------------------------------------------------------------------
#
# github-get-release-package-data()
#
# @deprecated
# Use github-release-get-package-data
#
github-get-release-package-data ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-release-package-data $org $repo $name\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3

    local urlPath; urlPath="$(github-get-releases-url-path "$org" "$repo")" || return
    local tmpCurl; tmpCurl="$(create-temp-file 'curl.release')" || return
    github-curl "$urlPath" >"$tmpCurl" || return
    local tmpJq; tmpJq="$(create-temp-file 'jq.release')" || return
    jq -r --arg name "$name" \
       '.assets[]
        | select(.name == $name)' \
      </"$tmpCurl" >/"$tmpJq" \
      || return 
    printf '%s' "$tmpJq"
}

#-------------------------------------------------------------------------------
#
# github-get-release-package-info()
#
# @deprecated
# Use github-release-get-package-info
#
github-get-release-package-info ()
{
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-get-release-package-info infovar $org $repo $name\n' >&2; return 1; }
    local -n info=$1
    local releaseDataPath; releaseDataPath=$(github-get-release-package-data "${@:2}") || return
    local tmpJq; tmpJq=$(create-temp-file 'jq.release.info') || return
    jq -r '[.id, .url, .browser_download_url] | @tsv' \
      <"$releaseDataPath" \
      >"$tmpJq" \
      || return
    local -a args
    read -r -a args <"$tmpJq" || return
    info[id]=${args[0]}
    info[url]=${args[1]}
    local browser_download_url=${args[2]}
    local filename=${browser_download_url##*/}
    info[browser_download_url]=$browser_download_url
    info[filename]=$filename
}

#-------------------------------------------------------------------------------
#
# github-parse-args()
#
# Parse common GitHub API arguments into an associative array
#
github-parse-args ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-parse-args infovar nargs [$args]\n' >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $1 != argmap ]] && { local -n argmap; argmap=$1; }
    # Check that argmap is either an assoc array or a nameref to an assoc array
    [[ $(declare -p argmap 2>/dev/null) == "declare -A"* ]] \
    || [[ $(declare -p "${!argmap}" 2>/dev/null) == "declare -A"* ]] \
    || { printf "%s is not an associative array, and it's not a nameref to an associative array either\n" "argmap" >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $2 != nargs ]] && { local -n nargs; nargs=$2; }

    nargs=0
    shift 2
    while (( $# > 0 )); do
        case $1 in
            '--accept'   |\
            '--data'     |\
            '--output'   |\
            '--token'    |\
            '--platform' |\
            '--version' \
            )
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                argmap["${1##--}"]=$2
                ((nargs+=2))
                shift 2
                ;;
            '--')
                shift
                ((nargs++))
                break
                ;;
            *)
                break
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
#
# github-release-create-url-path()
#
# Create a URL path for a GitHub release
#
github-release-create-url-path ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-release-create-url-path $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2

    local tag=${argmap[version]:-''}
    local urlPath
    if [[ -n "$tag" ]]; then
        local urlPath="/repos/$org/$repo/releases/tags/$tag"
    else
        local urlPath="/repos/$org/$repo/releases/latest"
    fi

    # printf with \n if interactive
    if [[ -t 0 ]]; then
        printf '%s\n' "$urlPath"
    else
        printf '%s' "$urlPath"
    fi
}

#-------------------------------------------------------------------------------
#
# github-release-download()
#
# Download a release asset from a GitHub repository
#
github-release-download ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-release-download $org $repo $releaseName $downloadFolder\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local downloadFolder=${4%%/}

    # Get release info
    local -a flags=()
    github-create-flags argmap flags token version
    local -A releaseInfo
    github-release-get-package-info "${flags[@]}" releaseInfo "$org" "$repo" "$name" || return
    # download release file using releaseInfo data
    local urlPath=${releaseInfo[urlPath]}
    local filename=${releaseInfo[filename]}
    local accept='Accept: application/octet-stream'
    local output="$downloadFolder/$filename"
    flags+=(--accept "$accept" --output "$output")
    github-curl "${flags[@]}" "$urlPath" || return
    printf '%s' "$output"
}

#-------------------------------------------------------------------------------
#
# github-release-download-latest()
#
# Download the latest release asset for a named package
#
github-release-download-latest ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-release-download-latest [$flags] $org $repo $name $downloadFolder\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local downloadFolder=${4%%/}

    local -a flags
    github-create-flags argmap flags token || return
    local version; version=$(github-release-get-latest-tag "${flags[@]}" "$org" "$repo") || return
    flags+=(--version "$version")
    github-release-download "${flags[@]}" "$org" "$repo" "$name" "$downloadFolder" || return
}

#-------------------------------------------------------------------------------
#
# github-release-get-data()
#
# Get release data from a GitHub repository
#
github-release-get-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    { (( $# >= 2 )) } || { printf 'Usage: github-release-get-data [flags] $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2
    
    local -a flags
    github-create-flags argmap flags version || return
    local urlPath; urlPath=$(github-release-create-url-path "${flags[@]}" "$org" "$repo") || return
    # build argstring for github-curl
    github-create-flags argmap flags token || return
    github-curl "${flags[@]}" "$urlPath" || return
}

#-------------------------------------------------------------------------------
#
# github-release-get-latest-tag()
#
# Get the latest release tag from a GitHub repo
#
github-release-get-latest-tag ()
{
    command -v "jq" >/dev/null || { printf '%s is required, but was not found.\n' "jq" >&2; return 1; }
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-get-latest-version [flags] $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2
    
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    
    releasesUrlPath=$(github-release-create-url-path "$org" "$repo")
    # build flags for github-curl
    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    # local VER; VER=$(github-curl "${flags[@]}" "$releasesUrlPath" \
                    #  | jq -r .tag_name)
    local tmpCurl; tmpCurl=$(mktemp --tmpdir curl.latest.tag.XXXXXX) || return
    github-curl "${flags[@]}" "$releasesUrlPath" >"$tmpCurl" || return
    local tmpJq; tmpJq=$(mktemp --tmpdir jq.latest.tag.XXXXXX) || return
    jq -r '.tag_name' <"$tmpCurl" >"$tmpJq" || return
    read -r tag < "$tmpJq" || return    
    
    printf '%s' "$tag"
}

#-------------------------------------------------------------------------------
#
# github-release-get-package-data()
#
# Get raw asset data for a named release package
#
github-release-get-package-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-release-get-package-data $org $repo $name\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3

    local -a flags
    github-create-flags argmap flags version token || return
    local urlPath; urlPath=$(github-release-create-url-path "${flags[@]}" "$org" "$repo") || return
    github-create-flags argmap flags token || return
    local tmpCurl; tmpCurl=$(mktemp --tmpdir curl.release.XXXXXX) || return
    github-curl "${flags[@]}" "$urlPath" >"$tmpCurl" || return
    jq -r --arg name "$name" \
       '.assets[]
        | select(.name == $name)' \
      <"$tmpCurl" \
      || return 
}

#-------------------------------------------------------------------------------
#
# github-release-get-package-info()
#
# Get structured package info for a named release asset
#
github-release-get-package-info ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-get-release-package-info infovar $org $repo $name\n' >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $1 != info ]] && { local -n info; info=$1; }
    local org=$2
    local repo=$3
    local name=$4

    # Call github-release-get-package-data and create/parse the necesary fields
    local -a flags=()
    github-create-flags argmap flags token version
    local -a fields=()
    read -r -a fields < <(github-release-get-package-data "${flags[@]}" "$org" "$repo" "$name" \
    | jq -r '
        [.browser_download_url,
         .content_type,
         (.browser_download_url | match(".*/(.*)").captures[0].string),
         .id,
         .name,
         .url,
         (.url | match("https://api.github.com/(.*)").captures[0].string)
        ] | @tsv' \
      || return)
    # Package fields into the info assoc array
    info[browser_download_url]=${fields[0]}
    info[content_type]=${fields[1]}
    info[filename]=${fields[2]}
    info[id]=${fields[3]}
    info[name]=${fields[4]}
    info[url]=${fields[5]}
    info[urlPath]=${fields[6]}
}

#-------------------------------------------------------------------------------
#
# github-release-install()
#
# Download and install a GitHub release asset
#
github-release-install ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 4 && $# <= 5 )) || { printf 'Usage: github-install-latest-release $org $repo $releaseName $installFolder [$downloadFolder]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local installFolder=$4
	local downloadFolder=${5:-$(create-temp-folder)}
	[[ -d "$downloadFolder" ]] || { echo "Non-existent folder: $downloadFolder" >&2; return 1; }
    local -a flags=()
    github-create-flags argmap flags token version
    local releasePath; releasePath=$(github-release-download "${flags[@]}" "$org" "$repo" "$name" "$downloadFolder") || return
    case "$releasePath" in
        *.tgz|*.tar.gz)
            tar --strip-components=1 -C "$installFolder" -xzf "$releasePath";;
        *)
            printf "Unsupported file type - can't install (%s)\n" "$releasePath" >&2
            return 1;;
    esac
	printf '%s' "$installFolder"
}

#-------------------------------------------------------------------------------
#
# github-release-install-latest()
#
# Install the latest release from a GitHub repo
#
# @note - github-release-install will install the latest by default, if you don't specify a version
#
github-release-install-latest ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 4 && $# <= 5 )) || { printf 'Usage: github-release-install-latest $org $repo $releaseName $installFolder [$downloadFolder]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local installFolder=$4
	local downloadFolder=${5:-''}

    local -a flags
    github-create-flags argmap flags token
    local version; version=$(github-release-get-latest-tag "${flags[@]}" "$org" "$repo") || return    
    flags+=(--version "$version")
    github-release-install "${flags[@]}" "$org" "$repo" "$releaseName" "$installFolder" "$downloadFolder"
}

#-------------------------------------------------------------------------------
#
# github-release-list()
#
# List releases for a GitHub repository
#
github-release-list ()
{
	# parse github args
	local -A argmap=()
	local nargs=0
	github-parse-args argmap nargs "$@"
	shift "$nargs"
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: github-release-list [flags] $org $repo\n' >&2; return 1; }
	local org=$1
	local repo=$2

	# get release name list, using token if provided
    local -a flags=()
	[[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
	github-release-get-data "${flags[@]}" "$org" "$repo" \
	| jq -r '[.assets[].name] | sort | @tsv' \
	|| return

}

#-------------------------------------------------------------------------------
#
# github-release-list-platforms()
#
# List available platforms for a release
#
github-release-list-platforms ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
	# shellcheck disable=SC2016
	(( $# = 2 )) || { printf 'Usage: github-release-list [flags] $org $repo\n' >&2; return 1; }
	local org=$1
	local repo=$2

	# get release name list, using token if provided
    readarray -t -d $'\t' releases < <(github-release-list "$@")
    local platform
    for release in "${releases[@]}"; do
        if [[ ! "$release" =~ checksums.txt ]]; then
            platform="${release##"${repo}"_}"
            platform="${platform%%.*}"
        	printf '%s\n' "$platform"
        fi
    done
}

#-------------------------------------------------------------------------------
#
# github-release-select()
#
# Select a release from a list of choices
#
github-release-select ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
	# shellcheck disable=SC2016
	(( $# == 3 )) || { printf 'Usage: github-release-select [flags] name $org $repo\n' >&2; return 1; }
	[[ $1 != 'name' ]] && local -n name=$1
	local org=$2
	local repo=$3

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
	IFS=$'\t' read -r -a names < <(github-release-list "${flags[@]}" "$org" "$repo") || return
	select name in "${names[@]}"; do break; done
}

#-------------------------------------------------------------------------------
#
# github-release-select-platform()
#
# Select a platform for a release download
#
github-release-select-platform ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
	# shellcheck disable=SC2016
	(( $# = 2 )) || { printf 'Usage: github-release-select-platforms [flags] $org $repo' >&2; return 1; }
    local platforms
    readarray -t -d $'\n' platforms < <(github-release-list-platforms "$@")
	select platform in "${platforms[@]}"; do
        printf '%s' "$platform" || return
        break
    done
}

#-------------------------------------------------------------------------------
#
# github-test-repo()
#
# Test if a GitHub repo exists
#
# Simple attempt to get info for a repo
# If it does not succeed, it could mean the org or repo are nonexistent or misspelled
# But it could also mean that the repo is non-public and requires a token for authentication
# The Github API returns 404s for all of the above, so the error status doesn't tell us anything
github-test-repo ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-test-repo $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2

    local urlPath="/repos/$org/$repo"
    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    # We don't care about the info, just if we can successfully call the endpoint
    github-curl "${flags[@]}" --output /dev/null "$urlPath" || return
}

# @deprecated - use github-test-repo and pass a token
#
#-------------------------------------------------------------------------------
#
# github-test-repo-with-auth()
#
# Test if a GitHub repo exists with authentication
#
# Simple attempt to get info for a repo
# If it does not succeed, it could mean the org or repo are nonexistent or misspelled
# But it could also mean that the repo is non-public and requires a token for authentication
# The Github API returns 404s for all of the above, so the error status doesn't tell us anything
github-test-repo-with-auth ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-test-repo-with-auth $org $repo $token\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local token=$3

    local urlPath="/repos/$org/$repo"
    # We don't care about the info, just if we can successfully call the endpoint
    github-curl --output /dev/null --token "$token" "$urlPath" || return
}

