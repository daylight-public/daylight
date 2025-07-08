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
```

### Use `daylight.sh` to install etcd
```
/opt/bin/daylight.sh etcd-install-latest
```

Use `daylight.sh` to install `watch-daylight` which will keep `daylight.sh` updated from etcd
/opt/bin/daylight.sh watch-daylight-install-service