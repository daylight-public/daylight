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