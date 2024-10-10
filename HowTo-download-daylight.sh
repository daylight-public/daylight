To download `daylight.sh` to `/opt/bin` ...
```
curl --silent --remote-name --output-dir /opt/bin https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
```

To create the `daylight.sh` download folder, download `daylight.sh`, and install the `fresh-daylight` service to download updates ...
```
sudo mkdir -p /opt/bin/
sudo chown -R ubuntu:ubuntu /opt/bin/
curl --remote-name --output-dir /opt/bin https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
```

To download and run the script like a maniac ...
```
curl --silent /opt/bin/daylight.sh https://raw.githubusercontent.com/daylight-public/daylight/sentience/daylight.sh | bash
