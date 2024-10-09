### OVH

### IONOS
IONOS hosts come with a root user and a root password that you can view in the Web Admin console. This is the sort of machine generated initial password you'd expect to have to reset ... but it appears reseting the password is not actually enforced. The password is only 8 mixed-case alnum characters. This is not secure.

Changing the password is possible, but not supported through the IONOS console. It needs to be from the command line on the host.

Once this password is changed, and stored securely, we can proceed to setting up the system.

#### Before getting started
You will need a few things ready, before getting started.

- A secure password, stored in a secure password store.

Once these steps are complete, ssh into the host as root to complete setup. Start by setting a secure password.

```
$ ssh-keygen -R $vm
$ ssh root@$vm
$ ssh root@$vm "passwd"
$ scp ./etc/files.tgz root@$vm:/root
$ ssh root@$vm "tar -C / -xzf /root/files.tgz"
$ ssh root@$vm "adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu "
$ ssh root@$vm "/root/setup-ssh.sh"
$ ssh root@$vm "apt update -y && apt upgrade -y"
# apt update -y
# apt upgrade -y
# exit

$ scp ./etc/files.tgz root@$vm:/root
$ ssh root@$vm

# tar -C / -xzf /root/files.tgz
# adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu 
# /root/setup-ssh.sh
# exit

$ ssh ubuntu@$vm "sudo timedatectl set-timezone $timezone"
$ ssh ubuntu@$vm "sudo hostnamectl hostname $hostname"

```
In a terminal window
- A clone of this repo
- A terminal open on your local system to this repo
- A public key, for copying to the remote system to allow ssh
- A public key for SSH login saved to `./ubuntu.pem.pub`
- Environment variables set up for your new host
    - Fully qualified hostname (eg vm1.example.com)
    - Short hostname (eg vm1)
    - Timezone (eg US/Central)
```
$ git clone https://github.com/daylight
$ cp <your public key> ./ubuntu.pem.pub
$ vm=# your VM FQDN or IP
$ hostname=# your VM short hostname
$ timezone=# your VM timezone
$ tar -C ./etc/files/ -czf ./etc/files.tgz .
$ ssh-keygen -R $vm
$ scp ./etc/files.tgz root@$vm:/root
$ ssh root@$vm "tar -C / -xzf /root/files.tgz"
$ scp ./ubuntu.pem.pub root@$vm:/home/ubuntu/.ssh/
```


#### Create ubuntu user

```
# chown -R root:root /etc/sudoers.d/  
# chown -R root:root /etc/ssh/sshd_config.d/
```

IONOS VMs do not come with an ubuntu user. The ubuntu user will need to be created. This is true as of this writing. You may wish to confirm this is still true, before running `adduser` to create the user.

##### Confirm the ubuntu user doesn't exist
```
# id --user ubuntu
id: ‘ubuntu’: no such user
# id --user 1000
id: ‘1000’: no such user
```

##### Create the ubuntu user, and confirm they were propertly created.
```
# adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu
info: Adding user `ubuntu' ...
info: Adding new group `ubuntu' (1000) ...
info: Adding new user `ubuntu' (1000) with group `ubuntu (1000)' ...
warn: The home directory `/home/ubuntu' already exists.  Not touching this directory.
warn: Warning: The home directory `/home/ubuntu' does not belong to the user you are currently creating.info: Copying files from `/etc/skel' ...
info: Adding new user `ubuntu' to supplemental / extra groups `users' ...
info: Adding user `ubuntu' to group `users' ...

# adduser ubuntu sudo
info: Adding user `ubuntu' to group `sudo' ...

# id ubuntu
uid=1000(ubuntu) gid=1000(ubuntu) groups=1000(ubuntu)

# chown -R ubuntu:ubuntu /home/ubuntu/

# sudo --user ubuntu sudo ls /
```

**Good** - If successful, you'll see the contents of `/`
```
bin  boot  dev  etc  home  lib  lib32  lib64  libx32  lost+found  media  mnt  opt  proc  root  run  sbin  snap  srv  sys  tmp  usr  var
```

**Bad** - If there's a problem, you will be prompted for a password
```
[sudo] password for ubuntu:
```

#### Setup ubuntu user for password-free login and sudo

`ubuntu` has two main needs: password free ssh login, and sudo access.

These require copying specific files from your local system to specific locations on the remote host. One of these files is an SSH public key. You will need to provide this. The other files are in the `./etc/` folder in this repo.

Execute these commands from your local machine to copy the necessary files to the remote host. You will need to enter the root password separately for every command. This will be annoying. Fortunately, you're almost done having to use root on this host, perhaps ever.
```
# scp ./ubuntu.pub root@$vm:/home/ubuntu/.ssh/
# scp ./etc/files.tar.gz root@$vm:/tmp/
```

Confirm that sudo was set up properly for ubuntu.
```
# adduser ubuntu sudo
# sudo --user ubuntu sudo ls /
```

**Good** - If successful, you'll see the contents of `/`
```
bin  boot  dev  etc  home  lib  lib32  lib64  libx32  lost+found  media  mnt  opt  proc  root  run  sbin  snap  srv  sys  tmp  usr  var
```

**Bad** - If there's a problem, you will be prompted for a password
```
[sudo] password for ubuntu:
```

#### Setup ubuntu user for ssh login

On the remote host, as root
```
# mkdir -p /home/ubuntu/.ssh/
# chmod 700 /home/ubuntu/.ssh/
# touch /home/ubuntu/.ssh/authorized_keys
# chmod 600 /home/ubuntu/.ssh/authorized_keys
# cat /home/ubuntu/.ssh/ubuntu.pem.pub >> /home/ubuntu/.ssh/authorized_keys
# chown -R ubuntu:ubuntu /home/ubuntu/
# cp /tmp/sudoers.ubuntu /etc/sudoers.d/ubuntu
# cp /tmp/sshd_config.nopassword /etc/ssh/sshd_config.d/
# systemctl restart ssh
```

#### Set hostname, timezone, etc
$ ssh ubuntu@$vm "sudo timedatectl set-timezone $timezone"
$ ssh ubuntu@$vm "sudo hostnamectl hostname $hostname"

#### Speed run

For more advanced users, here's a more streamlined approach

# Prepare ./etc/files, including ssh info for root
(N/A)
# Clear out any previous ssh attempts
ssh-keygen -R $vm
# rsync files to the remote host
rsync -ah --info=progress2 ./etc/files/ root@$vm:/

Once the files are in place, it's possible to ssh in with no password. We only have to use the password once.

# Change the weak host password -- this is hard to do over ssh so we do it in a local session
# (if this forces us to expliticly refer to a ket with -i, we will try that next)
ssh root@$vm
passwd
# Run the script that takes care of all remaining steps
ssh -t root@$vm <./etc/run-on-host.ssh

passwd
apt update -y
apt upgrade -y
tar -C / -xzf /root/files.tgz
adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu
adduser ubuntu sudo
mkdir -p /home/ubuntu/.ssh/
chmod 700 /home/ubuntu/.ssh/
touch /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys
cat /home/ubuntu/.ssh/ubuntu.pem.pub >> /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/
systemctl restart ssh
timedatectl set-timezone US/Central
hostnamectl hostname ionos-vps2


# tar -C / -xzf /root/files.tgz
# adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu 
# /root/setup-ssh.sh
# exit




#### oddsy endsies
There is no ubuntu user, and no user with uid 1000.

One-liner to create ubuntu user

```
# adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu
```

This creates an account that cannot login over SSH via a password. An SSH key is required. That means the new account mush be configured with the public ket in its `~/.ssh/authorized_keys file. The commands to do this are in here

(from daylight.sh `install-public-key()`)
```
    # shellcheck disable=SC2016
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: install-public-key $username $publicKeyPath [$homeFolder]\n' >&2; return 1; }
    local username=$1
    local publicKeyPath=$2
    local homeFolder="${3:-/home/$username}"

    sudo mkdir -p "$homeFolder/.ssh"
    sudo touch "$homeFolder/.ssh/authorized_keys"
    # shellcheck disable=SC2024
    sudo tee --append "$homeFolder/.ssh/authorized_keys" <"$publicKeyPath" >/dev/null
    sudo chmod 700 "$homeFolder/.ssh"
    sudo chmod 600 "$homeFolder/.ssh/authorized_keys"
    sudo chown -R "$username:$username" "$homeFolder"
```

There are 2 other things I appear to have to do
- Change sshd_config, or add a file to sshd_config.d/
- Change sudoers, or add a file to sudoers.d/

1. Create the ubuntu user
```
# adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu
```
2. Add ubuntu to sudo
```
# adduser ubuntu sudo
```
3. Add ubuntu fragment to sudoers.d
4. Create .ssh stuff
5. scp pub key to ubuntu
6. create authorized_keys
7. scp sshd_fragment
8. Restart sshd


```
adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu
adduser ubuntu sudo
mkdir -p /home/ubuntu/.ssh
touch /home/ubuntu/.ssh/authorized_keys
chmod 700 /home/ubuntu/.ssh/
chmod 600 /home/ubuntu/.ssh/authorized_keys
cp /tmp/ionos-vms.pem.pub /home/ubuntu/.ssh/
cat /home/ubuntu/.ssh/ionos-vms.pem.pub >> /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/
cp /tmp/sudoers.ubuntu /etc/sudoers.d/ubuntu
cp /tmp/sshd_config.nopassword /etc/ssh/sshd_config.d/
systemctl restart ssh
```

```
ssh-keygen -R $ip_ionos_vps0
scp ./sshd_config.nopassword ./sudoers.ubuntu ~/.ssh/ionos-vms.pem.pub root@$ip_ionos_vps0:/tmp/ 
12  ls /etc/sudoers.d/
   13  cat  /etc/sudoers.d/sudoers.ubuntu
   14  vim /etc/sudoers.d/sudoers.ubuntu
   15  cat /etc/sudoers.d/sudoers.ubuntu
   16  visudo
   17  reboot
   18  cat /etc/sudoers.d/sudoers.ubuntu
   19  mv /etc/sudoers.d/sudoers.ubuntu /etc/sudoers.d/ubuntu
   20  cat /etc/sudoers/ubuntu /etc/sudoers.d/sudoers.ubuntu
   21  mv /etc/sudoers/ubuntu /etc/sudoers.d/sudoers.ubuntu
   22  mv /etc/sudoers.d/ubuntu /etc/sudoers.d/sudoers.ubuntu
   23  mv /etc/sudoers.d/sudoers.ubuntu /etc/sudoers.d/ubuntu  
```