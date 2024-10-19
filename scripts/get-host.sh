#! /usr/bin/env bash

main ()
{
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: get-host $user $vm\n' >&2; return 1; }
	declare -F ec >/dev/null || { printf 'Unknown function: %s\n' "ec"; return 1; }
	local user=$1
	local vm=$2
	
	local vmKey="/$user/vm/$name/host"
	ec get --print-value-only "/$user/vm/$vm/host"
}

main "$@"
