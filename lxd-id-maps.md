lxd uses unprivileged containers by default. This means the root user in the container is not the root user of the host system, ie root is not uid 0.

The host accomplishes this by mapping a block of uids into the container.

By default lxd maps 65536 ids into the container with a base of 100000.
This means uid 0 = uid 100000 in the container and eg uid 1000 = 101000.
Anything mapped into the container that is not owned by one of these
high-number uids will appear in the container as uid/gid = -1, or nobody/nogroup.

Sometimes this isn't what you want.

For one, it can be nice for ubuntu (uid 1000) on the host to act as ubuntu in the container as well.

For two, I _think_ there might be some issues with ssh. It might not be possible for a user to ssh into a container if there is not a corresponding user on the host system, even though the ssh gets forwarded right into the container. If this is true then I think the user on the host system and the user in the container must have the same uid.

Linux has a facility to help with some of this: the shadow subsystem, notably the /etc/subuid and /etc/subgid. Each row in /etc/sub(ug)id is of the form user:baseid:numids. Each of these rows defines a range of userids that the user is able to control.

### How to play with id maps
To have any visibility into what's going on with id maps, the best thing to do is to share a folder from the host VM with an lxd container, and create files on the shared folder from both the host and the container. Playing with this, in conjunction with playing with id maps, is a great way to develop intuition.

