#! /usr/bin/env bash

main ()
{
	name=host
	incus rm --force $name || return
	incus init images:ubuntu/24.04/cloud $name --storage default || return
	incus config set $name user.user-data - </tmp/host.cfg || return
	incus profile add $name medium || return
	incus start $name || return
	incus exec $name -- cloud-init status --wait || return
	incus exec $name -- cat /var/log/cloud-init-output.log || return
	incus config device add $name ssh proxy listen="tcp:0.0.0.0:22000" connect="tcp:127.0.0.1:22" || return
	incus exec $name -- cloud-init status || return
}

(return 0 2>/dev/null) || main "$@"

