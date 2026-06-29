#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


test-gen-default-index()
{
    local out
    out=$(nginx-gen-default-index) || {
        printf '  FAIL (gen-default-index): function returned non-zero\n'
        return 1
    }
    printf '%s' "$out" | grep -q '🌞' || {
        printf '  FAIL (gen-default-index): emoji not in template output\n'
        return 1
    }
    printf '%s' "$out" | grep -q 'Welcome to nginx' || {
        printf '  FAIL (gen-default-index): missing welcome text\n'
        return 1
    }
    printf '  PASS\n'
}


test-install-index()
{
    local tmpFile; tmpFile=$(mktemp /tmp/daylight-test-index-XXXXXX.html)
    NGINX_INDEX="$tmpFile" nginx-install-index || {
        printf '  FAIL (install-index): function returned non-zero\n'
        rm -f "$tmpFile"
        return 1
    }
    grep -q '🌞' "$tmpFile" || {
        printf '  FAIL (install-index): emoji not in installed file\n'
        rm -f "$tmpFile"
        return 1
    }
    rm -f "$tmpFile"
    printf '  PASS\n'
}


test-init-syntax-failure()
{
    command -v nginx >/dev/null 2>&1 || {
        printf '  SKIP (init-syntax-failure): nginx not installed\n'
        return 0
    }

    # Write a deliberately broken nginx config
    local badConf; badConf=$(mktemp /tmp/daylight-bad-nginx-conf-XXXXXX)
    printf 'events {} http { server { listen 80; this is not valid nginx config;\n' > "$badConf"

    NGINX_CONF="$badConf" nginx-init >/dev/null 2>&1 && {
        printf '  FAIL (init-syntax-failure): expected failure but succeeded\n'
        rm -f "$badConf"
        return 1
    }

    rm -f "$badConf"
    printf '  PASS\n'
}


test-nginx-init-serves-emoji()
{
    command -v nginx >/dev/null 2>&1 || {
        printf '  SKIP (nginx-init-serves-emoji): nginx not installed\n'
        return 0
    }

    # Create temp docroot and nginx config
    local docroot; docroot=$(mktemp -d /tmp/daylight-nginx-docroot-XXXXXX)
    chmod 755 "$docroot"
    local port=8080
    local conf; conf=$(mktemp /tmp/daylight-nginx-conf-XXXXXX)
    cat > "$conf" <<NGINX_CONF
daemon off;
pid $docroot/nginx.pid;
error_log $docroot/error.log;
events {}
http {
    access_log $docroot/access.log;
    server {
        listen $port;
        root $docroot;
    }
}
NGINX_CONF

    # Start nginx with the test config (backgrounded since daemon off)
    nginx -c "$conf" -p "$docroot" &>/dev/null &
    local nginx_pid=$!
    # Create a dummy index.html so curl can detect nginx is up
    printf '<html><body>\n</body></html>\n' > "$docroot/index.html"
    # Give nginx a moment to bind before polling
    sleep 0.3
    # Wait for the port to be available
    local wait_sec=0
    while ! curl -sf "http://localhost:$port/" >/dev/null 2>&1 && (( wait_sec < 15 )); do
        sleep 0.2
        (( wait_sec++ ))
    done
    if (( wait_sec >= 15 )); then
        printf '  SKIP (nginx-init-serves-emoji): nginx did not start in time\n'
        kill "$nginx_pid" 2>/dev/null || true
        wait "$nginx_pid" 2>/dev/null || true
        rm -rf "$docroot" "$conf"
        return 0
    fi

    # Run nginx-init against the test server
    NGINX_CONF="$conf" NGINX_INDEX="$docroot/index.html" NGINX_URL="http://localhost:$port/" nginx-init >/dev/null 2>&1
    local rc=$?

    # Curl the page and check for the emoji
    local emoji_found=1
    curl -sf "http://localhost:$port/" | grep -q '🌞' && emoji_found=0

    # Cleanup
    kill "$nginx_pid" 2>/dev/null || true
    wait "$nginx_pid" 2>/dev/null || true
    sleep 0.1
    rm -rf "$docroot" "$conf"

    [[ $rc -eq 0 ]] || {
        printf '  FAIL (nginx-init-serves-emoji): nginx-init returned non-zero\n'
        return 1
    }
    [[ $emoji_found -eq 0 ]] || {
        printf '  FAIL (nginx-init-serves-emoji): emoji not found in served page\n'
        return 1
    }
    printf '  PASS\n'
}


run-tests()
{
    local tests=(
        test-gen-default-index
        test-install-index
        test-init-syntax-failure
        test-nginx-init-serves-emoji
    )
    local total=${#tests[@]}
    local passed=0
    local failed=0
    local skipped=0
    for t in "${tests[@]}"; do
        printf 'Test: %s\n' "$t"
        if "$t"; then
            (( passed++ ))
        else
            (( failed++ ))
        fi
    done
    printf '\n%d passed, %d failed, %d skipped, %d total\n' "$passed" "$failed" "$skipped" "$total"
    return "$failed"
}


main()
{
    case ${1:-all} in
        test-gen-default-index)           test-gen-default-index ;;
        test-install-index)               test-install-index ;;
        test-init-syntax-failure)         test-init-syntax-failure ;;
        test-nginx-init-serves-emoji)     test-nginx-init-serves-emoji ;;
        all)                              run-tests ;;
        *)                                printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
