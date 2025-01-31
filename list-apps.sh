#! /usr/bin/env bash
set -u

###
# To be a truly sweet app, this would need to either check for an app token, or create an app token
# using an app with Org Admin-Read permissions. I don't currently have a smooth way to try an existing
# token, fail, and then ask for another token. I think the app-create in day.sh might have something like that.
# For now, this defers to `github-curl`, which currently uses GITHUB_ACCESS_TOKEN, though that might change.
###
github-list-apps ()
{
    source './daylight.sh'

    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: list-apps.sh $org\n' >&2; return 1; }
    local org=$1

    local urlPath="/orgs/$org/installations"
    github-curl "$urlPath" | jq -r 'reduce .installations[] as $el({}; .[$el.app_slug] = {"id": $el.id, "permissions": $el.permissions})'
}

return 2>/dev/null || github-list-apps "$@"