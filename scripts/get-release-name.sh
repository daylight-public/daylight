#! /usr/bin/env bash

get-user-access-token ()
{
    declare -F github-curl >/dev/null || { printf 'Unknown function: %s\n' "github-curl"; return 1; }
    declare -F github-curl-post >/dev/null || { printf 'Unknown function: %s\n' "github-curl-post"; return 1; }
    
    # Get the clientId for the dylt-cli GitHub App CLI, which must be installed 
    local appSlug="dylt-cli"
    local urlPath="/apps/$appSlug"
    read -r clientId < <(github-curl "$urlPath" \
                         | jq -r '.client_id' \
                         || return \
                        )
    declare -p clientId

    # Use client id to invoke device code flow
    urlPath="/login/device/code?client_id=$clientId"
    urlBase="https://github.com"
    local -a args
    read -r -a args < <(github-curl-post "$urlPath" "" "$urlBase" \
                        | jq -r '[.device_code, .user_code, .verification_uri] | @tsv') \
                        || { printf 'Call failed: github-curl-post()\n'; return; }
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
    read -r -a args < <(github-curl-post "$urlPath" "" "$urlBase" \
                        | jq -r '[.access_token] | @tsv') \
                        || return
    # return the access token
    local accessToken=${args[0]}
    _GAT=$accessToken
}


# Auth is always hard. GitHub Auth is no exception.
#
# The hardest part of this whole operation is successfully auth'ing to GitHub.
# This is actually needed pretty early in the process, so we'll do it first.
#
# Authentication to GitHub will be done via a user access token.
# User Access Tokens are used to perform actions on behalf of a human user.
# They can be granularly scoped.
# They are associated with a GitHub App. The GitHub App restricts the permissions of the token.
# dylt-cli is a GitHub App that exists for this purpose.
# For the user to succesfully install a non-public app, they will either need to install dylt-cli
# or they will need to install an app with similar permissions.
#
# When running this script there are a few possible scenarios.
# The repo in question may be public, or not.
# An auth token does not exist, or is invalid, or is valid.
# Of these 2x3 scenarios, 3 are valid:
#   1. Public repo, no token
#   2. Public repo, valid token
#   3. Non-public repo, valid token
# 2 is somewhat interesting, in that invalid tokens will prevent operations even on public repos.
#
# init-access-token() is a bit like a state machine that determines our initial state from the 2x3 possibilities.
# It then either moves into an acceptable state or returns non-zero.
#
# As a final twist, if the repo is public, the user will have a chance to create a token anyway.
# Tokens establish identity, and identity supports traceability.
# 
# Basic flow
#
#   Test if public repo
#   if public
#       We're mostly all set here. But we still need to check if there's an invalid token present.
#       Also, in the absence of a valid token, we'll provide an opportunity to create one.
#       If this succeeds, we'll have a token
#       If not, we'll clear the token but still processed
#   else
#       We see if a token exists.
#       If so, we'll auth with it.
#       If successful, we're done
#       If not, we'll attempt to get a token.
#       If this succeeds, we'll have a token
#       If not, we'll return non-zero
#   fi
#


init-access-token ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: init-access-token $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2

    # See if we're able to access the repo without authentication
    # This will let us determine if the repo is public or not
    local isPublic
    if test-repo "$org" "$repo"; then
        isPublic=1
    else
        isPublic=0
    fi
    if (( isPublic == 1)); then
        # If no token exists, we don't need a token but we will ask anyway
        if [[ -z $_GAT ]]; then
            echo
            printf '%s/%s is a public repo, so you do not need to create an access token.\n' "$org" "$repo"
            echo
            local ynCreateToken
            yesno 'Would you like to create a token anyway? [yn] ' ynCreateToken
            if [[ ! ${ynCreateToken,,} =~ y|yes ]]; then
                # Public repo + no token = OK
                echo
                printf "No worries! You're all set.\n"
                echo "# Public repo + no token = OK"
                return 0
            elif github-create-user-access-token _GAT dylt-cli; then
                # Public repo + new token = OK
                echo "# Public repo + new token = OK"
                return 0
            else
                printf "No valid token was created, but no token is needed so you're all set.\n"
                echo 
                # Public repo + no token = OK
                echo "# Public repo + no token = OK"
                return 0
            fi
        elif test-repo-with-auth "$org" "$repo" "$_GAT"; then
            # Public repo + valid token = OK
            echo "# Public repo + valid token = OK"
            return 0
        else
            # The current token is invalid. The user can get a new one or the old one can be discarded.
            unset _GAT
            echo
            printf 'You have an existing token, but it is invalid. The invalid token will be discarded, and since this is public repo you can proceed.\n'
            echo
            local ynCreateToken
            yesno 'Would you like to create a new token? [yn] ' ynCreateToken
            if [[ ! ${yesno,,} =~ y|yes ]]; then
                # Public repo + no token = OK
                echo
                printf "No worries! You're all set.\n"
                echo "# Public repo + no token = OK"
                return 0
            elif github-create-user-access-token _GAT dylt-cli; then
                # Public repo + new token = OK
                echo "# Public repo + new token = OK"
                return 0
            else
                printf "No valid token was created, but no token is needed so you're all set.\n"
                echo 
                # Public repo + no token = OK
                echo "# Public repo + no token = OK"
                return 0
            fi
        fi
    else
        # If a token exists, we'll check if it's valid
        if [[ -n $_GAT ]]; then
            if test-repo-with-auth "$org" "$repo" "$_GAT"; then
                # Non-public repo + valid token = OK
                echo "# Non-public repo + valid token = OK"
                return 0
	    else
                # Invalid token - fall through to no-token case
                :
            fi
        elif github-create-user-access-token _GAT dylt-cli; then
            # Non-public repo + new token = OK
            echo "# Non-public repo + new token = OK"
            return 0
        fi
    fi
    # No successful case happened, so we assume failure
    echo "return 1"
    return 1
}


main ()
{
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: get-release-name.sh $org $repo [$tag]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    # local tag=${3:-''}

    init-access-token "$org" "$repo" || return
    declare -p _GAT
    
    # We've confirmed we can access this repo so let's get the list of release names for this tag
    declare -F github-get-release-name-list >/dev/null || { printf 'Unknown function: %s\n' "github-get-release-name-list"; return 1; }
    local -a names
    github-get-release-name-list names "$@" || return
    declare -p names
    local nNames=${#names[@]}
    # Print a formatted numbered list of all release names
    for (( i=0; i<nNames; ++i ))
        do printf '%-3d%-40s\n' $((i+1)) "${names[$i]}"
    done
    # Choose the number of a release to use - loop until a valid number is selected
    local prompt; prompt=$(printf 'Which release would you like to install (1-%d)? ' "$nNames")
    local releaseNum
    while  [[ -z $releaseNum || $releaseNum == *[!0123456789]* ]] || (( releaseNum < 1 || releaseNum > nNames )); do
        read -r -p "$prompt" releaseNum
    done
    # Get the release name from the selected number
    printf '%d is a nice release number\n' "$releaseNum"
    local releaseName=${names[(($releaseNum-1))]}
    printf 'releaseName=%s\n' "$releaseName"
}

# main "$@"
