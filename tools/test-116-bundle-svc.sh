#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


test-resolve-rel-path-existing()
{
    local result
    result=$(resolve-rel-path svc/nginx/index.html.tmpl) || {
        printf '  FAIL (resolve-rel-path-existing): returned non-zero\n'
        return 1
    }
    [[ -f "$result" ]] || {
        printf '  FAIL (resolve-rel-path-existing): path is not a file: %s\n' "$result"
        return 1
    }
    printf '  PASS\n'
}


test-resolve-rel-path-nonexistent()
{
    local result
    result=$(resolve-rel-path nonexistent/file.txt) || {
        printf '  FAIL (resolve-rel-path-nonexistent): returned non-zero\n'
        return 1
    }
    # Should return a path string even if file doesn't exist
    [[ -n "$result" ]] || {
        printf '  FAIL (resolve-rel-path-nonexistent): returned empty string\n'
        return 1
    }
    # Path should end with the relative path we passed
    [[ "$result" == */nonexistent/file.txt ]] || {
        printf '  FAIL (resolve-rel-path-nonexistent): unexpected path: %s\n' "$result"
        return 1
    }
    printf '  PASS\n'
}


test-resolve-rel-path-usage()
{
    resolve-rel-path 2>/dev/null && {
        printf '  FAIL (resolve-rel-path-usage): expected failure with no args\n'
        return 1
    }
    resolve-rel-path a b 2>/dev/null && {
        printf '  FAIL (resolve-rel-path-usage): expected failure with 2 args\n'
        return 1
    }
    printf '  PASS\n'
}


test-template-resolves-from-extracted-tree()
{
    # Simulate a release extraction: copy daylight.sh + svc/ to a temp dir
    local releaseRoot; releaseRoot=$(mktemp -d /tmp/daylight-116-XXXXXX)
    cp "$SCRIPT_DIR/../daylight.sh" "$releaseRoot/daylight.sh"
    cp -r "$SCRIPT_DIR/../svc" "$releaseRoot/svc"

    # Source daylight.sh from the temp dir (simulates an extracted release)
    (
        cd "$releaseRoot" || exit 1
        source daylight.sh || exit 1

        # Verify template generation works from an installed location
        local out
        out=$(nginx-gen-default-index) || {
            printf '  FAIL (template-resolves): nginx-gen-default-index returned non-zero\n'
            exit 1
        }
        printf '%s' "$out" | grep -q '🌞' || {
            printf '  FAIL (template-resolves): emoji not in template output\n'
            exit 1
        }

        # Verify install-index writes to the expected path
        local tmpFile; tmpFile=$(mktemp /tmp/daylight-116-install-XXXXXX.html)
        nginx-install-index "$tmpFile" || {
            printf '  FAIL (template-resolves): nginx-install-index returned non-zero\n'
            rm -f "$tmpFile"
            exit 1
        }
        grep -q '🌞' "$tmpFile" || {
            printf '  FAIL (template-resolves): emoji not in installed file\n'
            rm -f "$tmpFile"
            exit 1
        }
        rm -f "$tmpFile"
        printf '  PASS\n'
    )
    local rc=$?
    rm -rf "$releaseRoot"
    return "$rc"
}


run-tests()
{
    local tests=(
        test-resolve-rel-path-existing
        test-resolve-rel-path-nonexistent
        test-resolve-rel-path-usage
        test-template-resolves-from-extracted-tree
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
        test-resolve-rel-path-existing)               test-resolve-rel-path-existing ;;
        test-resolve-rel-path-nonexistent)             test-resolve-rel-path-nonexistent ;;
        test-resolve-rel-path-usage)                   test-resolve-rel-path-usage ;;
        test-template-resolves-from-extracted-tree)    test-template-resolves-from-extracted-tree ;;
        all)                                           run-tests ;;
        *)                                             printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
