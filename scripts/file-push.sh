#! /usr/bin/env bash

main ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: file-push.sh $src $vm:/dstPath\n' >&2; return 1; }
    # shellcheck disable=SC2016
    [[ -n "$DYLT_USER" ]] || { echo 'Please set $DYLT_USER' >&2; return 1; }
	local src=$1
	local dst=$2
	local dstVm=${dst%%:*}
	local dstPath=${dst#*:}
    local dstHost; dstHost="$(./get-host.sh "$DYLT_USER" "$dstVm")" || return
	scp "$src" "ubuntu@$dstHost:$dstPath"
}

main "$@"
