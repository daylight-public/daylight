No VPS providers are quite the same. There are a few quirks to getting any new VPS in good shape for a nice standard initialization.

### Nice Standard Initialization

Cloud init has been rerun with a standard cloud-init config, and a few other manual steps if needed
     - Either make root account password-free, or change the password to something better and save it offline
     - Upload public key
     - Add a rayray system user
     - Install daylight.sh
     - Install fresh-daylight service
     - Create a btrfs partition
     - Setup zabbly incus packages
     - Install incus, using the new package
     - Add rayray to incus-admin

This could be done inside a per-boot script, which gets scp'd and then executed upon rebooting the server

#cloud-config
package_upgrade: true
packages:
  - bash
  - curl
  - gpg
  - openssh-server

users:
  - name: rayray
    gecos: 'rayray - daylight system user'
    shell: /bin/bash
    uid: 2000

runcmd:
  - mkdir -p /opt/bin
  - curl --silent https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh -o /opt/bin/daylight.sh
  - chmod 755 /opt/bin/daylight.sh
  - /opt/bin/daylight.sh init-rayray
  - /opt/bin/daylight.sh install-fresh-daylight-svc
  - /opt/bin/daylight.sh incus-install
  - /opt/bin/daylight.sh incus-create-profiles
  - adduser rayray incus-admin
  - /opt/bin/daylight.sh install-dylt
  - systemctl start ssh

# Do something about root password (TBD)

# Get btrfs partition good to go (@note - this will be manual for now)

### Setup daylight.sh


### setup rayray user

### Setup zabbly package stuff and install incus

# confirm fingerprint

# add package source

# install incus

# add rayray to incus admin group