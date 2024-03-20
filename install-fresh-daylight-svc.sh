url=https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
sudo mkdir -p /opt/bin/
sudo chown -R ubuntu:ubuntu /opt/bin/
curl --silent --remote-name --output-dir /opt/bin/ "$url"
chmod 777 /opt/bin/daylight.sh