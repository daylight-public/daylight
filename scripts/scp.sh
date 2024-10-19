#! /usr/bin/env bash

create-scp-spec ()
{
	# shellcheck disable=SC2016
	(( $# == 1 )) || { printf 'Usage: create-scp-spec $scpArg\n' >&2; return 1; }
	# shellcheck disable=SC2016
	[[ -n "$DYLT_USER" ]] || { echo 'Please set $DYLT_USER' >&2; return 1; }
	arg=$1
	
	if [[ $arg == *":"* ]]; then
		local argVm=${arg%%:*}
		local argHost; argHost="$(./get-host.sh "$DYLT_USER" "$argVm")" || return
		local argPath=${arg##*:}
		local argUser=ubuntu
		local spec; spec="$(printf '%s@%s:%s' "$argUser" "$argHost" "$argPath")" || return
	else
		local argPath="$arg"
		local spec; spec="$(printf '%s' "$argPath")" || return
	fi
	printf '%s' "$spec"
}

main ()
{
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: scp.sh $src $dst\n' >&2; return 1; }
	declare -F ec >/dev/null || { printf 'Unknown function: %s\n' "ec"; return 1; }
	local src=$1
	local dst=$2
	local srcSpec dstSpec
	# src
	srcSpec="$(create-scp-spec "$src")"
	# dst
	dstSpec="$(create-scp-spec "$dst")"
	printf 'Copying %s to %s ...' "$srcSpec" "$dstSpec"
	scp "$srcSpec" "$dstSpec"
}

main "$@"

