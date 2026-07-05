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
FIXTURES_DIR="$SCRIPT_DIR/fixtures/headers"


#--------
# lookup-content-disposition
#
# filter
# stdin - header file
# stdout - filename element from header
# return 1 if header not found
#
# sample
# 	content-disposition: attachment; filename=etcd-v3.6.13-darwin-amd64.zip
#
lookup-content-disposition ()
{
	# lookup content disp or fail
	# use bash paramter sub or a regex to find the filename
	# printf the filename, + newline if terminal
}



#
# Same as lookup-content-disposition
# But we don't use grep in helper functions when bash will do.
# As our reward we get to use base to confirm our test results
# which is very nice when that data is dynamic and needs to be 
# looked up.
#
grep-content-disposition ()
{
}

#-------------------
#
# lookup-header()
#
# Read a header file (as produced by curl --dump-header) from stdin and look
# up a header by name.  Returns the full header line on stdout.
#
# Positional args:  $1   header name to search for (case-insensitive)
#
# Stdin:            a headers file in HTTP format (CRLF line endings
#                   produced by curl --dump-header are handled)
#
# Stdout:           the matching header line, with trailing CRLF stripped,
#                   or nothing if not found
#
# Returns:          0   header found
#                   1   header not found
#
# How it works:
#   Reads stdin line by line.  For each line, strips the trailing CR
#   byte (\r) that curl --dump-header adds as part of CRLF line endings.
#   Both the search term and the line are lower-cased via bash's ${var,,}
#   parameter expansion to get a case-insensitive match.  The regex
#   /^name:.*/ anchors at the start — header names only appear at the
#   beginning of a line in HTTP header dumps, so no false matches.
#
# Edge cases:
#   Extra colon — if the user passes "content-type:" or "content-type",
#                 both work because the regex expects a colon anyway.
#   Arbitrary values — header values can contain colons, spaces, special
#                      characters; the (.*) capture handles them all.
#   CRLF endings — curl's --dump-header uses CRLF; the CR is stripped
#                  before matching and before printing.
#   Case mismatch — HTTP headers are case-insensitive by spec; ${,,}
#                   on both sides normalizes for comparison while
#                   preserving the original line for output.
#   Empty value — header: (with nothing after the colon) is a valid HTTP
#                 header; the regex matches and the line is printed.
#   Multiple matches — only the first match is returned, which matches
#                      curl's behavior (first header wins on duplicates).
#
lookup-header ()
{
    local headerName=$1
    local search="${headerName,,}"
    local line

    while IFS= read -r line; do
        line=${line%$'\r'}

        # Compare lower-cased to lower-cased (HTTP headers are
        # case-insensitive per RFC 7230).  The ${var,,} expansion
        # converts var to all lowercase.
        if [[ "${line,,}" =~ ^"$search":(.*) ]]; then
            printf '%s' "$line"
            return 0
        fi
    done

    return 1
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


all()
{
    local tests=(
        test-headers-content-disposition
        test-headers-paginated-json
        test-headers-paginated-object
        test-headers-single-json
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
        test-headers-single-json)             "$@" ;;
        *)                                    printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
