#! /usr/bin/env bash

main ()
{
	# shellcheck disable=SC2016
	(( $# == 1 )) || { printf 'Usage: list-vm-hosts.sh $user\n' >&2; return 1; }
	local user=$1

	ec get --prefix "/$/$user/vm" -w json | jq '[ .kvs[] 
	                                              | select(.key | @base64d | contains("host"))
	                                              | { "name": .key | @base64d | split("/") | .[4],
	                                                  "host": .value | @base64d
	                                                }
	                                            ]'
}

main "$@"
