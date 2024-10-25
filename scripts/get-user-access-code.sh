#! /usr/bin/env bash

main ()
{
    # shellcheck disable=SC2016
    { (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: get-user-access-token.sh [$appName]\n' >&2; return 1; }
    declare -F github-get-app-info >/dev/null || { printf 'Unknown function: %s\n' "github-get-app-info"; return 1; }
    declare -F github-get-device-code-info >/dev/null || { printf 'Unknown function: %s\n' "github-get-device-code-info"; return 1; }
    local appSlug
    if (( $# < 1)); then
        read -r -p "What GitHub app would you like a token for (eg dylt-releaseme)? " appSlug
    else
        appSlug=$1
    fi
    declare -p appSlug
    local -A appInfo
    github-get-app-info appInfo "$appSlug"
    declare -p appInfo

    local clientId=${appInfo['client_id']}
    local -A deviceCodeInfo
    github-get-device-code-info deviceCodeInfo "$clientId"
    declare -p deviceCodeInfo
}

main "$@"