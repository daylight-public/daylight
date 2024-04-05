### OVH

### IONOS
IONOS hosts get setup with a root user, and a password that you can view in the Web Admin console. This is the sort of machine generated initial password you'd expect to have to reset ... but it appears reseting the password is not actually enforced. (The password also isn't that secure; 8 mixed-case alnum characaters).

Changing the password is possible, but perhaps better is to make it password-free.

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
# adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu
2. Add ubuntu to sudo
# adduser ubuntu sudo
3. Add ubuntu fragment to sudoers.d
4. Create .ssh stuff
5. scp pub key to ubuntu
6. create authorized_keys
7. scp sshd_fragment
8. Restart sshd


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