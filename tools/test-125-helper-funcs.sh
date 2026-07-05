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


#-------------------------------------------------------------------------------
#
# lookup-content-disposition()
#
# Read a headers file from stdin and extract the filename from the
# Content-Disposition header.  Internally uses lookup-header to find
# the raw header line, then parses the filename value from it.
#
# Content-Disposition values use the format defined in RFC 6266:
#
#   content-disposition: attachment; filename=etcd-v3.6.13-darwin-amd64.zip
#   content-disposition: attachment; filename="etcd-v3.6.13-darwin-amd64.zip"
#
# The filename may be quoted or unquoted.  This function tries the
# quoted form first (filename="..."), then falls back to unquoted
# (filename=... without whitespace or semicolons).  This mirrors how
# curl --remote-header-name parses Content-Disposition.
#
# Stdin:            a headers file in HTTP format
#
# Stdout:           the filename from Content-Disposition, or nothing
#                   if no matching header was found or no filename
#                   could be extracted
#
# Returns:          0   filename found and printed
#                   1   Content-Disposition header not found
#                   2   header found but no extractable filename
#
lookup-content-disposition ()
{
    # Use lookup-header to get the raw Content-Disposition line
    local line
    line=$(lookup-header 'content-disposition') || return 1

    local filename

    # Try quoted filename first:  filename="value"
    # This is the more common form in modern responses.
    if [[ "$line" =~ filename=\"([^\"]+)\" ]]; then
        filename="${BASH_REMATCH[1]}"

    # Fall back to unquoted:  filename=value
    # The value extends to the next semicolon, whitespace, or end of line.
    elif [[ "$line" =~ filename=([^\";[:space:]]+) ]]; then
        filename="${BASH_REMATCH[1]}"

    else
        return 2
    fi

    printf '%s' "$filename"
    if [[ -t 1 ]]; then
        printf '\n'
    fi
}


#-------------------------------------------------------------------------------
#
# grep-content-disposition()
#
# Same purpose as lookup-content-disposition, but implemented with grep
# instead of bash builtins.  This exists specifically as a cross-check:
# a second, independent implementation to compare results against
# lookup-content-disposition in tests.  Both functions should produce
# the same output for the same input.
#
# Stdin:            a headers file in HTTP format
#
# Stdout:           the filename from Content-Disposition, or nothing
#                   if no matching header was found
#
# Returns:          0   filename found and printed
#                   1   no Content-Disposition header found
#
grep-content-disposition ()
{
    # Find the Content-Disposition header line, case-insensitive,
    # anchored to the start of the line.  Strip carriage returns
    # from curl's CRLF line endings.
    local line
    line=$(grep -i '^content-disposition:' | head -1 | tr -d '\r')

    if [[ -z "$line" ]]; then
        return 1
    fi

    # Extract the filename= portion.  [^;]* stops at the next
    # semicolon or end of line, handling both quoted and
    # unquoted filenames.  Strip any surrounding quotes and the
    # filename= prefix.
    local filename
    filename=$(printf '%s' "$line" | grep -o 'filename=[^;]*' | sed 's/^filename=//;s/"//g')

    if [[ -z "$filename" ]]; then
        return 1
    fi

    printf '%s' "$filename"
    if [[ -t 1 ]]; then
        printf '\n'
    fi
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



#
#-------------------------------------------------------------------------------
#
# lookup-next-link()
#
# Read a headers file from stdin and extract the URL from the Link
# header with rel="next".  Internally uses lookup-header to find the
# raw header line, then parses the next-link URL from it.
#
# RFC 8288 Link header format:
#
#   link: <https://api.github.com/...?page=2>; rel="next",
#         <https://api.github.com/...?page=288>; rel="last"
#
# Whitespace around the semicolon is optional per the RFC.
#
# Stdin:            a headers file in HTTP format
#
# Stdout:           the next link URL, or nothing if no Link header
#                   or no rel="next" link was found
#
# Returns:          0   next link found and printed
#                   1   Link header not found
#                   2   header found but no rel="next" link
#
lookup-next-link ()
{
    local line
    line=$(lookup-header 'link') || return 1

    # Extract the URL angle bracket before ; rel="next"
    # Whitespace around ; is optional per RFC 8288: <url>;rel="next",
    # <url> ; rel="next", <url>; rel="next", etc.
    if [[ "$line" =~ \<([^\>]+)\>[[:space:]]*\;[[:space:]]*rel=\"next\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        if [[ -t 1 ]]; then
            printf '\n'
        fi
        return 0
    fi

    return 2
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
# Stdout:           the next link URL, or nothing if not found
#
# Returns:          0   next link found and printed
#                   1   Link header or rel="next" not found
#
grep-next-link ()
{
    local line
    line=$(grep -i '^link:' | head -1 | tr -d '\r')
    [[ -n "$line" ]] || return 1

    # Extract <URL> then ; with optional whitespace, then rel="next"
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


all()
{
    local tests=(
        test-headers-content-disposition
        test-headers-paginated-json
        test-headers-paginated-object
        test-headers-single-json
        test-lookup-cds
        test-lookup-next-links
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
        lookup-next-link-hit|\
        lookup-next-link-miss)                 "$@" ;;
        *)                                    printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
