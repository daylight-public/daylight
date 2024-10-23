#! /usr/bin/env bash

main ()
{
	# shellcheck disable=SC2016
	(( $# == 1 )) || { printf 'Usage: get-all-vms.sh $user\n' >&2; return 1; }
	declare -F ec >/dev/null || { printf 'Unknown function: %s\n' "ec"; return 1; }
	local user=$1
	
	local prefix="/$user/vm"
	while IFS= read -r key; do
		if [[ -n $key ]]; then
			vm=${key#$prefix/}
			vm=${vm%%/*}
			printf '%s\n' "$vm"
		fi
	done < <(ec get --keys-only --prefix "/$user/vm" -w json | jq -r '.kvs[].key | @base64d') \
	| sort \
	| uniq
}

main "$@"
