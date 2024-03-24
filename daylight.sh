#! /usr/bin/env bash

activate-flask-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: activate-flask-app $name [$srcFolder]\n' >&2; return 1; }
    local name=$1

    activate-svc "flask@" "$name"
}


activate-svc ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: active-svc $name [$index] []\n' >&2; return 1; }
    local name=$1
    local index=${2:-''}
    # Confirm the service unit file exists
    if [[ -f "/etc/systemd/system/$name.service" ]]; then
        printf 'Service "%s" not found\n' "$serviceName"
        return 1
    fi
    # Get the serviceName - it's either the name param or it's the name param plus index
    local serviceName
    if [[ -z "$index" ]]; then
        serviceName=$name
    else
        if [[ ${name: -1} != '@' ]]; then
            printf 'Indexed service %s must end with '\''@'\''\n' "$name"
            return 1
        fi
        serviceName="$name$index"
    fi
    # Enable and start the service
    sudo systemctl enable "$serviceName"
    sudo systemctl start "$serviceName"
    # If there's a timer, enable and start the timer
    if [[ -f "/etc/systemd/system/$name.timer" ]]; then
        sudo systemctl enable "$serviceName.timer"
        sudo systemctl start "$serviceName.timer"
    fi
}


activate-vm ()
{
    # shellcheck disable=SC2016
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: activate-vm $name $folder [$instanceName] []\n' >&2; return 1; }
    local name=$1
    local srcFolder=$2
    local instanceName=${3:-$name}

    # Create the image, using the instance name
    lxc launch "$name" "$instanceName" || return
    # Run the finsihing-touches script
    if [[ -f "$srcFolder/finishing-touches.sh" ]]; then
        # shellcheck disable=SC1091
        source "$srcFolder/finishing-touches.sh"
    fi
}


add-container-user ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: add-container-user $username $container $publicKeyPath\n' >&2; return 1; }
    local username=$1
    local container=$2
    local publicKeyPath=$3

    # validation
    id --user "$username" >/dev/null 2>&1|| { printf 'User "%s" must exist on host system\n' "$username"; return 1; }
    [[ -f "$publicKeyPath" ]] || { echo "Non-existent path: $publicKeyPath" >&2; return 1; }

    # Create a home filesystem for the user/container
    # homePath="/mnt/home/$container/$username"
    # if [[ ! -d "$homePath" ]]; then
    #     local homeDir; homeDir=$(create-home-filesystem "$username" "$container") || return
    # fi

    # Get id-map for the container, concatenate rows to it for the new user, update the idmap
    add-user-to-idmap "$username" "$container" || return

    # Setup ownership in the home dir
    local uid; uid=$(id --user "$username") || return
    local gid; gid=$(id --group "$username") || return
    # lxc exec "$container" -- chown -R "$uid:$gid" "/home/$username" || return

    # Create group for the user, then add user: no home, set uid+gid -- and add to sudo2
    lxc exec "$container" -- addgroup --gid "$gid" "$username" || return
    lxc exec "$container" -- adduser --disabled-password --gecos '' --uid "$uid" --gid "$gid" "$username" || return
    lxc exec "$container" -- bash -l -c 'source /usr/bin/daylight.sh && { getent group sudo2 >/dev/null || create-sudo2-group; }' 
    lxc exec "$container" -- adduser "$username" sudo2 || return
    
    # Push the public key to the container, and invoke the public key setup function on the container
    local publicKeyName="${publicKeyPath##*/}"
    lxc file push "$publicKeyPath" "$container/tmp/$publicKeyName" || return
    lxc exec "$container" -- bash -l -c "source /usr/bin/daylight.sh && install-public-key /home/$username /tmp/$publicKeyName" || return
    
    # Setup the .bashrc so it sources daylight.sh
    lxc exec "$container" -- sh -c "printf 'source %s\n' \"$(command -v daylight.sh)\" | sudo tee --append \"/home/$username/.bashrc\""

    lxc exec "$container" -- chown -R "$username:$username" "/home/$username"

}


add-ssh-to-container ()
{
    # shellcheck disable=SC2016
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: add-ssh-to-container $container [$port]\n' >&2; return 1; }
    local container=$1
    local port=${2:-'22'}

    lxc config device add "$container" "ssh-$port" proxy listen=tcp:0.0.0.0:"$port" connect=tcp:127.0.0.1:22
}


add-superuser ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: $username $publicKeyPath\n' >&2; return 1; }
    local username=$1
    local publicKeyPath=$2

    # Check if user already exists
    id --user "$username" >/dev/null && { printf 'User "%s" exists\n' "$username"; return 1; }

    # Create the user -- normal home folder -- and add to sudo2
    sudo adduser --gecos -'' --disabled-password "$username"
    sudo adduser "$username" sudo2

    # Setup the user's public key to allow ssh
    install-public-key "/home/$username" "$publicKeyPath"
    sudo chown -R "$username:$username" "/home/$username"

    # Update /etc/subuid and /etc/subgid with the new user
    add-user-to-shadow-ids "$username"
}


add-user ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: $username $publicKeyPath\n' >&2; return 1; }
    local username=$1
    local publicKeyPath=$2

    # Check if user already exists
    id --user "$username" >/dev/null && { printf 'User "%s" exists\n' "$username"; return 1; }

    # Create the user: normal home folder, rbash
    sudo adduser --gecos -'' --disabled-password --shell /bin/false "$username"

    # Setup the user's public key to allow ssh
    install-public-key "/home/$username" "$publicKeyPath"
    sudo chown -R "$username:$username" "/home/$username"

    # Update /etc/subuid and /etc/subgid with the new user
    add-user-to-shadow-ids "$username"
}


add-user-to-idmap ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: add-user-to-idmap $username $container\n' >&2; return 1; }
    local username=$1
    local container=$2

    # Get id-map for the container, concatenate rows to it for the new user, update the idmap
    local newIdMap; newIdMap=$(mktemp) || return
    lxc query "/1.0/containers/$container" | jq -r '.expanded_config["raw.idmap"] // empty' | awk NF > "$newIdMap"

    local uid; uid=$(id --user "$username") || return
    local gid; gid=$(id --group "$username") || return
    printf 'uid %d %d\n' "$uid" "$uid" >> "$newIdMap"
    printf 'gid %d %d\n' "$gid" "$gid" >> "$newIdMap"

    lxc config set "$container" raw.idmap - < <(sort "$newIdMap" | uniq)
    lxc restart "$container" 2>/dev/null || lxc start "$container"
    lxc exec "$container" -- cloud-init status --wait
}


add-user-to-shadow-ids ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: add-user-to-shadow-ids $username\n' >&2; return 1; }
    local username=$1

    local uid; uid=$(id --user "$username") || return
    local gid; gid=$(id --group "$username") || return
    printf 'root:%d:1\n' "$uid" | sudo tee --append 2>/dev/null /etc/subuid
    printf 'root:%d:1\n' "$gid" | sudo tee --append 2>/dev/null /etc/subgid
    printf 'lxd:%d:1\n' "$uid" | sudo tee --append 2>/dev/null /etc/subuid
    printf 'lxd:%d:1\n' "$gid" | sudo tee --append 2>/dev/null /etc/subgid
    sudo systemctl restart snap.lxd.daemon
}


cat-conf-script ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: run-conf-script $name\n' >&2; return 1; }
    local name=$1

    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/conf.tgz"
    local confDir; confDir=$(download-to-temp-dir "$s3url") || return
    local scriptPath="$confDir/scripts/$name"
    [[ -f "$scriptPath" ]] || { echo "Non-existent path: $scriptPath" >&2; return 1; }
    cat "$scriptPath" || return
}


create-flask-app ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: create-flask-app $name $domain\n' >&2; return 1; }
    local name=$1
    local domain=$2

    systemctl cat "nginx" >/dev/null 2>&1 || { printf 'Non-existent service: %s\n' "nginx"; return;  }

    # Create an nginx file
    gen-nginx-flask "$name" "$domain" > "/etc/nginx/sites-available/$domain" || return
    ln --symbolic --force "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain" >/dev/null || return
    mkdir -p "/www/$domain" || return

    # Generate a cert w certbot
    if [[ ! -f "/etc/letsencrypt/live/$domain/cert.pem" ]]; then
        certbot certonly --standalone --domain "$domain" >/dev/null || return
    fi
}


create-github-user-access-token ()
{
    client_id=Iv1.f69b43d6e5f4ea24
    s="$(http --body POST https://github.com/login/device/code?client_id=$client_id | tail -n 1)"
    source <(python3 -m parse_query_string --names device_code user_code verification_uri --output env <<<"$s")
    # shellcheck disable=SC2154
    printf 'Please visit %s and enter the user code %s ...' "$verification_uri" "$user_code"
    read -r
    grant_type=urn:ietf:params:oauth:grant-type:device_code
    # shellcheck disable=SC2154
    s="$(http --body post "https://github.com/login/oauth/access_token?client_id=$client_id&device_code=$device_code&grant_type=$grant_type")"
    source <(python3 -m parse_query_string --names access_token refresh_token --output env <<<"$s")
}


create-home-filesystem ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: create-home-filesystem $username $container\n' >&2; return 1; }
    local username=$1
    local container=$2

    # Make folder for image file + home filesystem
    local containerDir="/mnt/home/$container"
    mkdir -p "$containerDir" >/dev/null || return

    # Create image file
    local imagePath="$containerDir/$username.img"
    sudo dd if=/dev/zero of="$imagePath" bs=1024 count=100K >/dev/null || return

    # Create loopback for image file
    local loopDev; loopDev=$(sudo losetup -f) || return
    sudo losetup -f "$imagePath" || return
    sudo mkfs -q -t ext4 "$loopDev" || return

    # Mount image file
    local homeDir="$containerDir/$username"
    mkdir -p "$homeDir" >/dev/null || return
    sudo mount "$loopDev" "$homeDir" || return

    # Set ownership on homeslice to user
    local uid; uid=$(id --user "$username") || return
    local gid; gid=$(id --group "$username") || return
    sudo chown -R "$uid:$gid" "$homeDir" || return
    
    # Create systemd mount unit file
    # TBD

    printf '%s' "$homeDir"
}



create-loopback ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: create-loopback $path $sizeInMegs\n' >&2; return 1; }
    local path=$1
    local sizeInMeg=$2
    
    # Confirm file doesn't exist
    [[ ! -f "$path" ]] || { printf 'Path already exists: %s\n' "$path" >&2; return 1; }
    # Create image file
    sudo dd if=/dev/zero of="$path" bs=1048576 count="$sizeInMeg" >/dev/null || return

    printf '%s' "$path"
}

#
# Create a cloud-init MIME including the special shellscript part-handlers (until they are a part of cloud-init!)
#
create-lxd-user-data ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: create-lxd-user-data $vmConfigDir\n' >&2; return 1; }

    local vmConfigDir=$1
    [[ -d "$vmConfigDir" ]] || { echo "Non-existent path: $vmConfigDir" >&2; return 1; }

    if  { [[ -f "$vmConfigDir/init-boot.sh" ]] && [[ -f "$vmConfigDir/init-instance.sh" ]]; }; then
        cloud-init devel make-mime --force \
                                --attach /usr/bin/shell_script_per_boot.py:part-handler \
                                --attach /usr/bin/shell_script_per_instance.py:part-handler \
                                --attach /usr/bin/shell_script_per_once.py:part-handler \
                                --attach "$vmConfigDir/init-boot.sh":x-shellscript-per-boot \
                                --attach "$vmConfigDir/init-instance.sh":x-shellscript-per-instance
    elif [[ -f "$vmConfigDir/init-boot.sh" ]]; then
        cloud-init devel make-mime --force \
                                --attach /usr/bin/shell_script_per_boot.py:part-handler \
                                --attach /usr/bin/shell_script_per_instance.py:part-handler \
                                --attach /usr/bin/shell_script_per_once.py:part-handler \
                                --attach "$vmConfigDir/init-boot.sh":x-shellscript-per-boot
    elif [[ -f "$vmConfigDir/init-instance.sh" ]]; then
        cloud-init devel make-mime --force \
                                --attach /usr/bin/shell_script_per_boot.py:part-handler \
                                --attach /usr/bin/shell_script_per_instance.py:part-handler \
                                --attach /usr/bin/shell_script_per_once.py:part-handler \
                                --attach "$vmConfigDir/init-instance.sh":x-shellscript-per-instance
    else
        printf 'Could not find either %s or %s\n' "$vmConfigDir/init-boot.sh" "$vmConfigDir/init-instance.sh"
        return 1
    fi
}


#
# Take a vm name, and a base image, and generate a service for publishing that image.
# TODO complete this function
create-publish-image-service ()
{
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: create-publish-image-service $vm $base [$imageRepo]\n' >&3; return 1; }
    local vm=$1
    local base=$2
    local imageRepo=${3:-'local'}

    local service="publish-$vm"
    local cmd="/usr/bin/daylight.sh install-vm \"$vm\" \"$base\" \"$imageRepo\""
    install-service-from-command "$service" "$cmd"
}


#
# Given the name of the script in $dist/conf/scripts, create a one-off service
# Beging by downloading dist and extracting conf.
#
create-service-from-dist-script ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: create-service-from-dist-script $script\n' >&2; return 1; }
    local script=$1
    shift

    local bucket; bucket=$(get-bucket) || return
    # Download & untar dist/conf.tgz from S3
    local s3Url="s3://$bucket/dist/conf.tgz"
    local srcFolder; srcFolder="$(download-to-temp-dir "$s3Url")" || return

    # Create a one-off service from the specified script in $srcFolder/scripts
    local serviceScriptPath="$srcFolder/scripts/$script"
    [[ -f "$serviceScriptPath" ]] || { echo "Non-existent path: $serviceScriptPath" >&2; return 1; }
    install-service-from-script "$serviceScriptPath" "$@"
}


create-static-website ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: create-static-website $domain $email\n' >&2; return 1; }
    local domain=$1
    local email=$2

    systemctl cat "nginx" >/dev/null 2>&1 || { printf 'Non-existent service: %s\n' nginx; return 1; }

    # Create an nginx file
    gen-nginx-static "$domain" > "/etc/nginx/sites-available/$domain" || return
    ln --symbolic --force "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain" >/dev/null || return
    mkdir -p "/www/$domain" || return

    # Generate a cert w certbot
    if [[ ! -f "/etc/letsencrypt/live/$domain/cert.pem" ]]; then
        certbot certonly --standalone --email "$email" --agree-tos --domain "$domain" >/dev/null || return
    fi
}


create-sudo2-group ()
{
    sudo addgroup --gid 2000 sudo2
    echo "%sudo2   ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee --append >/dev/null /etc/sudoers.d/%sudo2
}


#
# lxd does not have a nice way of safely deleting a VM if it does not exist; you end up with
# a non-zero RC. This function simply checks that the VM exists before foricbly deleting it.
#
delete-lxd-instance ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: delete-lxd-instance $vm\n' >&2; return 1; }
    local vm=$1

    if lxc info "$vm" >/dev/null 2>&1; then
        lxc delete --force "$vm" 2>/dev/null || return
    fi
}

download-app ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-app $name\n' >&2; return 1; }
    local name=$1

    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/app/$name.tgz"
    local tempDir; tempDir=$(download-to-temp-dir "$s3url") || return

    printf '%s' "$tempDir"
}


#
# Download the entire dist folder from S3 to /tmp/dist
#
download-dist ()
{
    local bucket; bucket=$(aws sts get-caller-identity --query 'Account' --output text) || return
    if [[ -d /tmp/dist ]]; then
        rm -rf /tmp/dist || return
    fi
    mkdir -p /tmp/dist || return
    aws s3 cp --recursive "s3://$bucket/dist" /tmp/dist || return
    find /tmp/dist -type f -name "*.sh" -exec chmod 777 {} \; || return
}


download-flask-app ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-flask-app $name\n' >&2; return 1; }
    local name=$1

    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/flask/$name.tgz"
    local tempDir; tempDir=$(download-to-temp-dir "$s3url") || return

    printf '%s' "$tempDir"
}


#
# Download a flask service from S3
# TODO Either finish this function, or delete it because it doesn't do anything different from download-svc
download-flask-service ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-flask-service $name\n' >&2; return 1; }
    local name=$1

    local bucket; bucket=$(get-bucket) || return
    local s3Url="s3://$bucket/dist/$name.tgz"
    local dir; dir=$(download-to-temp-dir "$s3Url") || return

    printf '%s' "$dir"
}


download-public-key ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-public-key $name\n' >&2; return 1; }
    local name=$1
    if [[ ! $name =~ \,pub$ ]]; then
        name="$name.pub"
    fi
    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/ssh.tgz"
    local srcFolder; srcFolder=$(download-to-temp-dir "$s3url") || return
    cp "$srcFolder/$name" "./$name"
}


download-shr-tarball ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-shr-tarball $targetFolder\n' >&2; return 1; }
    local downloadFolder=$1
    local urlLatestRelease="https://api.github.com/repos/actions/runner/releases/latest"
    local tarballFileName tarballUrl
    local args
    read -r -a args < <(curl --silent "$urlLatestRelease" | jq -r '.assets[]? | select(.name | test("^actions-runner-linux-x64.*\\d\\.tar.gz$")) | [.name, .browser_download_url] | @tsv') || return
    tarballFileName=${args[0]}
    tarballUrl=${args[1]}
    local tarballPath; tarballPath="$(mktemp -t "XXX.$tarballFileName")" || return
    curl --location --silent --output "$tarballPath" "$tarballUrl"
    tar --list --gunzip --file "$tarballPath" >/dev/null
    tar --directory "$downloadFolder" --extract --gunzip --file "$tarballPath" || return
    printf '%s' "$downloadFolder" 
}


download-svc ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-svc $name\n' >&2; return 1; }
    local name=$1
    local bucket; bucket=$(get-bucket) || return
    local s3Url="s3://$bucket/dist/svc/$name.tgz"
    local tempDir; tempDir=$(download-to-temp-dir "$s3Url") || return

    printf '%s' "$tempDir"
}


download-to-temp-dir ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-to-temp-dir $s3Url\n' >&2; return 1; }
    local s3Url=$1

    local tempDir; tempDir=$(mktemp -d) || return
    aws s3 cp "$s3Url" - | tar -C "$tempDir" -xzf - >/dev/null || return

    printf '%s' "$tempDir"
}


download-vm ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-vm $name\n' >&2; return 1; }
    local name=$1

    local bucket; bucket=$(get-bucket) || return
    local s3Url="s3://$bucket/dist/vm/$name.tgz"
    local tempDir; tempDir=$(download-to-temp-dir "$s3Url") || return

    printf '%s' "$tempDir"
}


edit-daylight ()
{
	local daylightPath; daylightPath=$(command -v daylight.sh)
	vim "$daylightPath"
	source-daylight
	read -r -p "Push changes [Y/n]? " yn
	if [[ -z "$yn" ]] || [[ $yn = [Yy] ]]; then
		push-daylight
	fi
}



gen-nginx-flask ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: gen-nginx-static $name $domain\n' >&2; return 1; }
    local name=$1
    local domain=$2

    # shellcheck disable=SC2154
    cat <<EOD
server {
	listen 80;
	listen [::]:80;
	server_name $domain;
	return 301 https://$host$request_uri;
}

server {
	listen [::]:443 ssl; # managed by Certbot
	listen 443 ssl; # managed by Certbot

	server_name $domain;
	root /www/$domain;

 	location /
	{
		include proxy_params;
		proxy_pass http://unix:/app/flask/$name/app.sock;
	}

	ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem; # managed by Certbot
	ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem; # managed by Certbot
	include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
	ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
EOD
}


gen-nginx-static ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: gen-nginx-static $domain\n' >&2; return 1; }
    local domain=$1

    cat <<EOD
server {
	listen 80;
	listen [::]:80;
	server_name $domain;
	return 301 https://\$host\$request_uri;
}

server
{
	listen unix:/www/$domain.sock;
	root /www/$domain;
}


server
{
	listen 80;
	listen [::]:80;
	listen 443 ssl; # managed by Certbot
	listen [::]:443 ssl; # managed by Certbot
	
	server_name $domain;
	root /www/$domain;

	location /
	{
		include proxy_params;
		proxy_pass http://unix:/www/$domain.sock;
	}

	ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem; # managed by Certbot
	ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem; # managed by Certbot
	include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
	ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}
EOD
}

# Necessary Ugliness! Generate a systemd unit file for a simple one-shot service
# Used by multiple other functions which generate services
#
generate-unit-file ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: generate-unit-file $cmd $description [$args]\n' >&2; return 1; }
    local cmd=$1
    local description=$2
    shift 2;

    cat <<EOD
[Unit]
Description=$description

[Service]
User=ubuntu
Type=oneshot
ExecStart=$cmd $@

[Install]
WantedBy=multi-user.target
EOD
}


get-bucket ()
{
    local bucket; bucket=$(aws sts get-caller-identity --query 'Account' --output text) || return

    printf '%s' "$bucket"
}


get-container-ip ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-container-ip $container\n' >&2; return 1; }
    local container=$1

    lxc query "/1.0/containers/$container/state" | jq -r '.network.eth0.addresses[] | select(.family=="inet").address'
}


get-image-base ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-iamge-base $vmConfigFolder\n' >&2; return 1; }
    local srcFolder=$1

    [[ -d "$srcFolder" ]] || { echo "Non-existent folder: $srcFolder" >&2; return 1; }
    local path="$srcFolder/config.json"
    [[ -f "$path" ]] || { echo "Non-existent path: $path" >&2; return 1; }
    local base; base=$(jq -r '.base' "$path") || return
    printf '%s' "$base"
}


get-image-name ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-image-name $vmConfigFolder\n' >&2; return 1; }
    local srcFolder=$1

    local base; base=$(get-image-base "$srcFolder") || return
    local name="${base##*:}"
    printf '%s' "$name"
}


get-image-repo ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-image-repo $vmConfigFolder\n' >&2; return 1; }
    local srcFolder=$1

    local base; base=$(get-image-base "$srcFolder") || return
    local repo="${base%%:*}"
    printf '%s' "$repo"
}


# Parse `systemctl cat` for the given service and return the value for the given key
get-service-file-value ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: get-service-working-directory $serviceName $key\n' >&2; return 1; }
    local name=$1
    local key=$2
    
    systemctl cat "$name" >/dev/null || { printf 'Service not found: %s\n' "$name"; return 1; }
    local rx="^$key=(.*)"
    while read -r line; do
        if [[ "$line" =~ $rx ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return
        fi
    done < <(systemctl cat "$name")

}


# Extract the environment file path from the service definition
# aka the 'EnvironmentFile' value
get-service-environment-file ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-service-environment-file $serviceName\n' >&2; return 1; }
    local name=$1

    get-service-file-value "$name" 'EnvironmentFile'
}


# Extract the executable command line definition from the service definition
# aka the 'ExecStart' value
get-service-exec-start ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-service-exec-start $serviceName\n' >&2; return 1; }
    local name=$1

    get-service-file-value "$name" 'ExecStart'
}


# Extract the working directory from the service definition
# aka the 'WorkingDirectory' value
get-service-working-directory ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-service-working-directory $serviceName\n' >&2; return 1; }
    local name=$1

    get-service-file-value "$name" 'WorkingDirectory'
}


init-lxd ()
{
    # Remove the packaged lxc/d since it causes problems
    apt-get remove -y lxd lxd-client liblxc-common liblxc-dev liblxc1 lxc-dev lxcfs nova-compute-lxc
    # Setup subuid+subgid to allow for mapping ubuntu
    add-user-to-shadow-ids ubuntu
    # Setup /dev/xvdf as a btrfs volume, then bind mount it onto the lxd images folder
    [[ -b "/dev/xvdf" ]] || { echo "Non-existent device: /dev/xvdf" >&2; return 1; }
    mkfs -t btrfs /dev/xvdf || return
    mkdir -p /mnt/data/lxd || return
    mount /dev/xvdf /mnt/data/lxd || return
    mkdir /mnt/data/lxd/images || return
    # Install the lxd snap
    snap install lxd || return
    # Initialize lxd with btrfs and use the volume on /dev/xvdg for lxd stuff
    [[ -b "/dev/xvdg" ]] || { echo "Non-existent device: /dev/xvdg" >&2; return 1; }
    lxd init --auto --storage-backend btrfs --storage-create-device /dev/xvdg --storage-pool default || return
    # Bind mount the images folder from above and restart lxd
    mount -o bind /mnt/data/lxd/images /var/snap/lxd/common/lxd/images || return
    snap restart lxd || return
    # Setup xvdh to be the volume for instance home dirs
    [[ -b "/dev/xvdh" ]] || { echo "Non-existent device: /dev/xvdh" >&2; return 1; }
    mkfs -t ext4 /dev/xvdh
    mkdir -p /mnt/home
    mount /dev/xvdh /mnt/home
    chown -R ubuntu:ubuntu /mnt/home
    # profile: map ubuntu from host to container
    lxc profile create map-ubuntu || return
    local uid; uid=$(id --user ubuntu) || return
    local gid; gid=$(id --group ubuntu) || return
    lxc profile set map-ubuntu raw.idmap - < <(printf 'uid %d %d\ngid %d %d\n' "$uid" "$uid" "$gid" "$gid") || return
    # profile: serve HTTP/S
    lxc profile create www || return
    lxc profile device add www https proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443 || return
    lxc profile device add www http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80 || return
# }

    # install the shell script handlers ... clunky but it'll do for now
    aws s3 cp --recursive --exclude "*" --include "shell_script_per_*.py" "s3://$bucket/conf/scripts" /usr/bin
}


init-nginx ()
{
    :
    # The trickiest part here is getting the initial certbot params installed. I'm not actually sure that will work; this will be
    # my first try.

    # install nginx

    # install certbot snap

    # Check that the certbot files are where they need to be
    # If they are, copy them to /etc/letsencrypt
}


install-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: install-app $name $srcFolder [$dstFolder]\n' >&2; return 1; }
    local name=$1
    local srcFolder=$2
    local dstFolder=${3:-"/app/$PWD/$name"}

    mkdir -p "$dstFolder"
    # rsync it where it needs to go
    rsync --archive "$srcFolder/" "$dstFolder"
}


install-awscli ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: install-awscli $defaultRegion\n' >&2; return 1; }
    local defaultRegion=$1

    # Install AWS CLI
    apt-get install -y awscli || return
    # Setup AWS, download bootstrap.sh, and source it
    aws configure set default.region "$defaultRegion" || return
    # This command needs to be run as ubuntu, since we want to set the ubuntu user's default region
    su ubuntu --login --command "aws configure set default.region $defaultRegion" || return
}


install-flask-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: install-flask-app $name $srcFolder [$dstFolder]\n' >&2; return 1; }
    local name=$1
    local srcFolder=$2
    local dstFolder=${3:-"/app/flask/$name"}

    # rsync it where it needs to go
    rsync --archive "$srcFolder/" "$dstFolder"
    # Create the venv
    local venvPath="$dstFolder/venv"
    python3 -m venv "$venvPath" >/dev/null || return
    "$venvPath/bin/pip" install --upgrade pip || return
    "$venvPath/bin/pip" install wheel || return
    "$venvPath/bin/pip" install --requirement "$dstFolder/requirements.txt"
    # Create the log folder
    mkdir -p "$dstFolder/log" >/dev/null || return
}


install-fresh-daylight-svc ()
{
    repo=https://raw.githubusercontent.com/daylight-public/daylight/main
    sudo mkdir -p /opt/svc/fresh-daylight/bin 
    sudo chown -R ubuntu:ubuntu /opt/svc/fresh-daylight
    curl --silent --remote-name --output-dir /opt/svc/fresh-daylight "$repo/svc/fresh-daylight/fresh-daylight.service"
    curl --silent --remote-name --output-dir /opt/svc/fresh-daylight "$repo/svc/fresh-daylight/fresh-daylight.timer"
    curl --silent --remote-name --output-dir /opt/svc/fresh-daylight/bin "$repo/svc/fresh-daylight/bin/main.sh"
    chmod 777 /opt/svc/fresh-daylight/bin/main.sh
    sudo systemctl enable /opt/svc/fresh-daylight/fresh-daylight.service
    sudo systemctl enable /opt/svc/fresh-daylight/fresh-daylight.timer
    sudo systemctl start fresh-daylight.timer
}


install-gnome-keyring ()
{
	sudo apt-get install libsecret-1-0 libsecret-1-dev
	make -C /usr/share/doc/git/contrib/credential/libsecret
	git config --global credential.helper /usr/share/doc/git/contrib/credential/libsecret/git-credential-libsecret
}


install-latest-httpie ()
{
    curl -SsL -o /etc/apt/sources.list.d/httpie.list https://packages.httpie.io/deb/httpie.list
    curl -SsL https://packages.httpie.io/deb/KEY.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/httpie.gpg >/dev/null
    apt update -y
    apt install -y httpie
}


install-mssql-tools ()
{
    curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
    apt-get -y update
    sudo ACCEPT_EULA=Y apt-get install -y mssql-tools
}


install-public-key ()
{
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
}


install-python ()
{
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update -y
    apt-get install -y python3 python3-dev python3-pip python3-testresources python3-venv
    pip3 install --upgrade pip setuptools wheel
}


#
# Given a tar, create a service folder, copy the tars contents to the service folder, and create
# symlinks in /etc/systemd/system as needed.
# Support services which include a .timer file as well as a .service unit file.
#
#
install-service ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: configure-service $service $serviceTarball\n' >&2; return 1; }
    local service=$1
    local serviceTarball=$2

    [[ -f "$serviceTarball" ]] || { printf 'Non-existent service tar: %s\n' "$serviceTarball" >&2; return 1; }
    # Create a service folder & untar the service tar into the new folder
    local dst="/app/svc/$service"
    mkdir -p "$dst"
    tar -C "$dst" -xf "$serviceTarball"
    # Create symlinks in /etc/sysd/sys to the files in the tar folder - .service and optionally .timer
    sudo ln --force --symbolic "$dst/$service.service" /etc/systemd/system
    if [[ -f "$dst/$service.timer" ]]; then
        sudo ln --force --symbolic "$dst/$service.timer" /etc/systemd/system
    fi
}


#
# Take a script, and turn it into a systemd service, by creating a service folder, copying the script there, and
# generating a unit file.
#
install-service-from-script ()
{
    # shellcheck disable=SC2016
    (( $# >= 1 )) || { printf 'Usage: install-service-from-script $serviceScriptPath [$args]\n' >&2; return 1; }
    local serviceScriptPath=$1
    # Set $@ = $args
    shift 

    # Validation
    [[ -f "$serviceScriptPath" ]] || { echo "Non-existent path: $serviceScriptPath" >&2; return 1; }
    # Get the service file, and infer the service name if not specified
    local serviceScriptFile=${serviceScriptPath##*/}
    local service=${serviceScriptFile%.*}

    # 'Install' the service - Create a service folder, copy the script to $serviceFolder/run.sh, and gen a .service file
    local serviceFolder="/app/svc/$service"
    sudo mkdir -p /app || return
    sudo chown -R ubuntu:ubuntu /app || return
    mkdir -p "$serviceFolder" "$serviceFolder/bin" || return
    cp "$serviceScriptPath" "$serviceFolder/bin/$serviceScriptFile" || return
    chmod 777 "$serviceFolder/bin/$serviceScriptFile" || return
    # Generate the unit file
    local description="One-off service for $serviceScriptFile"
    local cmd="$serviceFolder/bin/$serviceScriptFile $*"
    generate-unit-file "$cmd" "$description" >"$serviceFolder/$service.service"

    # Create a symlink in /etc/sysd/sys to the new service in its new home
    sudo ln --force --symbolic "$serviceFolder/$service.service" "/etc/systemd/system/$service.service"

    # Done!
    printf '%s' "$service"
}


#
# Take a script, and turn it into a systemd service, by creating a service folder, copying the script there, and
# generating a unit file.
#
install-service-from-command ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: install-service-from-script $service $cmd [$cmdArg1 ... $cmdArgN]\n' >&2; return 1; }
    local service=$1
    # Set $@ = $args
    shift 

    # 'Install' the service - Create a service folder, copy the script to $serviceFolder/run.sh, and gen a .service file
    local serviceFolder="/app/svc/$service"
    mkdir -p "$serviceFolder" "$serviceFolder" || return
    chmod 777 "$serviceFolder" || return
    # Generate the unit file
    local cmd="$*"
    local description="One-off service for command"
    generate-unit-file "$cmd" "$description" >"$serviceFolder/$service.service"
    chown -R ubuntu:ubuntu "$serviceFolder"|| return

    # Create a symlink in /etc/sysd/sys to the new service in its new home
    sudo ln --force --symbolic "$serviceFolder/$service.service" "/etc/systemd/system/$service.service"

    # Done!
    printf '%s' "$service"
}


#
# I'm thinking this might have to be part of daylight.
#
install-shellscript-part-handlers ()
{
    download-dist || return
    srcFolder=$(untar-to-temp-folder /tmp/dist/conf.tgz)
    cp "$srcFolder"/scripts/shell_script_per_*.py /usr/bin
    # chown ubuntu:ubuntu /usr/bin/shell_script_per_*.py
}


install-shr-token ()
{
    # shellcheck disable=SC2016
    (( $# == 5 )) || { printf 'Usage: install-shr-token $org $repoName $svcName $shr_access_token $labels\n' >&2; return 1; }
    org=$1
    repoName=$2
    svcName=$3
    shr_access_token=$4
    labels=$5
    # Create SHR folder + download GH SHR tarball
    local shrHome="/opt/actions-runner"
    local shrFolder="$shrHome/$svcName"
    mkdir -p "$shrFolder"
    download-shr-tarball "$shrFolder"
    # Redeem SHR Access Token for SHR Registration Token and install the SHR
    repoUrl="https://github.com/$org/$repoName"
    apiUrl="https://api.github.com/repos/$org/$repoName/actions/runners/registration-token"
    shrToken=$(http post "$apiUrl" "Authorization: token $shr_access_token" accept:application/json | jq -r '.token')
    cd "$shrFolder" || return
    chown -R ubuntu:ubuntu "$shrHome"
    if [[ -f ./svc.sh ]] && ./svc.sh status >/dev/null; then
        ./svc.sh uninstall
        su -c "./config.sh remove --token $shrToken" ubuntu
    fi
    su -c "./config.sh --unattended \
          --url $repoUrl \
          --token $shrToken \
          --replace \
          --name ubuntu-dev \
          --labels $labels" \
          ubuntu
    # Install the SHR as a service
    ./svc.sh install
    ./svc.sh start
}


install-svc ()
{
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: install-svc $name $srcFolder [$dstFolder]\n' >&2; return 1; }
    local name=$1
    local srcFolder=$2
    local dstFolder=${3:-"/app/svc/$name"}

    # Create the local service folder; copy the .service and the .env if present
    mkdir -p "$dstFolder"
    cp "$srcFolder/$name.service" "$dstFolder" || return
    if [[ -f "$srcFolder/.env" ]]; then
        cp "$srcFolder/.env" "$dstFolder"
    fi
    # Copy the local service bin folder if present
    if [[ -d "$srcFolder/bin" ]]; then
        mkdir -p "$dstFolder/bin"
        cp "$srcFolder"/bin/* "$dstFolder/bin"
    fi
    # Create symlinks in /etc/systemd/system for the .service and .timer if present
    ln --force --symbolic "$dstFolder/$name.service" "/etc/systemd/system/$name.service"
    if [[ -f "$srcFolder/$name.timer" ]]; then
        cp "$srcFolder/$name.timer" "$dstFolder" || return
        ln --force --symbolic "$dstFolder/$name.timer" "/etc/systemd/system/$name.timer"
    fi

    printf '%s' "$dstFolder"
}


install-venv ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: create-venv $name $s3Url\n' >&2; return 1; }
    local name=$1
    local s3Url=$2

    local srcFolder; srcFolder=$(download-to-temp-dir "$s3Url") || return
    local venvParentFolder=/app/venv
    mkdir -p "$venvParentFolder" >/dev/null || return
    local venvFolder="$venvParentFolder/$name"
    python3 -m venv "$venvFolder"
    local pipPath="$venvFolder/bin/pip"
    $pipPath install wheel >/dev/null || return
    $pipPath install --requirement "$srcFolder/requirements.txt" >/dev/null || return
}


#
# Given a vm name, a base, and an optional imageRepo, create an instance and publish it.
# This assumes the vm init scripts are in $dist/conf/vm/$vm
#
install-vm ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: install-vm $image $srcFolder\n' >&2; return 1; }
    local image=$1
    local srcFolder=$2
    
    [[ -d "$srcFolder" ]] || { echo "Non-existent folder: $srcFolder" >&2; return 1; }
    local imageBase; imageBase=$(get-image-base "$srcFolder") || return
    # The base and the image can be of the form repo:name or just name.
    # Dealing with that is simple but it takes a few lines of bash.
    local imageRepo
    local imageName
    if [[ "$image" == *:* ]]; then
        imageRepo="${image%%:*}"
        imageName="${image##*:}"
    else
        imageRepo='local'
        imageName="$image"
    fi

    local userDataPath; userDataPath=$(mktemp) >/dev/null || return
    create-lxd-user-data "$srcFolder" >"$userDataPath" || return
    local instanceName; instanceName=$(mktemp --dry-run "$imageName-XXXXXXXX") || return
    local instance="$imageRepo:$instanceName"
    # Launch an instance with the new user data
    lxc init "$imageBase" "$instance" || return
    lxc config set "$instance" user.user-data - <"$userDataPath" || return
    lxc start "$instance" || return
    lxc exec "$instance" -- cloud-init status --wait || return
     # Publish the instance as an instance
    lxc stop "$instance" || return
    lxc publish "$instance" "$imageRepo:" --alias "$imageName" || return
    lxc delete "$instance" || return
    # # Download all the dists ... or maybe just the right one.
    # download-dist || return
    # # Create user-data for the desired VM
    # local configDir="/tmp/dist/vm/$vm"
    # mkdir -p "$configDir" || return
    # tar -C "$configDir" -xvf "/tmp/dist/vm/$vm.tgz" || return
    # local userDataPath; userDataPath=$(mktemp) >/dev/null || return
    # create-lxd-user-data "$configDir" >"$userDataPath" || return
    # # Delete the instance if it exists (lxd does not provide a cleaner, RC=0 solution)
    # delete-lxd-instance "$vm"
    # # Launch an instance with the new user data
    # lxc init "$base" "$vm" || return
    # lxc config set "$vm" user.user-data - <"$userDataPath" || return
    # lxc start "$vm" || return
    # lxc exec "$vm" -- cloud-init status --wait || return
    # # Publish the instance as an image
    # lxc stop "$vm" || return
    # lxc publish "$vm" "$imageRepo:" --alias "$vm" || return
    # [[ -f "$userDataPath" ]] || { echo "Non-existent path: $userDataPath" >&2; return 1; }
}


list-apps ()
{
    local bucket; bucket=$(get-bucket) || return
    aws s3api list-objects --bucket "$bucket" --prefix 'dist/app' --query 'Contents[].Key[]' | jq -r '.[] | match("^dist/app/(.*)\\.tgz$").captures[0].string' || return
}


list-conf-scripts ()
{
    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/conf.tgz"
    local confDir; confDir=$(download-to-temp-dir "$s3url") || return
    local scriptDir="$confDir/scripts"
    [[ -d "$scriptDir" ]] || { printf 'Non-existent folder: %s\n' "$scriptDir" >&2; return 1; }
    ls -1 "$scriptDir"
}


list-public-keys ()
{
    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/ssh.tgz"

    aws s3 cp "$s3url" - | tar -tzf - | while read -r f; do [[ $f =~ .*/$ ]] || printf '%s\n' "${f##*/}"; done
}


list-services ()
{
    local bucket; bucket=$(get-bucket) || return
    aws s3api list-objects --bucket "$bucket" --prefix 'dist/svc' --query 'Contents[].Key' | jq -r '.[] | match("^dist/svc/(.*)\\.tgz$").captures[0].string'
}


list-vms ()
{
    local bucket; bucket=$(get-bucket) || return
    aws s3api list-objects --bucket "$bucket" --prefix 'dist/vm' --query 'Contents[].Key[]' | jq -r '.[] | match("^dist/vm/(.*)\\.tgz$").captures[0].string' || return
}


pull-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 0 )) && (( $# <= 2 )); } || { printf 'Usage: pull-svc [$name [$dstFolder]]\n' >&2; return 1; }
    local name dstFolder
    if [[ $# == 0 ]]; then
        dstFolder=$PWD
        name=${PWD##*/}
    else
        name=$1
        dstFolder=${2:-"$PWD/$name"}
    fi

    local srcFolder; srcFolder=$(download-app "$name") || return
    install-app "$name" "$srcFolder" "$dstFolder" >/dev/null || return
}


#
# Download and source the latest daylight.sh from S3. Crucial for debugging.
#
pull-daylight ()
{
    curl -s https://raw.githubusercontent.com/daylight-public/daylight/master/daylight.sh >/usr/bin/daylight.sh
    chmod 777 /usr/bin/daylight.sh
    source /usr/bin/daylight.sh
}


pull-flask-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: pull-flask-app $name [$dstFolder]\n' >&2; return 1; }
    local name=$1
    local dstFolder=${2:-"/app/flask/$name"}

    local srcFolder; srcFolder=$(download-flask-app "$name") || return
    install-flask-app "$name" "$srcFolder" >/dev/null || return
}


pull-git-repo ()
{
	local repoUrl=$1
	local username=${2:-''}
	local token=${3:-''}

	if [[ -z "$username" ]]; then
		read -r -p 'GitHub username: ' username
	fi

	if [[ -z "$token" ]]; then
		if [[ -n "$GITHUB_ACCESS_TOKEN" ]]; then
			token="$GITHUB_ACCESS_TOKEN"
		else
			read -r -p 'GitHub Access Token: ' token
		fi
	fi

	[[ -n "$username" ]] || { printf 'Invalid username\n'; return 1; }
	[[ -n "$token" ]] || { printf 'Invalid token\n'; return 1; }
			

 	local RX_repoUrl="^https://github.com/([^/]*)/([^/]*)";
 	[[ "$repoUrl" =~ $RX_repoUrl ]] || return;
 	local account="${BASH_REMATCH[1]}";
 	local repo="${BASH_REMATCH[2]}";
	local repoUrl="https://$username:$token@github.com/$account/$repo"
	local repoFolder="$HOME/src/github.com/$account"
	local repoPath="$repoFolder/$repo"

 	mkdir -p "$repoFolder" || return;
 	git -C "$repoFolder" clone "$repoUrl" || return;
# 	cd "$HOME/src/github.com/$account/$repo" || return
}


#
# Given a vm name, a base, and an optional imageRepo, create an instance and publish it.
# This assumes the vm init scripts are in $dist/conf/vm/$vm
#
pull-image ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: pull-image $image [$base]\n' >&2; return 1; }
    local image=$1
    
    if (( $# >= 2 )); then
        base=$2
    else
        local defaultBase="ubuntu:20.04"
        local s; read -r -p "Please choose a base image [default - $defaultBase] " s || return
        base=${s:-$defaultBase}
    fi

    # Both the base and the image can be of the form repo:name or just name.
    # Dealing with that is simple but it takes a few lines of bash.
    local baseRepo
    local baseName
    if [[ "$base" == *:* ]]; then
        baseRepo="${base%%:*}"
        baseName="${base##*:}"
    else
        baseRepo='local'
        baseName="$base"
    fi

    local imageRepo
    local imageName
    if [[ "$image" == *:* ]]; then
        imageRepo="${image%%:*}"
        imageName="${image##*:}"
    else
        imageRepo='local'
        imageName="$image"
    fi

    local srcFolder; srcFolder=$(download-vm "$imageName") || return
    local userDataPath; userDataPath=$(mktemp) >/dev/null || return
    create-lxd-user-data "$srcFolder" >"$userDataPath" || return
    local instanceName; instanceName=$(mktemp --dry-run "$imageName-XXXXXXXX") || return
    local instance="$imageRepo:$instanceName"
    # Launch an instance with the new user data
    lxc init "$base" "$instance" || return
    lxc config set "$instance" user.user-data - <"$userDataPath" || return
    lxc start "$instance" || return
    lxc exec "$instance" -- cloud-init status --wait || return
     # Publish the instance as an instance
    lxc stop "$instance" || return
    lxc publish --public "$instance" "$imageRepo:" --alias "$imageName" || return
    lxc delete "$instance" || return
    # # Download all the dists ... or maybe just the right one.
    # download-dist || return
    # # Create user-data for the desired VM
    # local configDir="/tmp/dist/vm/$vm"
    # mkdir -p "$configDir" || return
    # tar -C "$configDir" -xvf "/tmp/dist/vm/$vm.tgz" || return
    # local userDataPath; userDataPath=$(mktemp) >/dev/null || return
    # create-lxd-user-data "$configDir" >"$userDataPath" || return
    # # Delete the instance if it exists (lxd does not provide a cleaner, RC=0 solution)
    # delete-lxd-instance "$vm"
    # # Launch an instance with the new user data
    # lxc init "$base" "$vm" || return
    # lxc config set "$vm" user.user-data - <"$userDataPath" || return
    # lxc start "$vm" || return
    # lxc exec "$vm" -- cloud-init status --wait || return
    # # Publish the instance as an image
    # lxc stop "$vm" || return
    # lxc publish "$vm" "$imageRepo:" --alias "$vm" || return
    # [[ -f "$userDataPath" ]] || { echo "Non-existent path: $userDataPath" >&2; return 1; }
}


pull-ssh-tarball ()
{
    local bucket; bucket=$(get-bucket) || return
    sshUrl="s3://$bucket/conf/ssh.tgz"
    local sshDir; sshDir=$(download-to-temp-dir "$sshUrl") || return
    printf '%s' "$sshDir"
}


pull-svc ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: pull-svc $name [$dstFolder]\n' >&2; return 1; }
    local name=$1
    local dstFolder=${2:-"/app/svc/$name"}

    local srcFolder; srcFolder=$(download-svc "$name") || return
    install-svc "$name" "$srcFolder" >/dev/null || return
}


pull-vm ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: pull-vm $name\n' >&2; return 1; }
    local name=$1

    local srcFolder; srcFolder=$(download-vm "$name") || return
    install-vm "$name" "$srcFolder"
    activate-vm "$name" "$srcFolder"
}


pull-webapp ()
{
    # shellcheck disable=SC2016
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: pull-webapp $name [$dstFolder]\n' >&2; return 1; }
	local name=$1
    local dstFolder=${2:-"/www/$name"}
    
	# I'm not sure but I think this might be out of step with the other pull-xxx fns, 
    #  which download and untar the tarball to a tmp folder, and then rsync. 
    #  I'm not actually sure that's better but it's good to be consistent.
    local s3key; s3key="s3://$(get-bucket)/dist/webapp/$name.tgz" || return
	aws s3 cp "$s3key" "/tmp/$name.tgz" || return
    mkdir -p "$dstFolder" || return
	tar -xz -C "$dstFolder" --exclude ./**/__pycache__ -f "/tmp/$name.tgz" || return
}


push-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 0 )) && (( $# <= 2 )); } || { printf 'Usage: push-app [$path [$name]]\n' >&2; return 1; }
    local path=${1:-$PWD}
    local name=${2:-${path##*/}}

    [[ -d "$path" ]] || { echo "Non-existent folder: $path" >&2; return 1; }
    local tmpDir; tmpDir=$(mktemp -d) || return
    local tgzPath="$tmpDir/$name.tgz"
    tar -C "$path" -zcf "$tgzPath" . >/dev/null || return
    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/app/$name.tgz"
    aws s3 cp "$tgzPath" "$s3url" >/dev/null || return
    printf '%s' "$s3url"
}




push-daylight ()
{
	# shellcheck disable=SC2016
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: push-daylight $message\n' >&2; return 1; }
    local message=$1

    local daylightPath="$HOME/src/github.com/daylight-public/daylight/daylight.sh"
    [[ -f "$daylightPath" ]] || { echo "Non-existent path: $daylightPath" >&2; return 1; }
    git commit -m "$message" "$daylightPath" || return
    git push || return
}


push-flask-app ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: push-flask-app $name $path\n' >&2; return 1; }
    local name=$1
    local path=$2

    [[ -d "$path" ]] || { echo "Non-existent folder: $path" >&2; return 1; }
    local tmpDir; tmpDir=$(mktemp -d) || return
    local tgzPath="$tmpDir/$name.tgz"
    tar -C "$path" -zcf "$tgzPath" . >/dev/null || return
    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/flask/$name.tgz"
    aws s3 cp "$tgzPath" "$s3url" >/dev/null || return
    printf '%s' "$s3url"
}


push-svc ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: push-svc $name [$srcFolder]\n' >&2; return 1; }
    local name=$1
    local srcFolder=${2:-"/app/svc/$name"}

	local tgzPath; tgzPath=$(mktemp).tgz >/dev/null || return
	echo "$tgzPath"
	tar -C "$srcFolder" -czf "$tgzPath" . >/dev/null || return
	local bucket; bucket=$(get-bucket) || return
	s3url="s3://$bucket/dist/svc/$name.tgz"
	aws s3 cp "$tgzPath" "$s3url" >/dev/null || return
}


push-webapp ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: push-webapp $name\n' >&2; return 1; }
	local name=$1

	tar -C "/www/$name" --exclude ./**/__pycache__ -czf "/tmp/$name.tgz" . || return
	local s3key; s3key="s3://$(get-bucket)/dist/webapp/$name.tgz" || return
	aws s3 cp "/tmp/$name.tgz" "$s3key" || return
}



run-conf-script ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: run-conf-script $name\n' >&2; return 1; }
    local name=$1

    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/conf.tgz"
    local confDir; confDir=$(download-to-temp-dir "$s3url") || return
    local scriptPath="$confDir/scripts/$name"
    [[ -f "$scriptPath" ]] || { echo "Non-existent path: $scriptPath" >&2; return 1; }
    "$scriptPath" || return
}


run-service ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: run-service $serviceName\n' >&2; return 1; }
    local name=$1

    cd "$(get-service-working-directory "$name")" || return
    source-service-environment-file "$name"
    bash -ux -c "$(get-service-exec-start "$name")"
}


setup-domain ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: setup-domain $domain $port $email\n' >&2; return 1; }
    [[ -f "/opt/bin/nginxer" ]] || { echo "Non-existent path: /opt/bin/nginxer" >&2; return 1; }
    [[ -d "/tmp/setup" ]] || { echo "Non-existent folder: /tmp/setup" >&2; return 1; }
    [[ -d "/etc/nginx/sites-available" ]] || { echo "Non-existent folder: /etc/nginx/sites-available" >&2; return 1; }
    [[ -d "/etc/nginx/sites-enabled" ]] || { echo "Non-existent folder: /etc/nginx/sites-enabled" >&2; return 1; }
    [[ -f "/opt/venv/main/bin/certbot" ]] || { echo "Non-existent path: /opt/venv/main/bin/certbot" >&2; return 1; }
    local domain=$1
    local port=$2
    local email=$3

    # Create the nginx unit file, write it to /etc/nginx/sites-available, and symlink to /etc/nginx/sites-enabled
    /opt/bin/nginxer "$domain" "$port" 2>/dev/null >/etc/nginx/sites-available/$domain
    ln -sf /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/$domain
    # User certbot to create the cert files and update the nginx unit files
    /opt/venv/main/bin/certbot --nginx -n --agree-tos --domain "$domain" --email "$email"
    # Create tar file of cert files
    tar -C /etc/letsencrypt/ -czf /tmp/setup/$domain-certs.tar.gz \
        ./archive/$domain \
        ./live/$domain \
        ./renewal/$domain.conf
    # Create tar file of nginx unit files
    tar -C /etc/nginx/ -czf /tmp/setup/$domain-nginx.tar.gz \
        ./sites-available/$domain \
        ./sites-enabled/$domain
}


source-daylight ()
{
	local daylightPath; daylightPath=$(command -v daylight.sh) || return
	source "$daylightPath"
}


source-service-environment-file ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: source-service-environment-file $serviceName\n' >&2; return 1; }
    local name=$1

    set -a
    source "$(get-service-environment-file "$name")"
    set +a
}


#
# Given a service name, and a list of parameters, this enables and starts an instance of the 
# indexed service for every parameter.
#
start-indexed-service ()
{
    # shellcheck disable=SC2016
    (( $# >= 1 )) || { printf 'Usage: start-indexed-service $arg1 [$arg2 ... $argn]\n' >&2; return 1; }
    local service=$1
    if [[ ! ${service: -1} == '@' ]]; then
        service="$service@"
    fi
    shift;

    for i in "$@"; do
        start-service "$service$i"
    done
}


#
# Start and enable a systemd service.
# If a .timer file is present, the .timer gets enabled and started instead of the .service unit file.
# This function supports both regular and indexed services
start-service ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: start-service $service[@$index]\n' >&2; return 1; }
    local service=$1

    # If $service is indexed (contains a '@'), $serviceRoot = $service minus @ and everything after
    # Otherwise $serviceRoot = Sservice
    local serviceRoot
    if [[ $service == *"@"* ]]; then
        serviceRoot="${service%%@*}@"
    else
        serviceRoot=$service
    fi

    # Note that $service contains the index (if it's an indexed service) but $serviceRoot does not.
    # Thus $service is suitable as a service name, and $serviceRoot is suitable for file names
    if [[ -f "/etc/systemd/system/$serviceRoot.timer" ]]; then
        sudo systemctl enable "$service.timer"
        sudo systemctl start "$service.timer"
    elif [[ -f "/etc/systemd/system/$serviceRoot.service" ]]; then
        sudo systemctl enable "$service"
        sudo systemctl start "$service"
    else
        printf 'Service "%s" not found\n' "$service"
    fi
}


sys-start ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: sys-start $service\n' >&2; return 1; }
    local service=$1

    sudo systemctl restart "$service" || journalctl --unit "$service"
}


# untar (and unzip if necessary) a .tar or .tgz to a new temp folder.
untar-to-temp-folder ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: untar-to-temp-folder $1\n' >&2; return 1; }
    local tarPath=$1
    local dstFolder; dstFolder=$(mktemp -d) || return
    tar -C "$dstFolder" -xzf "$tarPath" >/dev/null || return

    printf '%s' "$dstFolder"
}


#
# If daylight is invoked as a command, well all right then
#
old-main ()
{
    if (( $# >= 1 )); then
        set -ux
        cmd=$1
        shift
        case "$cmd" in
            install-vm) install-vm "$@";;
            *) printf 'Unknown command: %s \n' "$cmd";;
        esac
    fi
}


# If this script is being sourced in a terminal, and it does not exist on
# the host in /opt/bin, then download this script to /opt/bin and install the
# `fresh-daylight` service which will pull the latest script every hour.
if [[ ! -f /opt/bin/daylight.sh  &&  -t 0 ]]; then
    printf '%s\n' "Hello"
    printf '\n'  
    printf '%s\n' "It's nice to see you."
    printf '\n'  
    printf '%s\n' "Installing daylight ..."
    printf '\n' 
    url=https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
    curl --silent --remote-name --output-dir /opt/bin "$url"
    source /opt/bin/daylight.sh
    printf '%s\n' "Installing fresh-daylight service ..."
    printf '\n' 
    install-fresh-daylight-svc
    if [[ -f /home/ubuntu/.bashrc ]]; then
        {
        printf '%s\n' ""
        printf '%s\n' "# hello from daylight"
        printf '%s\n' "source /opt/bin/daylight.sh"
        } >> /home/ubuntu/.bashrc
    fi
    printf '%s\n' Done.
    printf '\n' 
fi


#
# If daylight is invoked as a command, well all right then
#
main ()
{
    if (( $# >= 1 )); then
        set -ux
        cmd=$1
        shift
        case "$cmd" in
			activate-flask-app)	activate-flask-app "$@";;
			activate-svc)	activate-svc "$@";;
			activate-vm)	activate-vm "$@";;
			add-container-user)	add-container-user "$@";;
			add-ssh-to-container)	add-ssh-to-container "$@";;
			add-superuser)	add-superuser "$@";;
			add-user)	add-user "$@";;
			add-user-to-idmap)	add-user-to-idmap "$@";;
			add-user-to-shadow-ids)	add-user-to-shadow-ids "$@";;
			cat-conf-script)	cat-conf-script "$@";;
			create-flask-app)	create-flask-app "$@";;
			create-github-user-access-token)	create-github-user-access-token "$@";;
			create-home-filesystem)	create-home-filesystem "$@";;
			create-loopback)	create-loopback "$@";;
			create-lxd-user-data)	create-lxd-user-data "$@";;
			create-publish-image-service)	create-publish-image-service "$@";;
			create-service-from-dist-script)	create-service-from-dist-script "$@";;
			create-static-website)	create-static-website "$@";;
			delete-lxd-instance)	delete-lxd-instance "$@";;
			download-app)	download-app "$@";;
			download-dist)	download-dist "$@";;
			download-flask-app)	download-flask-app "$@";;
			download-flask-service)	download-flask-service "$@";;
			download-public-key)	download-public-key "$@";;
			download-shr-tarball)	download-shr-tarball "$@";;
			download-svc)	download-svc "$@";;
			download-to-temp-dir)	download-to-temp-dir "$@";;
			download-vm)	download-vm "$@";;
			edit-daylight)	edit-daylight "$@";;
			gen-nginx-flask)	gen-nginx-flask "$@";;
			gen-nginx-static)	gen-nginx-static "$@";;
			generate-unit-file)	generate-unit-file "$@";;
			get-bucket)	get-bucket "$@";;
			get-container-ip)	get-container-ip "$@";;
			get-image-base)	get-image-base "$@";;
			get-image-name)	get-image-name "$@";;
			get-image-repo)	get-image-repo "$@";;
			get-service-file-value)	get-service-file-value "$@";;
			get-service-environment-file)	get-service-environment-file "$@";;
			get-service-exec-start)	get-service-exec-start "$@";;
			get-service-working-directory)	get-service-working-directory "$@";;
			init-lxd)	init-lxd "$@";;
			init-nginx)	init-nginx "$@";;
			install-app)	install-app "$@";;
			install-awscli)	install-awscli "$@";;
			install-flask-app)	install-flask-app "$@";;
			install-fresh-daylight-svc)	install-fresh-daylight-svc "$@";;
			install-gnome-keyring)	install-gnome-keyring "$@";;
			install-latest-httpie)	install-latest-httpie "$@";;
			install-mssql-tools)	install-mssql-tools "$@";;
			install-public-key)	install-public-key "$@";;
			install-python)	install-python "$@";;
			install-service)	install-service "$@";;
			install-service-from-script)	install-service-from-script "$@";;
			install-service-from-command)	install-service-from-command "$@";;
			install-shellscript-part-handlers)	install-shellscript-part-handlers "$@";;
			install-shr-token)	install-shr-token "$@";;
			install-svc)	install-svc "$@";;
			install-venv)	install-venv "$@";;
			install-vm)	install-vm "$@";;
			list-apps)	list-apps "$@";;
			list-conf-scripts)	list-conf-scripts "$@";;
			list-public-keys)	list-public-keys "$@";;
			list-services)	list-services "$@";;
			list-vms)	list-vms "$@";;
			pull-app)	pull-app "$@";;
			pull-daylight)	pull-daylight "$@";;
			pull-flask-app)	pull-flask-app "$@";;
			pull-git-repo)	pull-git-repo "$@";;
			pull-image)	pull-image "$@";;
			pull-ssh-tarball)	pull-ssh-tarball "$@";;
			pull-svc)	pull-svc "$@";;
			pull-vm)	pull-vm "$@";;
			pull-webapp)	pull-webapp "$@";;
			push-app)	push-app "$@";;
			push-daylight)	push-daylight "$@";;
			push-flask-app)	push-flask-app "$@";;
			push-svc)	push-svc "$@";;
			push-webapp)	push-webapp "$@";;
			run-conf-script)	run-conf-script "$@";;
			run-service)	run-service "$@";;
			setup-domain)	setup-domain "$@";;
			source-daylight)	source-daylight "$@";;
			source-service-environment-file)	source-service-environment-file "$@";;
			start-indexed-service)	start-indexed-service "$@";;
			start-service)	start-service "$@";;
			sys-start)	sys-start "$@";;
			untar-to-temp-folder)	untar-to-temp-folder "$@";;
            *) printf 'Unknown command: %s \n' "$cmd";;
        esac
    fi
}

main $@