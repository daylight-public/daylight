* Intro
    * Getting started can be hard
    * Two kinds of intro
        * Too much
        * Not enough
    * Need opinionated middle ground
    * Fire up an Ubuntu VM w root privileges. I'll wait.
    * Snap install
    * lxd init works ok
    * If you stop here, you'll have problems, and you'll have to learn new things, and it'll be the wrong time to have to learn new things. So it'll be good learn them now.
* Storage
    * Containers need storage
        * lxc needs to store stuff
        * instances need filesystems
* Network
    * Containers need to reach the Internet
    * Containers might need to be reachable from the Internet
* SSH / folder share
* Manage instances on remote servers
* Resource limits


## Get Started!

Get root access on a VM
```
$ sudo snap install lxd
```
```
$ lxd init
Would you like to use LXD clustering? (yes/no) [default=no]: no
Do you want to configure a new storage pool? (yes/no) [default=yes]: yes
Name of the new storage pool [default=default]: default
Name of the storage backend to use (dir, lvm, zfs, btrfs, ceph, cephobject) [default=zfs]: zfs
Create a new ZFS pool? (yes/no) [default=yes]: yes
Would you like to use an existing empty block device (e.g. a disk or partition)? (yes/no) [default=no]: no
Size in GiB of the new loop device (1GiB minimum) [default=7GiB]: 7GiB
Would you like to connect to a MAAS server? (yes/no) [default=no]: no
Would you like to create a new local network bridge? (yes/no) [default=yes]: yes
What should the new bridge be called? [default=lxdbr0]: lxdbr0
What IPv4 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]: auto
What IPv6 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]: auto
Would you like the LXD server to be available over the network? (yes/no) [default=no]: no
Would you like stale cached images to be updated automatically? (yes/no) [default=yes]: yes
Would you like a YAML "lxd init" preseed to be printed? (yes/no) [default=no]: no
$ lxd init
```

Now you should be able to get a nice simple empty list of running containers
```
$ lxc list
+------+-------+------+------+------+-----------+
| NAME | STATE | IPV4 | IPV6 | TYPE | SNAPSHOTS |
+------+-------+------+------+------+-----------+
```

0 is too few. Let's fix that.
