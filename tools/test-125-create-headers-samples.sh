#! /usr/bin/env bash


GH_ContentType_binary='application/octet-stream'
GH_ContentType_json='application/vnd.github+json'
HN_ContentDisposition='content-disposition'
HN_ContentType='content-type'
HN_Link='link'
PATH_HeadersFolder='./fixtures/headers'

# paginated json list
# GET /repos/$owner/$repo/releases?per_page=1
headers-1 ()
{	
	local headersPath="$PATH_HeadersFolder/headers-paginated-json-list.txt"
	mkdir -p "$PATH_HeadersFolder"
	local url=https://api.github.com/repos/etcd-io/etcd/releases?per_page=1
	curl \
		-H "$GH_ContentType_json" \
		--silent \
		--location \
		--dump-header "$headersPath" \
		--create-dirs \
		"$url" >/dev/null \
		|| return
	printf "$headersPath"
	[[ -t 1 ]] && printf '\n'
	grep -qi '^link:' "$headersPath" \
		|| { printf '  WARNING: no link header in %s\n' "$headersPath" >&2; }
}


# content-disposition from a release asset download
# The 302 redirect from GitHub's API is followed to Azure blob storage,
# which returns Content-Disposition on the 200 response.
# GET /repos/$owner/$repo/releases/assets/$id
headers-2 ()
{	
	local headersPath="$PATH_HeadersFolder/headers-content-disposition.txt"
	mkdir -p "$PATH_HeadersFolder"
	local url=https://api.github.com/repos/etcd-io/etcd/releases/assets/463602791
	curl \
		-H "Accept: $GH_ContentType_binary" \
		--silent \
		--location \
		--dump-header "$headersPath" \
		--create-dirs \
		"$url" >/dev/null \
		|| return
	printf "$headersPath"
	[[ -t 1 ]] && printf '\n'
	grep -i "^$HN_ContentDisposition" "$headersPath" || { printf '*** Content-Disposition header not found\n'; return 1; }
}


# single json object (no array, no pagination)
# GET /repos/$owner/$repo/releases/latest
headers-3 ()
{
	local headersPath="$PATH_HeadersFolder/headers-single-json.txt"
	mkdir -p "$PATH_HeadersFolder"
	local url=https://api.github.com/repos/etcd-io/etcd/releases/latest
	curl \
		-H "$GH_ContentType_json" \
		--silent \
		--dump-header "$headersPath" \
		--create-dirs \
		"$url" >/dev/null \
		|| return
	printf "$headersPath"
	[[ -t 1 ]] && printf '\n'
	grep -i "^$HN_ContentType" "$headersPath" || { printf '*** content-type header not found\n'; return 1; }
}


# object-wrapped paginated list (search)
# GET /search/repositories?q=$query&per_page=1
# Response: { total_count, incomplete_results, items[...] }
headers-4 ()
{
	local headersPath="$PATH_HeadersFolder/headers-paginated-object-list.txt"
	mkdir -p "$PATH_HeadersFolder"
	local url="https://api.github.com/search/repositories?q=etcd&per_page=1"
	curl \
		-H "$GH_ContentType_json" \
		--silent \
		--dump-header "$headersPath" \
		--create-dirs \
		"$url" >/dev/null \
		|| return
	printf "$headersPath"
	[[ -t 1 ]] && printf '\n'
	grep -i "^$HN_Link" "$headersPath" || { printf '*** link header not found\n'; return 1; }
}


all ()
{
	headers-1
	headers-2
	headers-3
	headers-4
}


main()
{
    case ${1:-all} in
        headers-1) headers-1 "$@";;
        headers-2) headers-2 "$@";;
        headers-3) headers-3 "$@";;
        headers-4) headers-4 "$@";;
        all|"")    all ;;
        *)         printf 'Unknown test: %s\n' "$1" >&2; exit 1 ;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi

