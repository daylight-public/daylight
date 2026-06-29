#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


test-gen-service-file()
{
    local out
    out=$(fresh-daylight-gen-service-file) || {
        printf '  FAIL (gen-service-file): function returned non-zero\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'ExecStart=/opt/svc/fresh-daylight/bin/run.sh' || {
        printf '  FAIL (gen-service-file): missing ExecStart line\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'Type=oneshot' || {
        printf '  FAIL (gen-service-file): missing Type=oneshot\n'
        return 1
    }
    printf '  PASS\n'
}


test-gen-timer-file()
{
    local out
    out=$(fresh-daylight-gen-timer-file) || {
        printf '  FAIL (gen-timer-file): function returned non-zero\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'OnCalendar=hourly' || {
        printf '  FAIL (gen-timer-file): missing OnCalendar=hourly\n'
        return 1
    }
    printf '%s' "$out" | grep -qF 'Unit=fresh-daylight.service' || {
        printf '  FAIL (gen-timer-file): missing Unit line\n'
        return 1
    }
    printf '  PASS\n'
}


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
    printf '%s' "$out" | grep -qF 'main "$@"' || {
        printf '  FAIL (gen-run-script): missing main entry point\n'
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
        test-gen-service-file
        test-gen-timer-file
        test-gen-run-script
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
        TEST_TMP_DIR=$(mktemp -d /tmp/daylight-107-XXXXXX) || {
            printf 'Failed to create test temp dir\n' >&2
            exit 1
        }
        printf 'Test artifacts: %s\n' "$TEST_TMP_DIR"
    fi
    case ${1:-all} in
        test-gen-service-file)  test-gen-service-file ;;
        test-gen-timer-file)    test-gen-timer-file ;;
        test-gen-run-script)    test-gen-run-script ;;
        test-install-to)        test-install-to ;;
        all)                    run-tests ;;
        *)                      printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
