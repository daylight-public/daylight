Download `daylight.sh` to `/opt/bin`
```
sudo mkdir -p /opt/bin/
sudo chown -R ubuntu:ubuntu /opt/bin/
curl --silent --remote-name --output-dir /opt/bin https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
```

Use `daylight.sh` to install etcd
/opt/bin/daylight.sh etcd-install-latest
```

Use `daylight.sh` to install `watch-daylight` which will keep `daylight.sh` updated from etcd
/opt/bin/daylight.sh watch-daylight-install-service