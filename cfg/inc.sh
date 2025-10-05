#! /usr/bin/env bash

main () {
	incus rm --force isaac || return
	incus init images:ubuntu/24.04/cloud isaac --storage default || return
	incus config set isaac user.user-data - </tmp/incus.cfg || return
	incus profile add isaac medium || return
	incus start isaac || return
	incus exec isaac -- cloud-init status --wait || return
	incus exec isaac -- cat /var/log/cloud-init-output.log || return
	incus config device add isaac ssh proxy listen="tcp:0.0.0.0:22000" connect="tcp:127.0.0.1:22" || return
	incus exec isaac -- cloud-init status || return
	
	# rayray
# 	incus exec isaac -- bash -c -- "printf '%s ALL = (root) NOPASSWD: ALL\n' 'rayray' >/etc/sudoers.d/01-rayray" || return
# 	incus file push /tmp/rayray.pub isaac/home/rayray/.ssh/ || return
# 	incus exec isaac -- touch /home/rayray/.ssh/authorized_keys || return
# 	incus exec isaac -- bash -c 'cat /home/rayray/.ssh/rayray.pub >> /home/rayray/.ssh/authorized_keys' || return
# 	incus exec isaac -- chmod 700 /home/rayray/.ssh/ || return
# 	incus exec isaac -- chmod 600 /home/rayray/.ssh/authorized_keys || return
# 	incus exec isaac -- chown -R rayray:rayray /home/rayray/ || return

	# isaac
# 	incus exec isaac -- adduser --gecos 'Isaac Burns - Daylight Dojo' --shell /bin/bash --disabled-password isaac || return
# 	incus exec isaac -- bash -c -- "printf '%s ALL = (root) NOPASSWD: ALL\n' 'isaac' >/etc/sudoers.d/02-isaac" || return
# 	incus exec isaac -- mkdir -p /home/isaac/.ssh/ || return
# 	incus file push /tmp/isaac.pub isaac/home/isaac/.ssh/ || return
# 	incus exec isaac -- touch /home/isaac/.ssh/authorized_keys || return
# 	incus exec isaac -- bash -c 'cat /home/isaac/.ssh/isaac.pub >> /home/isaac/.ssh/authorized_keys' || return
# 	incus exec isaac -- chmod 700 /home/isaac/.ssh/ || return
# 	incus exec isaac -- chmod 600 /home/isaac/.ssh/authorized_keys || return
# 	incus exec isaac -- chown -R isaac:isaac /home/isaac/ || return

	# arley
# 	incus exec isaac -- adduser --gecos 'Arley Burns - Daylight Dojo' --shell /bin/bash --disabled-password arley
# 	incus exec isaac -- bash -c -- "printf '%s ALL = (root) NOPASSWD: ALL\n' 'arley' >/etc/sudoers.d/03-arley"
# 	incus exec isaac -- mkdir -p /home/arley/.ssh/
# 	incus file push /tmp/arley.pub isaac/home/arley/
# 	incus exec isaac -- cat /home/arley/.ssh/arley.pub >> /home/arley/.ssh/authorized_keys
}

(return 0 2>/dev/null) || main "$@"

