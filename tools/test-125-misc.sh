#! /usr/bin/env bash
#
# One-off functions for analysis, test-fixture creation, and other odds and ends
# Tests in these files are often coarse-grained compared to actual unit tests
# and even system tests. It's ok if a single function checks multiple things
# in a single 'test'. We're going for simplicity here, and don't want to bog
# test writer's down in chasing granularity

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/../gh-funcs.sh" || exit 1

test-cp-error-codes ()
{
	local tmpDir
	tmpDir=$(mktemp -d --tmpdir cp-error-test.XXXXXX)

	# source file to copy
	local src="$tmpDir/src.txt"
	echo "hello" > "$src"

	# fixture: an existing file (for overwrite test)
	local destFile="$tmpDir/existing-file.txt"
	echo "original" > "$destFile"

	# fixture: an existing directory (for dir-ambiguity test)
	mkdir -p "$tmpDir/existing-dir"

	# fixture: unwritable directory
	mkdir -p "$tmpDir/unwritable"
	chmod 000 "$tmpDir/unwritable"

	printf '  %-32s %-6s  %s\n' "Scenario" "Exit" "Error"
	printf '  %-32s %-6s  %s\n' "────────────────────────────────" "────" "─────"

	local rc stderr

	# 1. Normal copy to a new file
	stderr=$(cp "$src" "$tmpDir/copied.txt" 2>&1)
	rc=$?
	printf '  %-32s %-6d  %s\n' "Normal copy" "$rc" "$stderr"

	# 2. Copy to a file that already exists
	stderr=$(cp "$src" "$destFile" 2>&1)
	rc=$?
	printf '  %-32s %-6d  %s\n' "Overwrite existing file" "$rc" "$stderr"

	# 3. Copy to a path that is an existing directory (no trailing /)
	stderr=$(cp "$src" "$tmpDir/existing-dir" 2>&1)
	rc=$?
	printf '  %-32s %-6d  %s\n' "Copy to existing dir (no /)" "$rc" "$stderr"

	# 4. Copy to a path with missing parent directories
	stderr=$(cp "$src" "$tmpDir/missing/sub/file" 2>&1)
	rc=$?
	printf '  %-32s %-6d  %s\n' "Missing parent directory" "$rc" "$stderr"

	# 5. Copy to an unwritable directory
	stderr=$(cp "$src" "$tmpDir/unwritable/" 2>&1)
	rc=$?
	printf '  %-32s %-6d  %s\n' "Unwritable directory" "$rc" "$stderr"

	# restore permissions for cleanup
	chmod 755 "$tmpDir/unwritable" 2>/dev/null

	printf '\n  Temp folder left for inspection: %s\n' "$tmpDir"
}


# Fetch a file endpoint with default Accept (JSON), pipe response through
# lookup-mediatype, verify the output matches the expected content_type.
test-lookup-mediatype ()
{
    local url="https://api.github.com/repos/dylt-dev/dylt/releases/assets/449914893"
    local response
    response=$(curl --fail-with-body --location --silent "$url") || {
        printf '  FAIL: curl failed\n'
        return 1
    }

    local mediaType
    mediaType=$(printf '%s' "$response" | lookup-mediatype)

    if [[ "$mediaType" == "text/plain; charset=utf-8" ]]; then
        printf '  PASS (mediatype: %s)\n' "$mediaType"
    else
        printf '  FAIL: expected "text/plain; charset=utf-8", got "%s"\n' "$mediaType"
        return 1
    fi
}


main()
{
    case ${1:-} in
        test-cp-error-codes)  test-cp-error-codes "$@";;
        test-lookup-mediatype) test-lookup-mediatype "$@";;
        "")                  printf 'Usage: %s <test-name>\n' "$0" >&2; exit 1 ;;
        *)                   printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
