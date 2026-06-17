#! /usr/bin/env bash

main ()
{
    printf '%s\n' "Checking for daylight.sh update ..."
    local installPath=/opt/bin/daylight.sh

    local installFolder; installFolder=$(dirname "$installPath")
    if [[ ! -d $installFolder ]]; then
        printf 'Folder %s does not exist — creating it\n' "$installFolder" >&2
        mkdir -p "$installFolder" || { printf 'Failed to create %s\n' "$installFolder" >&2; exit 1; }
    fi

    local tmpDir; tmpDir=$(mktemp -d) || { printf 'Failed to create temp dir\n' >&2; exit 1; }
    local tmpFile="$tmpDir/daylight.sh"
    local url=https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
    curl --silent --location --output "$tmpFile" "$url" || {
        local rc=$?
        printf 'Failed to download daylight.sh (exit %d)\n' $rc >&2
        rm -rf "$tmpDir"
        exit $rc
    }

    bash -n "$tmpFile" || {
        printf 'Syntax check FAILED — not installing corrupted download\n' >&2
        rm -rf "$tmpDir"
        exit 1
    }

    if [[ -f "$installPath" ]]; then
        if diff -q "$tmpFile" "$installPath" >/dev/null 2>&1; then
            printf 'Already up to date — no changes\n'
            rm -rf "$tmpDir"
            exit 0
        fi
        printf 'Changes detected\n'
    else
        printf 'No existing daylight.sh found — installing\n'
    fi

    cp "$tmpFile" "$installPath" || {
        printf 'Failed to copy to %s\n' "$installPath" >&2
        rm -rf "$tmpDir"
        exit 1
    }
    chmod 755 "$installPath"
    rm -rf "$tmpDir"
    printf 'Done — installed %s\n' "$installPath"
}

main "$@"
