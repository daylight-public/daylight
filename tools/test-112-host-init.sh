#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


test-host-init-calls-apt-get-update()
{
    local apt_calls=()
    apt-get() { apt_calls+=("$*"); }

    host-init || {
        printf '  FAIL (host-init-calls-apt-get-update): function returned non-zero\n'
        return 1
    }
    local joined="${apt_calls[*]}"
    [[ $joined == *"update"* ]] || {
        printf '  FAIL (host-init-calls-apt-get-update): apt-get update not called\n'
        return 1
    }
    printf '  PASS\n'
}


test-host-init-installs-nginx()
{
    local apt_calls=()
    apt-get() { apt_calls+=("$*"); }

    host-init || {
        printf '  FAIL (host-init-installs-nginx): function returned non-zero\n'
        return 1
    }
    local joined="${apt_calls[*]}"
    [[ $joined == *"install"* && $joined == *"nginx"* ]] || {
        printf '  FAIL (host-init-installs-nginx): nginx not in apt-get install\n'
        return 1
    }
    printf '  PASS\n'
}


test-host-init-installs-baseline()
{
    local apt_calls=()
    apt-get() { apt_calls+=("$*"); }
    local required=(ca-certificates curl git gnupg incus jq lsb-release nginx software-properties-common ufw)

    host-init || {
        printf '  FAIL (host-init-installs-baseline): function returned non-zero\n'
        return 1
    }
    local joined="${apt_calls[*]}"
    local missing=()
    for pkg in "${required[@]}"; do
        if [[ $joined != *"$pkg"* ]]; then
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        printf '  FAIL (host-init-installs-baseline): missing packages: %s\n' "${missing[*]}"
        return 1
    fi
    printf '  PASS\n'
}


run-tests()
{
    local tests=(
        test-host-init-calls-apt-get-update
        test-host-init-installs-nginx
        test-host-init-installs-baseline
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
        test-host-init-calls-apt-get-update)   test-host-init-calls-apt-get-update ;;
        test-host-init-installs-nginx)         test-host-init-installs-nginx ;;
        test-host-init-installs-baseline)      test-host-init-installs-baseline ;;
        all)                                   run-tests ;;
        *)                                     printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
