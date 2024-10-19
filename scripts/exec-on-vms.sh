#! /usr/bin/env bash

main ()
{
	local cmd=$1

	while read -r host; do
		printf '%s\n' "$host"
		ssh -n ubuntu@$host "$cmd"
	done < <(./list-vm-hosts.sh | jq -r '.value')
}

main "$@"
