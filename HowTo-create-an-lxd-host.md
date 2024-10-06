## How to Create an lxd host VM

[DIY Storage Pools](#diy-storage-pools)

_There are 2 kinds of 'How To LXD' information out there. The first is reference material that tells you everything. The second is quickstart material that gets you up and going as fast as possible. The first is too long to ever read in its entirety. The second is too short to leave you understanding anything at all about the lxd system you've just unleashed. The result is no one ever looks at the first kind of info, and they instead barrel ahead in relative ignorance with quickstarts, ending up with a system they don't understand, and that all-to-familiar dread-and-anxiety of being responsible for a system you can't fix and you have to hope always magically works, and never breaks in soul-crushing ways._

_What's needed is a variety of opinionated 'How To LXD' guides, that skip what you don't need to know, and force you to learn about the things you don't want to learn about but will be very glad that you did._

_This is such a guide._

At a high level creating an Ubuntu lxd host VM  -- a Ubunut VM capable of hosting lxd containers -- is very straightforward ...
1. Delete the existing `apt` lxd package, if necessary
1. Install the lxd snap package
1. Run `lxc init` and accept all default options

There are a few snags with this approach
* It's not scriptable
* The default options might not be what you want
* The default storage pool is the easiest to create, but it possibly is not the storage pool you want, and you won't even know it

### Storage pools?

Storage pools are a major `lxd` concept, and a major source of confusion. When using Docker containers, Docker uses its own filesystem. This is bad, but it means users never have to worry about filesystem details. `lxd` is a little different. `lxd` gives you a lot of options for how to do storage, which is good. But unless you're experienced with the nuances of layered filesystems, of btrfs vs ZFS, etc, everything about storage pools is likely unfamiliar, and storage pools can end up being a bit of a blocker.

The good news is that lxd's default settings to an ok job for most uses. `lxd` will create a ZFS volume, stored in a single file, and `lxd` will use this ZFS volume to hold all its instances and images. And that might be all you ever need.

(From https://linuxcontainers.org/lxd/docs/master/howto/storage_pools/ ... "Unless specified otherwise, LXD sets up loop-based storage with a sensible default size (20% of the free disk space, but at least 5 GiB and at most 30 GiB)")

But if you want to keep all your `lxd` stuff in a separate partition or disk, or if you want to separate instances and images, or if you don't want to use ZFS ... you'll have to do a few things on your own.

### DIY Storage pools

In this little example, we're going to use an unpartitioned 50G disk for lxd. This disk will be compeletely separate from the root filesystem. On this disk we will create 3 storage pools: 10G ZFS for images, 20G ZFS for containers, and 20G btrfs for other containers. This is for purely instructive purposes, though it might be interesting to experiment with the different container storage pools, eg for performance testing.

#### Storage pools vs storage volumes

The LXD docs at https://linuxcontainers.org/lxd/docs/master/explanation/storage/ (as of this writing) suggest that storage pools are like disks, and storage volumes are like the partitions within disks. This isn't bad but it's very misleading in one important way. With disks and partitions, each partition can have its own filesystem, and partitions are generally completely independent of one another. With storage pools and storage volumes, the choice of technology (btrfs, ZFS, etc) is made at the storage pool level, so all storage volumes inherit the filesystem from their storage pool. This means you are likely to want multiple storage pools, so you can have volumes with different filesystems.

Storage volumes are an implementation detail in `lxd`. `lxd` will automatically create storage volumes for you, eg separate volumes for instances and volumes, to keep instances and volumes separate from one another. I'm honestly not sure if manually creating volumes is interesting and helpful.

#### Creating storage pools manually

We're going to start with a fresh, un-init'd lxd installation, and an empty, unpartitioned disk. lxd is able to format partitions and install and mount filesystems, but it stops at partitioning.

```
lxc storage list
lxc storage create img zfs source=/dev/sdb1
lxc storage create c1 zfs source=/dev/sdb2
lxc storage create c2 btrfs source=/dev/sdb3
lxc storage pool list
```

### Networking

Another Docker comparison: in Docker, Docker handles networking for its various containers fairly transparently. lxd does the same, and unlike storage pools, it is quite possible to go far with lxd and never know anything about networking.

And this is fine ... up until you have a problem, or want to do something interesting, and you read 'look at your `lxdbr0` etc etc' and you cry for an hour because you never learned what `lxdbr0` was and with a name like that, you hoped you'd never have to.

#### network types

`lxd` provides quite a few types of networks to choose from. From https://linuxcontainers.org/lxd/docs/master/howto/network_create/ we've got ...
* bridge
* ovn
* maclan
* sriov
* physical

But as far as mere mortals are concerned there's one type, and it's **bridge**.

A bridge network is pretty close to a physical network switch. With a physical switch, you connect individual hosts via hardware NICs to a switch using Ethernet cables. With a bridge network, you connect containers via software NICs to a bridge network using lxc commands or configuration. Here we already have a potential point of confusion that is useful to clarify. With physical networking, we tend to think of a network as 'a bunch of things plugged into another thing, so all the things can communicate with one another'. The network is collectively everything. With lxc networking, it can be more useful to think smaller, and think of the network as a single thing, that other containers plug into to talk to each other and to talk to the greater Internet.

#### NICs

If reading 'hardware NICs' and 'software NICs' above seemed a little strange, that's perfectly natural. It's still a useful idea to have a handle on, so here's a bit of clarification. A physical network card (aka a NIC) is a little hunk of metal in silicon that you can plug one or more network cables into, and that has a bunch of chips on it, and those chips run software. That software knows how to translate electrical signals from its cable(s) into TCP/IP packets that programs can use, and vice versa. It's the software that matters.

A software NIC is a service that runs pretty much the same software as a hardware NIC, without needing to do the physical stuff. If you're using the cloud or a hosted service to read this, you're probably doing it over at least one software NIC, to a service running on a VM, that might be running on a VM, etc. Software NICs don't have ports that you plug cables into, but as far as the software is concerned, one NIC is as good as another.

For a NIC to be useful it needs to be connected to the Internet, either directly, via a cable, or indirectly, by being connected to an Internet-connected NIC over a network. And this is what an lxd **bridged** network is: it's a network with at least one Internet-connected (possibly physical) NIC, that you can connect containers to, and that allows those containers to connect to the Internet as well as anything else the network can connect to.

### lxd profiles

Creating containers with the same sets of devices over and over seems tedious and error-prone. Enter lxc profiles. An lxd profile is a collection of devices and other things that are likely to be common across a number of VMs. 

### How to networkp

At the end of the day, the part of lxd networking that's necessary to understand is pretty small. It's more a matter of knowing what you have to know, versus knowing what you can probably ignore. To network in lxd all you really have to do is the following ...

- Create all the bridged networks you need, possibly just one
- Attach your networks to profiles, which might just mean attaching your single bridged network to the default profile
- Initialize your instances with specific profiles, causing them to 'inherit' a network from their profile. If you're working with the default profile you can ignore this.

```
# Create network
lxc network create lxdbr0 --type bridge
lxc network attach-profile lxdbr0 default eth0
lxc init ubuntu:22.04 ubu --profile default --storage c1
```

### SSH
Create proxy
```
# Create proxy
lxc config device add ubu ssh2200 proxy \
    listen=tcp:0.0.0.0:2200 \
    connect=tcp:127.0.0.1:22
```
Copy public key to host

`lxc file push` public key from host into container

### User id map
Unix 101: Every file (and file-like object) is owned by a user and by a group. This user and a group are represented by numbers. The OS will then assign names to these numbers so that humans can actually use the system - for example in Ubuntu `root` is 0, `ubuntu` is 1000, and other users get arbitrary system-assigned values. But these user and group names are entirely there for human usage. The OS itself doesn't care about them.

lxd containers leverage this to provide a bit of security. By default, lxd assigns completely different numbers to familiar usernames like `root`, `ubuntu` etc. Typically the numbers assigned are very high, like 1002048, such that they won't collide with uids and gids on the host system. Why do this? So the root user in a container has a uid and gid that are completely meaningless on the host system. If the root user in a container somehow breaks out of the container and onto the host system, they won't be able to do any damage because they won't have any permissions on anything. Their uid and gid are not recognized.

Sometimes the implications of this are not desirable. For example, it might be nice for a user on the host, and a user inside a container, to have the same uid and gid. Files can then be seamlessly copied between host and container; folders on the host can be shared as disk devices inside the container; etc. But if `ubuntu` or `jsmith` on the host has a completely different uid/gid than `ubuntu` or `jsmith` in the container, then none of this will work.

We need a way to manipulate the mapping of host uid/gids to container uid/gids. This way users on the host can have the convenient illusion of being the same user inside the container and out. There are two components to solving this: one on the host side, and one on the container side.

### Part 1: The Host Side (shadow user files - `/etc/subuid` and `/etc/subgid`)

Linux has a group of utilities and files collectively known as the 'shadow' system. The idea is that something needs to answer the question "what userids in containers can be assumed/impersonated/etc by which userids in the host system?" Technically, this is really a question about user namespaces, since the Linux kernel doesn't know anything about lxd containers, and user namespaces are one of the tools lxd users to create the illusion of containers. But it comes down to the same thing.

`/etc/subuid` and `/etc/subgid` are plain text files that map ranges of u/gids in the host system to ranges of u/gids in containers. These mappings are known as `idmap`s. Every Linux process has a `uidmap` and a `gidmap`. The default `idmap`s look like this ...
```
$ cat /proc/$$/uid_map
         0          0 4294967295
$ cat /proc/$$/gid_map
         0          0 4294967295
```

These lines can be translated like this ... 
* uid 0 is allowed to map to uid 0
* uid 1 is allowed to map to uid 1
* uid 2 is allowed to map to uid 2
* ...
* uid 4294967295 is allowed to map to 4294967295

And the same goes for gids. Basically, any u/gid can be mapped to itself.

The `/etc/sub*id` file formats are slightly different ...
```
$ cat /etc/subuid
ubuntu:100000:65536
$ cat /etc/subgid
ubuntu:100000:65536
```

These lines can be translated like this
* uid 1000 (aka `ubuntu`) is allowed up map to uid 1000000
* uid 1001 is allowed to map to uid 100001
* uid 1002 is allowed to map to uid 100002 
* ...
* uid 1000+65536 is allowed to map to uid 165536

This effectively lets all human, non-system users to map to a completely unrelated uid that is out of range for normal operation. This is how containers de-privilege users - inside containers, uids have values that are meaningless to the host system. It's also why you can't share files etc between the host and containers without some extra steps.

Those steps are adding rows to `/etc/subuid` and `/etc/subgid`. Let's say you wanted `ubuntu` on  the host to match `ubuntu` in the container. You could first get `ubuntu`'s uid (it's 1000 but let's do this right) ...
```
$ id --user ubuntu
1000
```
Then, we can add the following line to `/etc/subuid`
```
ubuntu:1000:1
```
This permits `ubuntu` to map to a uid of 1000 inside containers. This would allow the host to share a folder with a container, and any files on that host owned by `ubuntu` would be accessible to `ubuntu` inside the container as well.

Scripting the generation of `ubuntu:1000:1` and appending it to `/etc/subuid` is a little tricky but it's not too bad. Here's a sample -- note the part that does the actual work is just one line
```
$ cat /etc/subuid
ubuntu:100000:65536
$ usr=ubuntu printf '%s:%d:1\n' "$usr" "$(id --user "$usr")" | sudo tee --append /etc/subuid
ubuntu:1000:1
$ cat /etc/subuid
ubuntu:100000:65536
ubuntu:1000:1
```

The tricky bit is `sudo tee --append` to add lines to the end of a protected file. For confusing bash reasons, `sudo cat >>` doesn't work, so `sudo tee --append` is the bashism that is required.

Big Note: None of this has actually done any mapping of host *ids to container *ids. All we've done is permit this mapping to happen. The mapping itself happens at the container level.

### Part 2: The Container Part (`raw.idmap`)

Every container in lxd has an id map. By default it will map all host users to unprivileged users. To fix this, and map `ubuntu` to `ubuntu`, we need to manipulate the container's id map. The syntax for id maps is reminiscent of the syntax for `/etc/sub*id` files, but simpler and cleaner.
```
uid 1000 1000
gid 1000 1000
```
will take care of mapping uid+gid for user 1000 (aka `ubuntu`). Or, even more simpler
```
both 1000 1000
````
You can enter this in a simple text file, eg `/tmp/idmap.txt`, and then use `lxc config set` to set the idmap from your file


### One weird thing ...
... that I just learned. All this id stuff only matters for files you copy from host to container, or folders that you share from host to container.

Let's illustrate.

```
$ lxc launch ubuntu:22.04 ubu --profile basic
$ lxc launch ubuntu:22.04 ubu --profile basic
Creating ubu
Starting ubu

$ lxc exec ubu -- cloud-init status --wait

status: done

$ lxc exec ubu -- ls -al /home
total 3
drwxr-xr-x  3 root   root    3 May  3 17:29 .
drwxr-xr-x 18 root   root   24 Apr 27 02:15 ..
drwxr-x---  3 ubuntu ubuntu  6 May  3 17:29 ubuntu
$ lxc exec ubu -- ls -aln /home
total 3
drwxr-xr-x  3    0    0  3 May  3 17:29 .
drwxr-xr-x 18    0    0 24 Apr 27 02:15 ..
drwxr-x---  3 1000 1000  6 May  3 17:29 ubuntu
ubuntu@ovh2:/tmp/tlpi-dist/namespaces
```

We can see the usernames and ids on the container, and they are as expected. If we actually shell into the container we see the same thing

```
$ lxc shell ubu
root@ubu:~# ls -al /home
total 3
drwxr-xr-x  3 root   root    3 May  3 17:29 .
drwxr-xr-x 18 root   root   24 Apr 27 02:15 ..
drwxr-x---  3 ubuntu ubuntu  6 May  3 17:29 ubuntu
root@ubu:~# ls -aln /home
total 3
drwxr-xr-x  3    0    0  3 May  3 17:29 .
drwxr-xr-x 18    0    0 24 Apr 27 02:15 ..
drwxr-x---  3 1000 1000  6 May  3 17:29 ubuntu
```

This is container 101. Inside the container, we have the illusion of a `root` user and an `ubuntu` user and they behave as we expect.

```
$ echo hello >/tmp/hello.txt
$ lxc file push /tmp/hello.txt ubu/home/

$ echo funfunfun >/tmp/fun/fun.txt
$ cat /tmp/fun/fun.txt
funfunfun

$ lxc config device add ubu fun-folder disk source=/tmp/fun/ path=/home/fun/
Device fun-folder added to ubu
ubuntu@ovh2:/tmp/tlpi-dist/namespaces

$ lxc exec ubu -- ls -l /home/
total 5
drwxrwxr-x 2 nobody nogroup 4096 May  3 17:37 fun
-rw-rw-r-- 1 ubuntu ubuntu     6 May  3 17:34 hello.txt
drwxr-x--- 3 ubuntu ubuntu     6 May  3 17:29 ubuntu

$ lxc exec ubu -- ls -ln /home/
total 5
drwxrwxr-x 2 65534 65534 4096 May  3 17:37 fun
-rw-rw-r-- 1  1000  1000    6 May  3 17:34 hello.txt
drwxr-x--- 3  1000  1000    6 May  3 17:29 ubuntu

$ lxc exec ubu -- ls -l /home/fun
total 4
-rw-rw-r-- 1 nobody nogroup 10 May  3 17:37 fun.txt
ubuntu@ovh2:/tmp/tlpi-dist/namespaces

$ lxc exec ubu -- ls -ln /home/fun
total 4
-rw-rw-r-- 1 65534 65534 10 May  3 17:37 fun.txt
ubuntu@ovh2:/tmp/tlpi-dist/namespaces
ubuntu@ovh2:/tmp/tlpi-dist/namespaces
```

Files (and folders) lxc creates when it creates the container look good.

Files that lxc `file push`es to from host to container look good.

But the folder and its files that we shared from container to host ... they don't look so good.

Let's fix that.

### Back to the Container Side: id maps

Earlier we created a simple oneliner id map, with this one line
```
# Contents of /tmp/idmap.txt

both 1000 1000
```

We can set our container's id map to this file with the following command
```
# Set the id map
$ lxc config set ubu raw.idmap - < /tmp/idmap.txt

# Confirm it was set as expected -- seeing is believing
$ lxc config get ubu raw.idmap
both 1000 1000
```

Note the hyphen at the end of the `lxc config` command; that's a common bashism for receiving input from stdin. Its also a common source of hard-to-find mistakes.

If we want to get a little tricky, we can skip the whole file creation bit and do it all in this oneliner ...

```
lxc config set ubu raw.idmap "both $(id --user ubuntu) $(id --user ubuntu)"
```

Either gets the job done.

Now we can look at our files in the container again. Spoiler: we won't see any changes because we have to restart the container for the changes to go in to effect.

```
# Before restart - names and ids are bad
$ lxc exec ubu -- ls -l /home
total 5
drwxrwxr-x 2 nobody nogroup 4096 May  3 17:37 fun
-rw-rw-r-- 1 ubuntu ubuntu     6 May  3 17:34 hello.txt
drwxr-x--- 3 ubuntu ubuntu     6 May  3 17:29 ubuntu

$ lxc exec ubu -- ls -ln /home
total 5
drwxrwxr-x 2 65534 65534 4096 May  3 17:37 fun
-rw-rw-r-- 1  1000  1000    6 May  3 17:34 hello.txt
drwxr-x--- 3  1000  1000    6 May  3 17:29 ubuntu

$ lxc exec ubu -- ls -l /home/fun
total 4
-rw-rw-r-- 1 nobody nogroup 10 May  3 17:42 fun.txt

$ lxc exec ubu -- ls -ln /home/fun
total 4
-rw-rw-r-- 1 65534 65534 10 May  3 17:42 fun.txt

$ lxc restart ubu

$ lxc exec ubu -- ls -l /home
total 5
drwxrwxr-x 2 ubuntu ubuntu 4096 May  3 17:37 fun
-rw-rw-r-- 1 ubuntu ubuntu    6 May  3 17:34 hello.txt
drwxr-x--- 3 ubuntu ubuntu    6 May  3 17:29 ubuntu

$ lxc exec ubu -- ls -ln /home
total 5
drwxrwxr-x 2 1000 1000 4096 May  3 17:37 fun
-rw-rw-r-- 1 1000 1000    6 May  3 17:34 hello.txt
drwxr-x--- 3 1000 1000    6 May  3 17:29 ubuntu

$ lxc exec ubu -- ls -l /home/fun
total 4
-rw-rw-r-- 1 ubuntu ubuntu 10 May  3 17:42 fun.txt

$ lxc exec ubu -- ls -ln /home/fun
total 4
-rw-rw-r-- 1 1000 1000 10 May  3 17:42 fun.txt
```

Excellent! This is what we want to see.

Finally, to prove there's nothing magical about these numbers, let's map `ubuntu` to something strange.
```
# Map `ubuntu` to 6666
$ lxc config set ubu raw.idmap "both $(id --user ubuntu) 6666"

# Don't forget to restart!
$ lxc restart ubu

$ lxc exec ubu -- ls -l /home/
total 5
drwxrwxr-x 2   6666   6666 4096 May  3 17:37 fun
-rw-rw-r-- 1 ubuntu ubuntu    6 May  3 17:34 hello.txt
drwxr-x--- 3 ubuntu ubuntu    6 May  3 17:29 ubuntu
```

Note we see `6666` instead of `nobody` etc. That's because `nobody` is actually reserved fo the id 65535.

This is id maps.
