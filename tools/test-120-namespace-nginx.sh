#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


# Determine how to invoke bwrap. On kernels with
# apparmor_restrict_unprivileged_userns=1, unprivileged bwrap
# fails with "Permission denied" for the uid map. In that case
# fall through to sudo (which we know is available in test
# environments that have nginx installed).
detect-bwrap()
{
    command -v bwrap >/dev/null 2>&1 || return 1
    if bwrap --ro-bind / / --tmpfs /tmp -- bash -c 'true' >/dev/null 2>&1; then
        printf 'bwrap'
    elif sudo -n bwrap --ro-bind / / --tmpfs /tmp -- bash -c 'true' >/dev/null 2>&1; then
        printf 'sudo bwrap'
    else
        return 1
    fi
}


test-nginx-init-bwrap()
{
    local bwrap_cmd
    bwrap_cmd=$(detect-bwrap) || {
        printf '  SKIP (nginx-init-bwrap): bubblewrap not available\n'
        return 0
    }

    # Build the sandbox command.
    # Bind the real filesystem read-only, overlay tmpfs on paths that
    # nginx writes to (docroot, pid, logs, cache).  Inside the sandbox,
    # nginx runs on the real paths with the real config, but all writes
    # stay in the tmpfs overlays — nothing touches the real filesystem.
    local daylightPath; daylightPath=$(readlink -f "$SCRIPT_DIR/../daylight.sh")
    local cmd
    cmd="$bwrap_cmd --unshare-net --ro-bind / /"
    cmd="$cmd --tmpfs /run"
    cmd="$cmd --tmpfs /var/www/html"
    cmd="$cmd --tmpfs /var/log/nginx"
    cmd="$cmd --tmpfs /var/cache"
    cmd="$cmd --dev /dev"
    cmd="$cmd bash -c \"ip link set lo up && source '$daylightPath' && nginx && nginx-init\""

    local output
    output=$(eval "$cmd" 2>&1)
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        printf '  FAIL (nginx-init-bwrap): sandbox exited %d\n' "$rc"
        printf '    output: %s\n' "$output"
        return 1
    fi
    if ! printf '%s' "$output" | grep -q 'OK'; then
        printf '  FAIL (nginx-init-bwrap): expected "OK" in output, got: %s\n' "$output"
        return 1
    fi
    printf '  PASS\n'
}


run-tests()
{
    local tests=(
        test-nginx-init-bwrap
    )
    local total=${#tests[@]}
    local passed=0
    local failed=0
    for t in "${tests[@]}"; do
        printf 'Test: %s\n' "$t"
        if "$t"; then
            (( passed++ ))
        else
            (( failed++ ))
        fi
    done
    printf '\n%d passed, %d failed, %d total\n' "$passed" "$failed" "$total"
    return "$failed"
}


main()
{
    case ${1:-all} in
        test-nginx-init-bwrap)  test-nginx-init-bwrap ;;
        all)                    run-tests ;;
        *)                      printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
