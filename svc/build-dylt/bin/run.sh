#! /usr/bin/env bash

main ()
{
    local repoDir=/opt/svc/build-dylt/repo

    printf 'Updating dylt repo ...\n'
    cd "$repoDir" || { printf 'Repo dir %s not found\n' "$repoDir" >&2; exit 1; }
    git pull --ff-only origin main || {
        printf 'git pull failed — no new commits or network issue\n' >&2
        exit 1
    }

    printf 'Running nightly release ...\n'
    source ./sunbeam.sh || { printf 'Failed to source sunbeam.sh\n' >&2; exit 1; }

    local version
    version=$(git-get-latest-release-version dylt-dev dylt) || {
        printf 'Failed to get latest version\n' >&2
        exit 1
    }

    git-do-nightly-release "$version" || {
        printf 'Nightly release failed (likely no changes to push)\n' >&2
        exit 1
    }

    printf 'Done — tag pushed, goreleaser workflow triggered\n'
}

main "$@"
