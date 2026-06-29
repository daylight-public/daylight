#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


test-nginx-init-calls-nginx-t()
{
    local nginx_calls=()
    nginx() { nginx_calls+=("$*"); }
    curl() { true; }

    NGINX_INDEX=$(mktemp --tmpdir daylight-test-index.XXXXXX.html)
    : > "$NGINX_INDEX"

    nginx-init 2>/dev/null || true

    local joined="${nginx_calls[*]}"
    rm -f "$NGINX_INDEX"
    [[ $joined == *"-t"* ]] || {
        printf '  FAIL (nginx-init-calls-nginx-t): nginx -t not called\n'
        return 1
    }
    printf '  PASS\n'
}


test-nginx-init-appends-emoji()
{
    nginx() { true; }
    curl() { printf '<html><body><span style="font-size: 2em;">🌞</span></body></html>\n'; }

    NGINX_INDEX=$(mktemp --tmpdir daylight-test-index.XXXXXX.html)
    printf '<html><body>\n</body></html>\n' > "$NGINX_INDEX"

    nginx-init >/dev/null 2>&1 || true

    if grep -q '🌞' "$NGINX_INDEX"; then
        rm -f "$NGINX_INDEX"
        printf '  PASS\n'
    else
        rm -f "$NGINX_INDEX"
        printf '  FAIL (nginx-init-appends-emoji): emoji not found in index\n'
        return 1
    fi
}


test-nginx-init-returns-ok()
{
    nginx() { true; }
    curl() { printf '<html><body><span style="font-size: 2em;">🌞</span></body></html>\n'; }

    NGINX_INDEX=$(mktemp --tmpdir daylight-test-index.XXXXXX.html)
    : > "$NGINX_INDEX"

    local output
    output=$(nginx-init 2>/dev/null)
    rm -f "$NGINX_INDEX"
    [[ $output == "OK" ]] || {
        printf '  FAIL (nginx-init-returns-ok): expected "OK", got "%s"\n' "$output"
        return 1
    }
    printf '  PASS\n'
}


test-nginx-init-fails-on-syntax-error()
{
    nginx() { return 1; }
    curl() { true; }

    nginx-init 2>/dev/null && {
        printf '  FAIL (nginx-init-fails-on-syntax-error): expected failure but succeeded\n'
        return 1
    }
    printf '  PASS\n'
}


run-tests()
{
    local tests=(
        test-nginx-init-calls-nginx-t
        test-nginx-init-appends-emoji
        test-nginx-init-returns-ok
        test-nginx-init-fails-on-syntax-error
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
        test-nginx-init-calls-nginx-t)         test-nginx-init-calls-nginx-t ;;
        test-nginx-init-appends-emoji)         test-nginx-init-appends-emoji ;;
        test-nginx-init-returns-ok)            test-nginx-init-returns-ok ;;
        test-nginx-init-fails-on-syntax-error) test-nginx-init-fails-on-syntax-error ;;
        all)                                   run-tests ;;
        *)                                     printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
