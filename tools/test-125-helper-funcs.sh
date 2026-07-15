#! /usr/bin/env bash
#
# test-125-helper-funcs
#
# This function will test lookup-header() using the files in fixtures/headers.
# Each file is a curl --dump-header of a different GitHub API endpoint, and each
# has different headers.
#
# The test will be to check each headers file for the existing of 4 headers
#
#	name                    present?
# 	content-type		always
# 	content-disp		maybe
# 	link header             maybe
# 	XXX-nonono-XXX          never
#
# Different files will have different expecations
# 
# 	file					ct?	cd?	lh?	xxx?
#	headers-content-disposition.txt		Y	Y	N	N
#	headers-paginated-json.txt		Y	N	Y	N
#	headers-paginated-object.txt		Y	N	Y	N
#	headers-single-json.txt			Y	N	N	N


HN_ct='content-type'
HN_cd='content-disposition'
HN_lh='link'
HN_xxx='XXX-nonono-XXX'

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1
FIXTURES_DIR="$SCRIPT_DIR/fixtures/headers"


#-------------------------------------------------------------------------------
#
# grep-content-disposition()
#
# Same purpose as lookup-content-disposition, but implemented with grep
# for cross-checking in tests.  Both functions should produce the same
# output for the same input.
#
# Stdin:            a headers file in HTTP format
#
# Stdout:           the filename from Content-Disposition, or nothing
#
grep-content-disposition ()
{
    local line
    line=$(grep -i '^content-disposition:' | head -1 | tr -d '\r')
    [[ -z "$line" ]] && return 1

    local filename
    filename=$(printf '%s' "$line" | grep -o 'filename=[^;]*' | sed 's/^filename=//;s/"//g')
    [[ -z "$filename" ]] && return 1

    printf '%s' "$filename"
    if [[ -t 1 ]]; then
        printf '\n'
    fi
}


#-------------------------------------------------------------------------------
#
# grep-next-link()
#
# Same as lookup-next-link but implemented with grep for cross-checking
# in tests.  Both functions should produce the same output for the same
# input.
#
# Stdin:            a headers file in HTTP format
#
# Stdout:           the next link URL, or nothing
#
grep-next-link ()
{
    local line
    line=$(grep -i '^link:' | head -1 | tr -d '\r')
    [[ -n "$line" ]] || return 1

    local url
    url=$(printf '%s' "$line" | grep -o '<[^>]*>[[:space:]]*\;[[:space:]]*rel="next"' | sed 's/^<\([^>]*\)>.*/\1/')
    [[ -n "$url" ]] || return 1

    printf '%s' "$url"
    if [[ -t 1 ]]; then
        printf '\n'
    fi
}


#
# test-lookup-next-link-hit
#
# Confirm lookup-next-link succeeds and its result matches grep-next-link
#
lookup-next-link-hit ()
{
    local fixture=$1
    local lookup url_grep

    lookup=$(lookup-next-link < "$fixture") || { printf '  FAIL: lookup failed\n'; return 1; }
    url_grep=$(grep-next-link < "$fixture") || { printf '  FAIL: grep failed\n'; return 1; }

    if [[ "$lookup" != "$url_grep" ]]; then
        printf '  FAIL: mismatch — lookup got "%s", grep got "%s"\n' "$lookup" "$url_grep"
        return 1
    fi

    printf '  PASS (next: %s)\n' "$lookup"
    return 0
}


#
# test-lookup-next-link-miss
#
# Confirm lookup-next-link returns non-zero (no next link)
#
lookup-next-link-miss ()
{
    local fixture=$1

    lookup-next-link < "$fixture" >/dev/null && {
        printf '  FAIL: unexpected next link found\n'
        return 1
    }

    printf '  PASS (next absent)\n'
    return 0
}


test-headers-content-disposition ()
{
    local fixture="$FIXTURES_DIR/headers-content-disposition.txt"
    local failed=0

    test-lookup-header-hit "$HN_ct" < "$fixture" || ((failed++))
    test-lookup-header-hit "$HN_cd" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_lh" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_xxx" < "$fixture" || ((failed++))

    return "$failed"
}


test-headers-paginated-json ()
{
    local fixture="$FIXTURES_DIR/headers-paginated-json-list.txt"
    local failed=0

    test-lookup-header-hit "$HN_ct" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_cd" < "$fixture" || ((failed++))
    test-lookup-header-hit "$HN_lh" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_xxx" < "$fixture" || ((failed++))

    return "$failed"
}


test-headers-paginated-object ()
{
    local fixture="$FIXTURES_DIR/headers-paginated-object-list.txt"
    local failed=0

    test-lookup-header-hit "$HN_ct" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_cd" < "$fixture" || ((failed++))
    test-lookup-header-hit "$HN_lh" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_xxx" < "$fixture" || ((failed++))

    return "$failed"
}


test-headers-single-json ()
{
    local fixture="$FIXTURES_DIR/headers-single-json.txt"
    local failed=0

    test-lookup-header-hit "$HN_ct" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_cd" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_lh" < "$fixture" || ((failed++))
    test-lookup-header-miss "$HN_xxx" < "$fixture" || ((failed++))

    return "$failed"
}


test-lookup-cds ()
{
    local failed=0

    test-lookup-cd-hit "$FIXTURES_DIR/headers-content-disposition.txt" || ((failed++))

    test-lookup-cd-miss "$FIXTURES_DIR/headers-paginated-json-list.txt" || ((failed++))
    test-lookup-cd-miss "$FIXTURES_DIR/headers-paginated-object-list.txt" || ((failed++))
    test-lookup-cd-miss "$FIXTURES_DIR/headers-single-json.txt" || ((failed++))

    return "$failed"
}


test-lookup-next-links ()
{
    local failed=0

    lookup-next-link-miss "$FIXTURES_DIR/headers-content-disposition.txt" || ((failed++))
    lookup-next-link-hit  "$FIXTURES_DIR/headers-paginated-json-list.txt" || ((failed++))
    lookup-next-link-hit  "$FIXTURES_DIR/headers-paginated-object-list.txt" || ((failed++))
    lookup-next-link-miss "$FIXTURES_DIR/headers-single-json.txt" || ((failed++))

    return "$failed"
}


#
# test-lookup-cd-hit
#
# Confirm lookup-content-disposition succeeds and its result
# matches what grep-content-disposition produces.
#
test-lookup-cd-hit ()
{
    local fixture=$1
    local lookup lookup_rc

    lookup=$(lookup-content-disposition < "$fixture") || true
    lookup_rc=$?

    local grep grep_rc
    grep=$(grep-content-disposition < "$fixture") || true
    grep_rc=$?

    if [[ "$lookup_rc" -ne 0 ]]; then
        printf '  FAIL: lookup failed (no CD found)\n'
        return 1
    fi

    if [[ "$lookup" != "$grep" ]]; then
        printf '  FAIL: mismatch — lookup got "%s", grep got "%s"\n' "$lookup" "$grep"
        return 1
    fi

    printf '  PASS (cd: %s)\n' "$lookup"
    return 0
}


#
# test-lookup-cd-miss
#
# Confirm lookup-content-disposition returns non-zero (no CD header).
#
test-lookup-cd-miss ()
{
    local fixture=$1

    lookup-content-disposition < "$fixture" >/dev/null && {
        printf '  FAIL: unexpected CD found\n'
        return 1
    }

    printf '  PASS (cd absent)\n'
    return 0
}


#
# test-lookup-header $headerName
#
# call lookup-header on a header-name; fail if missing
#
test-lookup-header-hit ()
{
    local headerName=$1
    if lookup-header "$headerName" >/dev/null; then
        printf '  PASS (%s found)\n' "$headerName"
        return 0
    else
        printf '  FAIL (%s not found)\n' "$headerName"
        return 1
    fi
}


#
# test-lookup-header $headerName
#
# call lookup-header on a header-name; fail if found
#
test-lookup-header-miss ()
{
    local headerName=$1
    if lookup-header "$headerName" >/dev/null; then
        printf '  FAIL (%s unexpectedly found)\n' "$headerName"
        return 1
    else
        printf '  PASS (%s absent)\n' "$headerName"
        return 0
    fi
}


test-lookup-http-status-200 ()
{
    local result
    result=$(lookup-http-status < "$FIXTURES_DIR/headers-200-json.txt")
    [[ "$result" == "200" ]] \
        || { printf '  FAIL: expected 200, got %s\n' "$result"; return 1; }
    printf '  PASS\n'
}


test-lookup-http-status-302 ()
{
    local result
    result=$(lookup-http-status < "$FIXTURES_DIR/headers-302-redirect.txt")
    [[ "$result" == "302" ]] \
        || { printf '  FAIL: expected 302, got %s\n' "$result"; return 1; }
    printf '  PASS\n'
}


test-lookup-http-status-415 ()
{
    local result
    result=$(lookup-http-status < "$FIXTURES_DIR/headers-415-invalid.txt")
    [[ "$result" == "415" ]] \
        || { printf '  FAIL: expected 415, got %s\n' "$result"; return 1; }
    printf '  PASS\n'
}


test-lookup-http-status-404 ()
{
    local result
    result=$(lookup-http-status < "$FIXTURES_DIR/headers-404-notfound.txt")
    [[ "$result" == "404" ]] \
        || { printf '  FAIL: expected 404, got %s\n' "$result"; return 1; }
    printf '  PASS\n'
}


test-lookup-http-status-empty ()
{
    local result
    result=$(lookup-http-status < /dev/null)
    [[ -z "$result" ]] \
        || { printf '  FAIL: expected empty, got %s\n' "$result"; return 1; }
    printf '  PASS\n'
}


all()
{
    local tests=(
        test-headers-content-disposition
        test-headers-paginated-json
        test-headers-paginated-object
        test-headers-single-json
        test-lookup-cds
        test-lookup-next-links
        test-lookup-http-status-200
        test-lookup-http-status-302
        test-lookup-http-status-415
        test-lookup-http-status-404
        test-lookup-http-status-empty
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
        all|"")                               all ;;
        test-headers-content-disposition|\
        test-headers-paginated-json|\
        test-headers-paginated-object|\
        test-headers-single-json|\
        test-lookup-cd-hit|\
        test-lookup-cd-miss|\
        test-lookup-cds|\
        test-lookup-next-links|\
        test-lookup-http-status-200|\
        test-lookup-http-status-302|\
        test-lookup-http-status-415|\
        test-lookup-http-status-404|\
        test-lookup-http-status-empty|\
        lookup-next-link-hit|\
        lookup-next-link-miss)                 "$@" ;;
        *)                                    printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
