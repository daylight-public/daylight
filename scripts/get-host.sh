#! /usr/bin/env bash

main ()
{
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: get-host $user $vmName\n' >&2; return 1; }
	declare -F ec >/dev/null || { printf 'Unknown function: %s\n' "ec"; return 1; }
	local user=$1
	local name=$2
	
	local vmKey="/$/$user/vm/$name/host"
	ec get --print-value-only "$vmKey"
}

main "$@"
