#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


test-gen-run-script()
{
    local out
    out=$(fresh-daylight-gen-run-script) || {
        printf '  FAIL (gen-run-script): function returned non-zero\n'
        return 1
    }
    printf '%s' "$out" | head -1 | grep -qF '#! /usr/bin/env bash' || {
        printf '  FAIL (gen-run-script): missing shebang\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'if ! (return 0 2>/dev/null); then' || {
        printf '  FAIL (gen-run-script): missing source guard\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'get-latest-release-tag' || {
        printf '  FAIL (gen-run-script): missing get-latest-release-tag\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'get-release-asset-name' || {
        printf '  FAIL (gen-run-script): missing get-release-asset-name\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'download-release-asset' || {
        printf '  FAIL (gen-run-script): missing download-release-asset\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'verify-checksum' || {
        printf '  FAIL (gen-run-script): missing verify-checksum\n'
        return 1
    }
    printf '  PASS\n'
}


test-gen-run-script-no-raw-url()
{
    local out
    out=$(fresh-daylight-gen-run-script) || {
        printf '  FAIL (gen-run-script-no-raw-url): function returned non-zero\n'
        return 1
    }
    if printf '%s' "$out" | grep -qF 'raw.githubusercontent.com'; then
        printf '  FAIL (gen-run-script-no-raw-url): still uses raw.githubusercontent.com\n'
        return 1
    fi
    printf '  PASS\n'
}


test-gen-run-script-syntax()
{
    local out
    out=$(fresh-daylight-gen-run-script) || {
        printf '  FAIL (gen-run-script-syntax): function returned non-zero\n'
        return 1
    }
    printf '%s' "$out" | bash -n || {
        printf '  FAIL (gen-run-script-syntax): syntax check failed\n'
        return 1
    }
    printf '  PASS\n'
}


test-install-to()
{
    fresh-daylight-install-to "$TEST_TMP_DIR" || {
        printf '  FAIL (install-to): function returned non-zero\n'
        return 1
    }
    [[ -f "$TEST_TMP_DIR/fresh-daylight.service" ]] || {
        printf '  FAIL (install-to): service file not created\n'
        return 1
    }
    [[ -f "$TEST_TMP_DIR/fresh-daylight.timer" ]] || {
        printf '  FAIL (install-to): timer file not created\n'
        return 1
    }
    [[ -f "$TEST_TMP_DIR/bin/run.sh" ]] || {
        printf '  FAIL (install-to): run.sh not created\n'
        return 1
    }
    [[ -x "$TEST_TMP_DIR/bin/run.sh" ]] || {
        printf '  FAIL (install-to): run.sh not executable\n'
        return 1
    }
    printf '  PASS\n'
}


run-tests()
{
    local tests=(
        test-gen-run-script
        test-gen-run-script-no-raw-url
        test-gen-run-script-syntax
        test-install-to
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
    if [[ ${1:-all} == test-install-to ]] || [[ ${1:-all} == all ]]; then
        TEST_TMP_DIR=$(mktemp -d /tmp/daylight-110-XXXXXX) || {
            printf 'Failed to create test temp dir\n' >&2
            exit 1
        }
        printf 'Test artifacts: %s\n' "$TEST_TMP_DIR"
    fi
    case ${1:-all} in
        test-gen-run-script)             test-gen-run-script ;;
        test-gen-run-script-no-raw-url)  test-gen-run-script-no-raw-url ;;
        test-gen-run-script-syntax)      test-gen-run-script-syntax ;;
        test-install-to)                 test-install-to ;;
        all)                             run-tests ;;
        *)                               printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
