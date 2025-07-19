### Install `daylight.sh`

#### On an Ubuntu VM
```
sudo mkdir -p /opt/bin/
sudo chown -R ubuntu:ubuntu /opt/bin/
curl --remote-name --output-dir /opt/bin https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
sudo chmod 777 /opt/bin/daylight.sh
```


#### On an Alpine container
```
apk add bash curl
mkdir -p /opt/bin/
curl --remote-name --output-dir /opt/bin https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
chmod 777 /opt/bin/daylight.sh
/opt/bin/daylight.sh init-alpine
```

#### On an Alpine incus container
```
incus init images:alpine/3.22/cloud al --network=col0
incus config set al user.user-data - < ./cfg/alpine.cfg
incus start al

# Test that container started correctly
incus exec al -- cloud-init status
incus exec al -- su - rayray -c 'sudo ls /etc/sudoers.d'
incus exec al -- su - rayray -c 'doas ls /etc/sudoers.d'
```

### Use `daylight.sh` to install etcd
```
/opt/bin/daylight.sh etcd-install-latest
```

Use `daylight.sh` to install `watch-daylight` which will keep `daylight.sh` updated from etcd
/opt/bin/daylight.sh watch-daylight-install-service