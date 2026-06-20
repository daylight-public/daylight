#! /usr/bin/env bash


# Locate daylight.sh — sibling directory, then typical install path
SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
DAYLIGHT_SH="$SCRIPT_DIR/../daylight.sh"
for _c in "$DAYLIGHT_SH" /opt/bin/daylight.sh; do
    if [[ -f "$_c" ]]; then
        DAYLIGHT_SH=$_c
        break
    fi
done
[[ -f "$DAYLIGHT_SH" ]] || { printf 'Cannot find daylight.sh\n' >&2; exit 1; }

# Parse --token from global args
token_args=()
_positional=()
while (( $# > 0 )); do
    case $1 in
        --token) shift; token_args=(--token "$1") ;;
        -*)      printf 'Unknown flag: %s\n' "$1" >&2; exit 1 ;;
        *)       _positional+=("$1") ;;
    esac
    shift
done
set -- "${_positional[@]}"

command -v jq &>/dev/null || { printf 'jq is required but was not found\n' >&2; exit 1; }


#-------------------------------------------------------------------------------
#
# dl()
#
# @internal
# Shorthand for calling daylight.sh via case dispatch
#
dl()
{
    "$DAYLIGHT_SH" "$@"
}


#-------------------------------------------------------------------------------
#
# get-release-asset-name()
#
# Print the .tar.gz asset name for a given release tag
#
get-release-asset-name ()
{
    (( $# == 3 )) || { printf 'Usage: get-release-asset-name $org $repo $tag\n' >&2; return 1; }
    local org=$1 repo=$2 tag=$3

    local json
    json=$(dl github-release-get-data "${token_args[@]}" --version "$tag" "$org" "$repo") || return

    printf '%s' "$json" \
        | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .name' \
        | head -1
}


#-------------------------------------------------------------------------------
#
# list-nightly-tags()
#
# List all nightly release tags from a GitHub repo
#
list-nightly-tags ()
{
    (( $# == 2 )) || { printf 'Usage: list-nightly-tags $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2 page=1

    while true; do
        local json
        json=$(dl github-curl "${token_args[@]}" --per-page 100 \
            "/repos/$org/$repo/releases?page=$page") || return
        local tags
        tags=$(printf '%s' "$json" | jq -r '.[].tag_name' 2>/dev/null) || break
        [[ -n "$tags" ]] || break
        printf '%s\n' "$tags" | grep '^nightly-'
        (( page++ ))
    done
}


#-------------------------------------------------------------------------------
#
# verify-all-releases()
#
# Iterate all nightly releases and verify each; returns number of failures
#
verify-all-releases ()
{
    (( $# == 2 )) || { printf 'Usage: verify-all-releases $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2 total=0 passed=0 failed=0

    while IFS= read -r tag; do
        printf '=== %s ===\n' "$tag"
        (( total++ ))
        if verify-release "$org" "$repo" "$tag"; then
            (( passed++ ))
        else
            (( failed++ ))
        fi
    done < <(list-nightly-tags "$org" "$repo")

    printf '\n%d total, %d passed, %d failed\n' "$total" "$passed" "$failed"
    return "$failed"
}


#-------------------------------------------------------------------------------
#
# verify-release()
#
# Download and verify SHA256SUMS for a single release
#
verify-release ()
{
    (( $# == 3 )) || { printf 'Usage: verify-release $org $repo $tag\n' >&2; return 1; }
    local org=$1 repo=$2 tag=$3

    local tmpDir; tmpDir=$(mktemp -d) || return 1

    local assetName
    assetName=$(get-release-asset-name "$org" "$repo" "$tag") || {
        printf '  No .tar.gz asset for %s\n' "$tag" >&2
        rm -rf "$tmpDir"
        return 1
    }

    dl github-release-download "${token_args[@]}" --version "$tag" \
        "$org" "$repo" "$assetName" "$tmpDir" || {
        printf '  Failed to download %s\n' "$assetName" >&2
        rm -rf "$tmpDir"
        return 1
    }

    dl github-release-download "${token_args[@]}" --version "$tag" \
        "$org" "$repo" "SHA256SUMS" "$tmpDir" || {
        printf '  SHA256SUMS not found in %s\n' "$tag" >&2
        rm -rf "$tmpDir"
        return 1
    }

    local rc=0
    ( cd "$tmpDir" && grep -F "$assetName" SHA256SUMS | sha256sum -c - ) || rc=1
    rm -rf "$tmpDir"
    return "$rc"
}


#-------------------------------------------------------------------------------
#
# main()
#
# Dispatch command line arguments to the appropriate function
#
main ()
{
    if (( $# >= 1 )); then
        local cmd=$1
        shift
        case "$cmd" in
            get-release-asset-name)       get-release-asset-name "$@";;
            list-nightly-tags)            list-nightly-tags "$@";;
            verify-all-releases)          verify-all-releases "$@";;
            verify-release)               verify-release "$@";;
            *)                            verify-all-releases "$cmd" "$@";;
        esac
    fi
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
