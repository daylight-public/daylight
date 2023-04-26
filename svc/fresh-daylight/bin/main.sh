/bin/sh
printf '%s\n' "Installing daylight ..."
printf '%s\n' 
url=https://raw.githubusercontent.com/daylight-public/daylight/sentience/daylight.sh
curl --silent --remote-name --output-dir /opt/bin "$url"
printf '%s\n' Done.