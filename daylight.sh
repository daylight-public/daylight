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
    adduser --gecos -'' --disabled-password "$username"
    adduser "$username" sudo2

    # Setup the user's public key to allow ssh
    install-public-key "/home/$username" "$publicKeyPath"
    chown -R "$username:$username" "/home/$username"

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
    local uid; uid=$(id --user "$username") || return
    local gid; gid=$(id --group "$username") || return
    local idMapPath; idMapPath=$(lxd-dump-id-map "$container") || return
    printf 'uid %d %d\n' "$uid" "$uid" >> "$idMapPath"
    printf 'gid %d %d\n' "$gid" "$gid" >> "$idMapPath"
    lxd-set-id-map "$container" "$idMapPath"
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


###
# @deprecated
# use github-create-user-access-token instead
###
create-github-user-access-token ()
{
    client_id=Iv1.f69b43d6e5f4ea24
    s="$(http --body POST https://github.com/login/device/code?client_id=$client_id | tail -n 1)"
    # shellcheck source=/dev/null
    source <(python3 -m parse_query_string --names device_code user_code verification_uri --output env <<<"$s")
    # shellcheck disable=SC2154
    printf 'Please visit %s and enter the user code %s ...' "$verification_uri" "$user_code"
    read -r
    grant_type=urn:ietf:params:oauth:grant-type:device_code
    # shellcheck disable=SC2154
    s="$(http --body post "https://github.com/login/oauth/access_token?client_id=$client_id&device_code=$device_code&grant_type=$grant_type")"
    # shellcheck source=/dev/null
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


create-pubbo-service ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: create-pubbo-service $svcName $filePath $port\n' >&2; return 1; }
    svcName=$1
    filePath=$2
    port=$3
    socketFolder=/run/sock/pubbo
    socketPath="$socketFolder/$svcName.sock"
    
    # Get ready
    prep-service "$svcName"
    
    # Catdoc the unit file
    local unitTmplPath; unitTmplPath=$(mktemp --tmpdir=/tmp/ .XXXXXX) || return
    cat >"$unitTmplPath" <<- 'EOT'
[Unit]
Description=Service to make $filePath available over a Unix domain socket at "$socketPath"

[Service]
ExecStart=/opt/svc/$svcName/bin/main.sh
Type=exec
User=www-data
WorkingDirectory=/opt/svc/$svcName

[Install]
WantedBy=multi-user.target
EOT
    # envsubst to create the final unit file 
    filePath=$filePath socketPath=$socketPath svcName=$svcName envsubst <"$unitTmplPath" >"/opt/svc/$svcName/$svcName.service"

    # Catdoc the script
    local mainScriptTmplPath; mainScriptTmplPath=$(mktemp --tmpdir=/tmp/ .XXXXXX) || return
    cat >"$mainScriptTmplPath" <<- 'EOT'
#! /bin/sh
mkdir -p "$socketFolder"
/opt/bin/pubbo \
    --file-path "$filePath" \
    --socket-path "$socketPath"
EOT
    # envsubst to create the final script
    filePath=$filePath socketPath=$socketPath svcName=$svcName socketFolder=$socketFolder envsubst <"$mainScriptTmplPath" >"/opt/svc/$svcName/bin/main.sh"
    chmod 777 "/opt/svc/$svcName/bin/main.sh"

    # catdoc the nginx stream config file
    local streamCfgTmplPath; streamCfgTmplPath=$(mktemp --tmpdir= .XXXXXX) || return
    cat >"$streamCfgTmplPath" <<- 'EOT'
stream {
    upstream sock {
        server unix:$socketPath;
    }

    server {
        listen $port;
        proxy_pass sock;
    }
}
EOT

    # envsubst
    socketPath=$socketPath port=$port envsubst <"$streamCfgTmplPath" >"/etc/nginx/streams.d/$svcName.conf"

    # Create the systemd service
    ln --symbolic --force "/opt/svc/$svcName/$svcName.service" "/etc/systemd/system/$svcName.service"
    systemctl daemon-reload
    systemctl start "$svcName"
    systemctl enable "$svcName"
	# Restart nginx to pickup the new Unix socket started by the new service
	restart-nginx
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


create-temp-file ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: create-temp-file $template [$folder]\n' >&2; return 1; }
    template=$1
    folder=${2:-''}

    if [[ ! $template == *XXXXXX* ]]; then
        template="$template.XXXXXX"
    fi
    if [[ -n "$folder" ]]; then
        mktemp --tmpdir="$folder" "$template"
    else
        mktemp --tmpdir -t "$template"
    fi
}


# shellcheck disable=SC2120 # It's valid and common to use this function with 0 arguments
create-temp-folder ()
{
    # shellcheck disable=SC2016
    { (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: create-temp-file $template [$template [$folder]]\n' >&2; return 1; }
	local template=${1:-''}

    if (( $# == 0)) || [[ -z "$template" ]]; then
        mktemp --directory
    else
		if [[ ! $template == *XXXXXX* ]]; then
			template="$template.XXXXXX"
		fi
        mktemp --directory --tmpdir "$template"
    fi
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
# Download daylight script from the specified branch
#
download-daylight ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: download-daylight $branch $dstFolder\n' >&2; return 1; }
    local branch=$1
    local dstFolder=$2
    [[ -d "$dstFolder" ]] || { echo "Non-existent folder: $dstFolder" >&2; return 1; }
    local org=daylight-public
    local repo=daylight
    url="https://raw.githubusercontent.com/$org/$repo/$branch/daylight.sh"
    curl --location --silent --output-dir "$dstFolder" --remote-name "$url"
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


#
# Download latest dylt release
#
download-dylt ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-dylt $dstFolder [$platform]\n' >&2; return 1; }
    local dstFolder=$1
    local platform=$2
    [[ -d "$dstFolder" ]] || { echo "Non-existent folder: $dstFolder" >&2; return 1; }

    # If there's no platform, try and determine it. If it can't be determined,
    # prompt the user
    platform=$(github-detect-local-platform) || return
    if [[ -z "$platform" ]]; then
        platform=$(github-release-select-platform)
    fi

    # Confirm a platform was actually selected 
    # shellcheck disable=SC2016
    [[ -n "$platform" ]] || { printf 'Variable is unset or empty: $platform\n' >&2; return 1; }    

    # create flags (--token)
    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}") 
    # get the latest version
    local version; version=$(github-release-get-latest-tag "${flags[@]}" dylt-dev dylt) || return
    # create the release name (goreleaser trims the leading 'v' from the release tag)
    local releaseName="dylt_${platform}.tar.gz"
    github-release-download-latest "${flags[@]}" dylt-dev dylt "$releaseName" "$dstFolder" || return
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
    read -r -a args < <(curl --silent "$urlLatestRelease" \
        | jq -r '.assets[]? | select(.name | test("^actions-runner-linux-x64.*\\d\\.tar.gz$")) | [.name, .browser_download_url] | @tsv') \
        || return
    tarballFileName=${args[0]}
    tarballUrl=${args[1]}
    local tarballPath; tarballPath="$(create-temp-file "XXX.$tarballFileName")" || return
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


ec ()
{
    local discSrv='hello.dylt.dev'
    /opt/etcd/etcdctl --discovery-srv "$discSrv" "$@"
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


emit-os-arch-vars ()
{
    emit-vars HOSTTYPE MACHTYPE OSTYPE
}


emit-vars ()
{
    for varname in "$@"; do
        printf '%s\0%s\0' "$varname" "${!varname}"
    done
}


# Statically create the URL from which to download a specific version of etcd.
#
# An optional $platform argument is supported as well. If omitted it defaults to
# linux-amd64.
# 
etcd-create-download-url ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    
    # get arg values from flags, if present (if not fall back to defaults
    local version=${argmap[version]:-''}
    [[ -n "$version" ]] || version=$(github-release-get-latest-tag etcd-io etcd) || return
    local platform=${argmap[platform]:-'linux-amd64'}
    local releaseName; releaseName=$(etcd-create-release-name "$version" "$platform")

    local -A info
    github-release-get-package-info info etcd-io etcd "$releaseName" || return
    local downloadUrl=${info[url]}
    printf '%s' "$downloadUrl"
}


###
#
# Create an etcd release name based on version on platform
#
###
etcd-create-release-name ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: etcd-create-release-name "$version" "$platform"\n' >&2; return 1; }
    local version=$1
    local platform=$2

    # All releases are tarballs except Windows which is a zipfile
    local releaseName
    if [[ $platform == 'windows' ]]; then
        releaseName="etcd-$version-$platform.zip"
    else
        releaseName="etcd-$version-$platform.tar.gz"
    fi
    printf '%s' "$releaseName" || return
}


# Download the latest etcd release
etcd-download-latest ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: etcd-download-latest $downloadFolder\n' >&2; return 1; }

    local version; version=$(etcd-get-latest-version) || return
    etcd-download --version "$version" "$@"
}


# Download a release of etcd from the specified URL.
#
# @Note this function changes the name of the release file to 
# etcd-release.tar.gz. This guarantees a consistent file name,
# but losing the version might not be a good tradeoff.
etcd-download ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: etcd-download $downloadFolder\n' >&2; return 1; }
    local downloadFolder=$1

    local version=${argmap[version]:-''}
    [[ -n "$version" ]] || version=$(github-release-get-latest-tag etcd-io etcd) || return
    local platform=${argmap[platform]:-'linux-amd64'}
    local releaseName; releaseName=$(etcd-create-release-name "$version" "$platform") || return
    local -a flags
    github-create-flags argmap flags token
    flags+=(--version "$version")
    github-release-download "${flags[@]}" etcd-io etcd "$releaseName" "$downloadFolder"
}


# Generate an etcd script to join an existing cluster, using a heredoc
# template.
etcd-gen-join-script ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: etcd-gen-join-script $etcd_disc_svr $etcd_ip $etcd_name\n' >&2; return 1; }
    local etcdDiscSvr=$1
    local etcdIp=$2
    local etcdName=$3
    local joinEtcdScriptTmplPath; joinEtcdScriptTmplPath=$(mktemp --tmpdir=/tmp/ join-etcd.sh.tmpl.XXXXXX) || return
    cat >"$joinEtcdScriptTmplPath" <<- 'EOT'
	#! /usr/bin/env bash
	/opt/etcd/etcd \
		--name "$etcd_name" \
		--discovery-srv "$etcd_disc_svr" \
		--initial-advertise-peer-urls http://$etcd_ip:2380 \
		--initial-cluster-token hello \
		--initial-cluster-state existing \
		--advertise-client-urls http://$etcd_ip:2379 \
		--listen-client-urls http://$etcd_ip:2379,http://127.0.0.1:2379 \
		--listen-peer-urls http://$etcd_ip:2380 \
		--data-dir /var/lib/etcd/
	EOT
    # Note the line continuations - this is all one command
	etcd_disc_svr=$etcdDiscSvr \
	etcd_ip=$etcdIp \
	etcd_name=$etcdName \
	envsubst <"$joinEtcdScriptTmplPath"
}


# Generate an etcd script to join an new cluster, using a heredoc
# template.
etcd-gen-run-script ()
{
    # shellcheck disable=SC2016
    (( $# == 5 )) || { printf 'Usage: etcd-gen-run-script $etcd_disc_svr $etcd_name $etcd_ip $initialState $dataDir\n' >&2; return 1; }
    local discSvr=$1
    local name=$2
    local ip=$3
    local initialState=$4
    local dataDir=$5
    [[ -d "$dataDir" ]] || { echo "Non-existent folder: $dataDir" >&2; return 1; }

    cat <<- EOT
	#! /usr/bin/env bash
	/opt/etcd/etcd \\
	    --name "$name" \\
	    --discovery-srv "$discSvr" \\
	    --initial-advertise-peer-urls http://$ip:2380 \\
	    --initial-cluster-token hello \\
	    --initial-cluster-state $initialState \\
	    --advertise-client-urls http://$ip:2379 \\
	    --listen-client-urls http://$ip:2379,http://127.0.0.1:2379 \\
	    --listen-peer-urls http://$ip:2380 \\
	    --data-dir "$dataDir"
	EOT
}

    # (( $# == 4 )) || { printf 'Usage: etcd-gen-run-script $etcd_disc_svr $etcd_ip $etcd_name $initialState\n' >&2; return 1; }
    # local etcdDiscSvr=$1
    # local etcdIp=$2
    # local etcdName=$3
    # local initialState=$4
    # local runEtcdScriptTmplPath; runEtcdScriptTmplPath=$(mktemp --tmpdir=/tmp/ run-etcd.sh.tmpl.XXXXXX) || return
    # cat >"$runEtcdScriptTmplPath" <<- 'EOT'
	# #! /usr/bin/env bash
	# /opt/etcd/etcd \
	# 	--name "$etcd_name" \
	# 	--discovery-srv "$etcd_disc_svr" \
	# 	--initial-advertise-peer-urls http://$etcd_ip:2380 \
	# 	--initial-cluster-token hello \
	# 	--initial-cluster-state $initial_state \
	# 	--advertise-client-urls http://$etcd_ip:2379 \
	# 	--listen-client-urls http://$etcd_ip:2379,http://127.0.0.1:2379 \
	# 	--listen-peer-urls http://$etcd_ip:2380 \
	# 	--data-dir /var/lib/etcd/
	# 	EOT
    # etcd_disc_svr=$etcdDiscSvr \
    # etcd_ip=$etcdIp \
    # etcd_name=$etcdName \
    # initial_state=$initialState \
    # envsubst <"$runEtcdScriptTmplPath"

# Generate a systemd etcd unit file a from the heredoc template
#
# This is very boilerplate. All the goodness is in the run.sh
# script references in ExecStart
#
etcd-gen-unit-file ()
{
    cat <<- 'EOT'
	[Unit]
	Description=etcd service
	Documentation=https://github.com/coreos/etcd

	[Service]
	ExecStart=/opt/svc/etcd/run.sh		
	User=rayray
	Type=simple
	Restart=on-failure
	RestartSec=5
	WorkingDirectory=/opt/etcd/

	[Install]
	WantedBy=multi-user.target
	EOT
}

# Dynamically get the version number for the latest etcd release.
etcd-get-latest-version ()
{
	local tag; tag=$(github-release-get-latest-tag etcd-io etcd) || return
	if [[ -t 0 ]]; then
		printf '%s\n' "$tag"
	else
		printf '%s' "$tag"
	fi
}


# Install an etcd release tarball into the specified folder
etcd-install-latest ()
{
	# parse github args
	local -A argmap=()
	local nargs=0
	github-parse-args argmap nargs "$@" || return
	shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: etcd-install-latest $installFolder\n' >&2; return 1; }
	[[ -d "$1" ]] || { echo "Non-existent folder: $1" >&2; return 1; }
    local installFolder=$1
    local org=etcd-io
    local repo=etcd
    local platform=${argmap[platform]}
	[[ -n "$platform" ]] || platform=linux-amd64

	local version; version=$(etcd-get-latest-version) || return
	local releaseName; releaseName=$(etcd-create-release-name "$version" "$platform") || return
	local -a flags=(--version "$version")
    github-release-install "${flags[@]}" "$org" "$repo" "$releaseName" "$installFolder" || return
    chown -R rayray:rayray "$installFolder" || return
}


# Install an etcd release tarball into the specified folder
# @note am I really wrapping a simple tar --extract?
etcd-install-release ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: etcd-install-release $releasePath $installFolder\n' >&2; return 1; }
    local releasePath=$1
    local installFolder=$2
    [[ -f "$releasePath" ]] || { echo "Non-existent path: $releasePath" >&2; return 1; }
    [[ -d "$installFolder" ]] || { printf 'Non-existent folder: %s\n' "$installFolder" >&2; return 1; }
    tar --gunzip --extract --file "$releasePath" --directory "$installFolder" --strip-components=1
}


# @Note this logic is elsewhere in this script. Maybe it can be extracted 
# to build this function
etcd-install-service ()
{
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: etcd-install-service $discSvr $name $ip $dataDir\n' >&2; return 1; }
    local discSvr=$1
    local name=$2
    local ip=$3
    local dataDir=$4
    [[ -d "$dataDir" ]] || { echo "Non-existent folder: $dataDir" >&2; return 1; }
    
    mkdir -p /opt/svc/etcd/ || return
    etcd-gen-unit-file >/opt/svc/etcd/etcd.service || return
    etcd-gen-run-script "$discSvr" "$name" "$ip" "existing" "$dataDir" >/opt/svc/etcd/run.sh || return
    chmod 755 /opt/svc/etcd/run.sh || return
    systemctl enable /opt/svc/etcd/etcd.service || return
    systemctl start etcd || return
    chown -R rayray:rayray /opt/svc/etcd/ || return
}


# etcd needs a data directory set up, and chown'd to the sysuser. Otherwise it 
# would be owned by root which is problematic.
#
# @Note etcd has a standard folder it uses by default. It might be good to
# default to that value as well.
etcd-setup-data-dir ()
{
    # shellcheck disable=SC2016
    # shellcheck disable=SC2016
    { (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: etcd-setup-data-dir [$folder]\n' >&2; return 1; }
    local dataDir=${1:-/var/lib/data/}
    if [[ -d "$dataDir" ]]; then
		read -r -p "Are you sure you want to delete the contents of $dataDir? (Ctrl-C to cancel)"
        find "$dataDir" -type f -delete
		find "$dataDir" -mindepth 1 -maxdepth 1 -type d -exec rm -r {} \;
    else
        mkdir -p "$dataDir"
    fi
    chown -R rayray:rayray "$dataDir"
}


gen-completion-script () {
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: cmdName\n' >&2; return 1; }
    # The incoming list of tokens must come from redirected stdin, so 
    # this session must not be interactive
    # Confirm user is not interactive
    if [[ -t 0 ]]; then
        printf '\nstdin is a terminal; please redirect input from stdin.\n\n';
        return 0
    fi
    local cmdName=$1
	local functionName="_$cmdName"

    # catdoc beginning of script
    cat <<- END
	$functionName ()
	{
	    local curr=\$2
	    local last=\$3

	    local mainCmds=(\\
	END
	
	# print body of content - one indented line per subcommand
	while read -r line; do
	    printf  '        %s \\\n' "$line"
	done

	# catdoc end of script
	cat <<- END
	    )

	    # Typical mapfile + comgen -W idiom
	    mapfile -t COMPREPLY < <(compgen -W "\${mainCmds[*]}" -- "\$curr")
	}

	complete -F $functionName $cmdName
	END
}



gen-completion-script-2 ()
{
    # Coming up with a nice CLI experience for a bash-completion-generation
    # script is trickier than one might think.  The trick is that a very 
    # important part of any bash completion script is the call to `complete -F 
    # $functionName $scriptPath at the end.` This `complete -F` call is what
    # binds the completion function to the script or command.
    #
    # Proposed CLI UX

    #
    # That means that  
    # This function is a filter. It can operate on a file, or on stdin.
    # If the caller is piping data in via stdin, the first argument is the name of the script path. The script name will be derived from the path.
    # If no stdin, the first argument is the name of the script. There is no path to derive a name from, so the name must be explicitly provided.
    # The second argument is the name of the function. If no function name is provided it will be derived from the script name.
    # If not provided, the function name will be derived from the name of the file
    #
    # The resulting completion script is written to stdout.
    # To write the output to a file, use redirection.
    # E.g. gen-completion-script ./daylight.sh >~/.bash_completions.d/daylight.sh

    # shellcheck disable=SC2016
    (( $# >= 0 && $# <= 2 )) || { printf 'Usage: gen-completion-script [$scriptPath [$functionName]]\n' >&2
                                  printf '       gen-completion-script $scriptName [$functionName] < (...script content...)\n' >&2
                                  return 1; }
    # Confirm user is not interactive
    if [[ -t 0 ]]; then
        printf '\nstdin is a terminal; please redirect input from stdin.\n\n';
        return 0
    fi    

    if (( $# == 0 )); then
        scriptPath=${BASH_SOURCE[0]:-'/opt/bin/daylight.sh'}
        compScriptFolder=$HOME/bash-completion.d
		printf 'Creating %s (if necessasry) ...\n' "$compScriptFolder"
        mkdir -p "$compScriptFolder/" || return
        compScriptPath="$compScriptFolder/daylight.sh"
		printf 'Writing completion script for %s to %s ...\n' "$scriptPath" "$compScriptPath"
        gen-completion-script "$scriptPath" >"$compScriptPath" || return
		printf 'Sourcing %s ...\n' "$compScriptPath"
        # shellcheck disable=SC1090
		source "$compScriptPath" || return
		printf 'Done - bash completions for %s have been updated.\n' "$compScriptPath"
    # If stdin is a terminal, a $scriptPath arg is required. $scritpName is optional and will default to the basename of $scriptPath
	else
		if [[ -t 0 ]]; then
			local scriptPath=$1
			local scriptName; scriptName=$(basename "$scriptPath") || return
		else
			scriptName=$1
		fi
		if (( $# >= 2 )); then
			functionName=$2
		else
			# The function name is the script name, prepended with _, and with . => -
			functionName=_${scriptName//./-}
		fi
	    # beginning of script
		cat <<- END
		$functionName ()
		{
		    local curr=\$2
		    local last=\$3

		    local mainCmds=(\\
		END

		if [[ -t 0 ]]; then
			while read -r func; do
				printf  '        %s \\\n' "$func"
			done < <(list-funcs)
		else
			while read -r func; do
				printf  '        %s \\\n' "$func"
			done < <(list-funcs <"$scriptPath")
		fi

		# end of script
		cat <<- END
		    )

		    # Trim everything up to + including the first slash
		    local lastCmd=\${last##*/}
		    case "\$lastCmd" in
		        daylight.sh)
		            # Typical mapfile + comgen -W idiom
		            mapfile -t COMPREPLY < <(compgen -W "\${mainCmds[*]}" -- "\$curr")
		            ;;
		    esac
		}

		complete -F $functionName $scriptName
		END
	fi
}

gen-daylight-completion-script () {
	# shellcheck disable=SC2016
	(( $# >= 0 && $# <= 1 )) || { printf 'Usage: gen-daylight-completion-script [$folder] []\n' >&2; return 1; }
	local folder=${1:-~/.bash_completion.d}
	# shellcheck disable=SC2016
    if [[ ! -d "$folder" ]]; then
        printf 'Creating folder %s\n' "$folder" >&2;
        mkdir -p "$folder" || return
    fi

    local path="$folder/daylight.sh"
    local scriptPath='/opt/bin/daylight.sh'
	local cmdName=daylight.sh
	# gen list of bash funcs & write to temp file
	local tmpListBashFuncs; tmpListBashFuncs=$(mktemp --tmpdir list-bash-funcs.XXXXXX) || return	
	list-bash-funcs "$@" <"$scriptPath" >"$tmpListBashFuncs" || return
	gen-completion-script "$cmdName" <"$tmpListBashFuncs" >"$path" || return
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
User=rayray
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


getVmName ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: getVmName infovar $user\n' >&2; return 1; }
    local -n _appInfo=$1
    local user=$2

    printf '%s' "$user"
}


github-app-get-client-id ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: github-app-get-id $appSlug\n' >&2; return 1; }
    local appSlug=$1

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    local -A info
    github-app-get-info "${flags[@]}" info "$appSlug" || return
    local clientId=${info[client_id]}
    printf '%s' "$clientId"
}


github-app-get-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: github-app-get-data $appSlug\n' >&2; return 1; }
    local appSlug=$1

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    github-curl "${flags[@]}" "/apps/$appSlug" || return
}


github-app-get-id ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: github-app-get-id $appSlug\n' >&2; return 1; }
    local appSlug=$1

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    local -A info
    github-app-get-info "${flags[@]}" info "$appSlug" || return
    local id=${info[id]}
    printf '%s' "$id"
}


github-app-get-info ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-app-get-data $infovar $appSlug\n' >&2; return 1; }
    local -n _info=$1
    local appSlug=$2

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    local tmpCurl; tmpCurl=$(mktemp --tmpdir curl.XXXXXX) || return
    github-app-get-data "${flags[@]}" "$appSlug" >"$tmpCurl" || return
    local tmpJq; tmpJq=$(mktemp --tmpdir jq.XXXXXX) || return
    jq -r '[.id, .client_id, .slug] | @tsv' <"$tmpCurl" >"$tmpJq" || return
    read -r -a args < "$tmpJq" || return

    _info[id]=${args[0]}
    _info[client_id]=${args[1]}
    # shellcheck disable=SC2154
    _info[slug]=${args[2]}
}

github-create-flags ()
{
    # shellcheck disable=SC2016
    (( $# >=2 )) || { printf 'Usage: github-create-flags argmap flags [$flag1 $flag2 ... $flagn]\n' >&2; return 1; }
    # Check that argmap is either an assoc array or a nameref to an assoc array
    [[ $1 != argmap ]] && { local -n argmap; argmap=$1; }
    [[ $(declare -p argmap 2>/dev/null) == "declare -A"* ]] \
    || [[ $(declare -p "${!argmap}" 2>/dev/null) == "declare -A"* ]] \
    || { printf "%s is not an associative array, and it's not a nameref to an associative array either\n" "argmap" >&2; return 1; }
    # Check that flags is either an array or a nameref to an array
    [[ $2 != flags ]] && { local -n flags; argmap=$2; }
    [[ $(declare -p flags 2>/dev/null) == "declare -a"* ]] \
    || [[ $(declare -p "${!flags}" 2>/dev/null) == "declare -a"* ]] \
    || { printf "%s is not an array, and it's not a nameref to an array either\n" "flags" >&2; return 1; }

    flags=()
    local argname arg
    shift 2
    if (( $# == 0 )); then
        for argname in "${!argmap[@]}"; do
            arg=${argmap["$argname"]}
            flags+=("$argname" "$arg")
        done
    else
        while (( $# > 0 )); do
            argname=$1
            if [[ -v argmap["$argname"] ]]; then
                arg=${argmap["$argname"]}
                flags+=("--${argname}" "$arg")
            fi
            shift
        done
    fi
}


github-create-url ()
{
    local urlPath=$1
    local urlBase=${2:-'https://api.github.com'}

    # Trim leading slash
    if [[ $urlPath == /* ]]; then
        urlPath=${urlPath:1}
    fi
    # concatenate urlBase and Path
    local url="$urlBase/$urlPath"
    printf '%s' "$url" || return
}

github-create-user-access-token ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-create-user-access-token tokenvar $appslug\n' >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $1 != tokenvar ]] && { local -n tokenvar; tokenvar=$1; }
    local appSlug=$2

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    
    # Get the clientId for the dylt-cli GitHub App CLI, which must be installed 
    local clientId; clientId=$(github-app-get-client-id "${flags[@]}" "$appSlug") || return

    # Use client id to invoke device code flow
    flags+=(--data '')
    urlPath="/login/device/code?client_id=$clientId"
    urlBase="https://github.com"
    local -a args
    read -r -a args < <(github-curl "${flags[@]}" "$urlPath" "$urlBase" \
                        | jq -r '[.device_code, .user_code, .verification_uri] | @tsv') \
                        || { printf 'Call failed: github-curl()\n'; return; }
    local deviceCode=${args[0]}
    local userCode=${args[1]}
    local verificationUri=${args[2]}

    # Prompt user to do stuff in the browser
    echo
    printf '%-40s%s\n' "User Code" "$userCode"
    printf '%-40s%s\n' "Verification Uri" "$verificationUri"
    if command -v pbcopy >/dev/null; then
        printf '%s' "$userCode" | pbcopy
    fi
    if command -v open >/dev/null; then
        echo
        read -r -p "Hit <Enter> to open $verificationUri in your browser ..." _
        open "$verificationUri"
    fi
    echo
    
    # Post to the thing and grab the access token
    local prompt; prompt=$(printf 'Go to %s and enter %s. Then return here and press <Enter> ...' "$verificationUri" "$userCode") || return
    read -r -p  "$prompt" _
    local grantType='urn:ietf:params:oauth:grant-type:device_code'
    urlPath="$(printf '/login/oauth/access_token?client_id=%s&device_code=%s&grant_type=%s' "$clientId" "$deviceCode" "$grantType")"
    urlBase="https://github.com"
    read -r -a args < <(github-curl "${flags[@]}" "$urlPath" "$urlBase" \
                        | jq -r '[.access_token] | @tsv') \
                        || return
    # return the access token
    # shellcheck disable=SC2034
    tokenvar=${args[0]}
}


github-curl ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 1 && $# <= 2 )) || { printf 'Usage: github-curl [flags] $urlPath [$urlBase]\n' >&2; return 1; }
    local urlPath=${1##/} # Trim leading slash if necessary
    local urlBase=${2:-'https://api.github.com'}

    # Set headers to flag values or default
    local acceptDefault='application/vnd.github+json'
    local accept=${argmap[accept]:-$acceptDefault}
    local outputDefault='-'
    local output=${argmap[output]:-$outputDefault}
    # Set url and token, if present
    local url="$urlBase/$urlPath"
    # Can't really parameterize on token -- we need separate curl calls for with token, and without
    local -a flags=(--fail-with-body --location --silent)
    flags+=(--header "Accept: $accept")
    flags+=(--output "$output")
    [[ -v argmap[data] ]] && flags+=(--data "$(printf "'%s'" "${argmap[data]}")")
    [[ -v argmap[token] ]] && flags+=(--header "Authorization: Token ${argmap[token]}")
    curl "${flags[@]}" "$url" \
        || { printf 'curl failed inside github-curl\n' >&2; return 1; }
}



###
# @deprecated
# use github-curl with --data 'your-data'
###
github-curl-post ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: github-curl-post $urlPath $postData [$urlBase]\n' >&2; return 1; }
    local urlPath=${1##/} # Trim leading slash if necessary
    local postData=$2
    local urlBase=${3:-'https://api.github.com'}

    local acceptDefault='application/vnd.github+json'
    local accept=${argmap[accept]:-$acceptDefault}
    local outputDefault='-'
    local output=${argmap[output]:-$outputDefault}
    # Set url and token, if present
    local url="$urlBase/$urlPath"
    local token=${argmap[token]}
    # Can't really parameterize on token -- we need separate curl calls for with token, and without
    if [[ -n $token ]]; then
        curl --fail-with-body \
             --location \
             --silent \
             --data "'$postData'" \
             --header "Accept: $accept" \
             --header "Authorization: Token $token" \
             --output "$output" \
             "$url" \
        || return
    else
        curl --fail-with-body \
             --location \
             --silent \
             --data "'$postData'" \
             --header "Accept: $accept" \
             --output "$output" \
             "$url" \
        || return
    fi
}


###
#
#
github-detect-local-platform ()
{
    # shellcheck disable=SC2016
    (( $# == 0 )) || { printf 'Usage: github-detect-local=platform\n' >&2; return 1; }
    printf '%s=%s\n' HOSTTYPE $HOSTTYPE >&2
    printf '%s=%s\n' MACHTYPE $MACHTYPE >&2
    printf '%s=%s\n' OSTYPE $OSTYPE >&2

    if [[ "$HOSTTYPE" == 'aarch64' ]] && [[ "$OSTYPE" =~ darwin ]]; then
        printf Darwin_arm64
    elif [[ "$HOSTTYPE" == "x86_64" ]] && [[ "$OSTYPE" == linux-gnu ]]; then
        printf Linux_x86_64
    else
        return 1
    fi
}


github-download-latest-release ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: download-latest-release $org $repo $name $downloadFolder\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local downloadFolder=$4

    # Get release package data as assoc array
    local -A releaseInfo
    github-get-release-package-info releaseInfo "$org" "$repo" "$name" || return
    local url=${releaseInfo[url]}
    local accept='Accept: application/octet-stream'
    local output="$downloadFolder/$name"
    local token=${argmap[token]}
    if [[ -n $token ]]; then
        github-curl --token "$token" --accept "$accept" --output "$output"
    else
        github-curl --accept "$accept" --output "$output"
    fi
    printf '%s' "$releasePath"
}


###
# @deprecated
# use github-release-get-data
###
github-get-release-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 4 )); } || { printf 'Usage: github-get-release-data [flags] $org $repo [$releaseTag [$platform]]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local tag=${3:-""}
    
    local urlPath; urlPath="$(github-get-releases-url-path "$org" "$repo" "$tag")" || return
	local tmpCurl; tmpCurl=$(create-temp-file github.get.release.data.json) || return
    # build argstring for github-curl
    local argstring=''
    [[ -n ${argmap[token]} ]] && argstring+="--token ${argmap[token]}"
    # github-curl -- note $argstring is unquoted
    github-curl "$argstring" "$urlPath" >"$tmpCurl" || return
	printf '%s' "$tmpCurl"
}


###
# @deprecated
# use github-release-get-name-list
###
github-get-release-name-list ()
{
    # shellcheck disable=SC2016
    { (( $# >= 3 )) && (( $# <= 4 )); } || { printf 'Usage: github-get-release-name-list listVar $org $repo [$tag]\n' >&2; return 1; }
    local -n listVar; listVar=$1
    # ${@:2} skips the first two args, which are $0 and the $listVar nameref 
    local tmpCurl; tmpCurl=$(github-get-release-data "${@:2}") || return
    # shellcheck disable=SC2034
	local tmpJq; tmpJq=$(create-temp-file jq.get.release.name.list.txt) || return
	jq -r '[.assets[].name] | sort | @tsv' \
        <"$tmpCurl" \
        >"$tmpJq" \
        || return

	# shellcheck disable=SC2034
    read -r -a listVar <"$tmpJq" || return
}


###
# @deprecated
# use github-release-get-package-data
###
github-get-release-package-data ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-release-package-data $org $repo $name\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3

    local urlPath; urlPath="$(github-get-releases-url-path "$org" "$repo")" || return
    local tmpCurl; tmpCurl="$(create-temp-file 'curl.release')" || return
    github-curl "$urlPath" >"$tmpCurl" || return
    local tmpJq; tmpJq="$(create-temp-file 'jq.release')" || return
    jq -r --arg name "$name" \
       '.assets[]
        | select(.name == $name)' \
      </"$tmpCurl" >/"$tmpJq" \
      || return 
    printf '%s' "$tmpJq"
}


###
# @deprecated
# use github-release-get-package-info
###
github-get-release-package-info ()
{
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-get-release-package-info infovar $org $repo $name\n' >&2; return 1; }
    local -n info=$1
    local releaseDataPath; releaseDataPath=$(github-get-release-package-data "${@:2}") || return
    local tmpJq; tmpJq=$(create-temp-file 'jq.release.info') || return
    jq -r '[.id, .url, .browser_download_url] | @tsv' \
      <"$releaseDataPath" \
      >"$tmpJq" \
      || return
    local -a args
    read -r -a args <"$tmpJq" || return
    info[id]=${args[0]}
    info[url]=${args[1]}
    local browser_download_url=${args[2]}
    local filename=${browser_download_url##*/}
    info[browser_download_url]=$browser_download_url
    info[filename]=$filename
}


github-parse-args ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-parse-args infovar nargs [$args]\n' >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $1 != argmap ]] && { local -n argmap; argmap=$1; }
    # Check that argmap is either an assoc array or a nameref to an assoc array
    [[ $(declare -p argmap 2>/dev/null) == "declare -A"* ]] \
    || [[ $(declare -p "${!argmap}" 2>/dev/null) == "declare -A"* ]] \
    || { printf "%s is not an associative array, and it's not a nameref to an associative array either\n" "argmap" >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $2 != nargs ]] && { local -n nargs; nargs=$2; }

    nargs=0
    shift 2
    while (( $# > 0 )); do
        case $1 in
            '--accept'   |\
            '--data'     |\
            '--output'   |\
            '--token'    |\
            '--platform' |\
            '--version' \
            )
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                argmap["${1##--}"]=$2
                ((nargs+=2))
                shift 2
                ;;
            '--')
                shift
                ((nargs++))
                break
                ;;
            *)
                break
                ;;
        esac
    done
}


github-release-create-url-path ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-release-create-url-path $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2

    local tag=${argmap[version]:-''}
    local urlPath
    if [[ -n "$tag" ]]; then
        local urlPath="/repos/$org/$repo/releases/tags/$tag"
    else
        local urlPath="/repos/$org/$repo/releases/latest"
    fi

    # printf with \n if interactive
    if [[ -t 0 ]]; then
        printf '%s\n' "$urlPath"
    else
        printf '%s' "$urlPath"
    fi
}


github-release-download ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-release-download $org $repo $releaseName $downloadFolder\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local downloadFolder=${4%%/}

    # Get release info
    local -a flags=()
    github-create-flags argmap flags token version
    local -A releaseInfo
    github-release-get-package-info "${flags[@]}" releaseInfo "$org" "$repo" "$name" || return
    # download release file using releaseInfo data
    local urlPath=${releaseInfo[urlPath]}
    local filename=${releaseInfo[filename]}
    local accept='Accept: application/octet-stream'
    local output="$downloadFolder/$filename"
    flags+=(--accept "$accept" --output "$output")
    github-curl "${flags[@]}" "$urlPath" || return
    printf '%s' "$output"
}


github-release-download-latest ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-release-download-latest [$flags] $org $repo $name $downloadFolder\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local downloadFolder=${4%%/}

    local -a flags
    github-create-flags argmap flags token || return
    local version; version=$(github-release-get-latest-tag "${flags[@]}" "$org" "$repo") || return
    flags+=(--version "$version")
    github-release-download "${flags[@]}" "$org" "$repo" "$name" "$downloadFolder" || return
}


github-release-get-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@"
    shift "$nargs"
    # shellcheck disable=SC2016
    { (( $# >= 2 )) } || { printf 'Usage: github-release-get-data [flags] $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2
    
    local -a flags
    github-create-flags argmap flags version || return
    local urlPath; urlPath=$(github-release-create-url-path "${flags[@]}" "$org" "$repo") || return
    # build argstring for github-curl
    github-create-flags argmap flags token || return
    github-curl "${flags[@]}" "$urlPath" || return
}


# Dynamically get the latest release version tag of a repo
#
github-release-get-latest-tag ()
{
    command -v "jq" >/dev/null || { printf '%s is required, but was not found.\n' "jq" >&2; return 1; }
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-get-latest-version [flags] $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2
    
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    
    releasesUrlPath=$(github-release-create-url-path "$org" "$repo")
    # build flags for github-curl
    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    # local VER; VER=$(github-curl "${flags[@]}" "$releasesUrlPath" \
                    #  | jq -r .tag_name)
    local tmpCurl; tmpCurl=$(mktemp --tmpdir curl.latest.tag.XXXXXX) || return
    github-curl "${flags[@]}" "$releasesUrlPath" >"$tmpCurl" || return
    local tmpJq; tmpJq=$(mktemp --tmpdir jq.latest.tag.XXXXXX) || return
    jq -r '.tag_name' <"$tmpCurl" >"$tmpJq" || return
    read -r tag < "$tmpJq" || return    
    
    printf '%s' "$tag"
}


github-release-get-package-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-release-get-package-data $org $repo $name\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3

    local -a flags
    github-create-flags argmap flags version token || return
    local urlPath; urlPath=$(github-release-create-url-path "${flags[@]}" "$org" "$repo") || return
    github-create-flags argmap flags token || return
    local tmpCurl; tmpCurl=$(mktemp --tmpdir curl.release.XXXXXX) || return
    github-curl "${flags[@]}" "$urlPath" >"$tmpCurl" || return
    jq -r --arg name "$name" \
       '.assets[]
        | select(.name == $name)' \
      <"$tmpCurl" \
      || return 
}


github-release-get-package-info ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-get-release-package-info infovar $org $repo $name\n' >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $1 != info ]] && { local -n info; info=$1; }
    local org=$2
    local repo=$3
    local name=$4

    # Call github-release-get-package-data and create/parse the necesary fields
    local -a flags=()
    github-create-flags argmap flags token version
    local -a fields=()
    read -r -a fields < <(github-release-get-package-data "${flags[@]}" "$org" "$repo" "$name" \
    | jq -r '
        [.browser_download_url,
         .content_type,
         (.browser_download_url | match(".*/(.*)").captures[0].string),
         .id,
         .name,
         .url,
         (.url | match("https://api.github.com/(.*)").captures[0].string)
        ] | @tsv' \
      || return)
    # Package fields into the info assoc array
    info[browser_download_url]=${fields[0]}
    info[content_type]=${fields[1]}
    info[filename]=${fields[2]}
    info[id]=${fields[3]}
    info[name]=${fields[4]}
    info[url]=${fields[5]}
    info[urlPath]=${fields[6]}
}


github-release-install ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 4 && $# <= 5 )) || { printf 'Usage: github-install-latest-release $org $repo $releaseName $installFolder [$downloadFolder]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local installFolder=$4
	local downloadFolder=${5:-$(create-temp-folder)}
	[[ -d "$downloadFolder" ]] || { echo "Non-existent folder: $downloadFolder" >&2; return 1; }
    local -a flags=()
    github-create-flags argmap flags token version
    local releasePath; releasePath=$(github-release-download "${flags[@]}" "$org" "$repo" "$name" "$downloadFolder") || return
    case "$releasePath" in
        *.tgz|*.tar.gz)
            tar --strip-components=1 -C "$installFolder" -xzf "$releasePath";;
        *)
            printf "Unsupported file type - can't install (%s)\n" "$releasePath" >&2
            return 1;;
    esac
	printf '%s' "$installFolder"
}


###
# @note - github-release-install will install the latest by default, if you don't specify a version
###
github-release-install-latest ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 4 && $# <= 5 )) || { printf 'Usage: github-release-install-latest $org $repo $releaseName $installFolder [$downloadFolder]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=$3
    local installFolder=$4
	local downloadFolder=${5:-''}

    local -a flags
    github-create-flags argmap flags token
    local version; version=$(github-release-get-latest-tag "${flags[@]}" "$org" "$repo") || return    
    flags+=(--version "$version")
    github-release-install "${flags[@]}" "$org" "$repo" "$releaseName" "$installFolder" "$downloadFolder"
}


github-release-list ()
{
	# parse github args
	local -A argmap=()
	local nargs=0
	github-parse-args argmap nargs "$@"
	shift "$nargs"
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: github-release-list [flags] $org $repo\n' >&2; return 1; }
	local org=$1
	local repo=$2

	# get release name list, using token if provided
    local -a flags=()
	[[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
	github-release-get-data "${flags[@]}" "$org" "$repo" \
	| jq -r '[.assets[].name] | sort | @tsv' \
	|| return

}


github-release-list-platforms ()
{
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: github-release-list [flags] $org $repo\n' >&2; return 1; }
	local org=$1
	local repo=$2

	# get release name list, using token if provided
    readarray -t -d $'\t' releases < <(github-release-list "$@")
    local platform
    for release in "${releases[@]}"; do
        if [[ ! "$release" =~ checksums.txt ]]; then
            platform="${release##${repo}_}"
            platform="${platform%%.*}"
            echo $platform
        fi
    done
}


github-release-select ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
	# shellcheck disable=SC2016
	(( $# == 3 )) || { printf 'Usage: github-release-select [flags] name $org $repo\n' >&2; return 1; }
	[[ $1 != 'name' ]] && local -n name=$1
	local org=$2
	local repo=$3

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
	IFS=$'\t' read -r -a names < <(github-release-list "${flags[@]}" "$org" "$repo") || return
	select name in "${names[@]}"; do break; done
}


github-release-select-platform ()
{
    local platforms
    readarray -t -d $'\n' platforms < <(github-release-list-platforms "$@")
	select platform in "${platforms[@]}"; do
        printf '%s' "$platform" || return
        break
    done
}


# Simple attempt to get info for a repo
# If it does not succeed, it could mean the org or repo are nonexistent or misspelled
# But it could also mean that the repo is non-public and requires a token for authentication
# The Github API returns 404s for all of the above, so the error status doesn't tell us anything
github-test-repo ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-test-repo $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2

    local urlPath="/repos/$org/$repo"
    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    # We don't care about the info, just if we can successfully call the endpoint
    github-curl "${flags[@]}" --output /dev/null "$urlPath" || return
}


# @deprecated - use github-test-repo and pass a token
#
# Simple attempt to get info for a repo
# If it does not succeed, it could mean the org or repo are nonexistent or misspelled
# But it could also mean that the repo is non-public and requires a token for authentication
# The Github API returns 404s for all of the above, so the error status doesn't tell us anything
github-test-repo-with-auth ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-test-repo-with-auth $org $repo $token\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local token=$3

    local urlPath="/repos/$org/$repo"
    # We don't care about the info, just if we can successfully call the endpoint
    github-curl --output /dev/null --token "$token" "$urlPath" || return
}


go-service-gen-nginx-domain-file ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: go-service-gen-unit-file infovar\n' >&2; return 1; }
    local -n _appInfo=$1
    local domain=${_appInfo[domain]}
    local name=${_appInfo[name]}
    # shellcheck disable=SC2016
    [[ -n "$domain" ]] || { echo '$domain is not set' >&2; return 1; }
    # shellcheck disable=SC2016
    [[ -n "$name" ]] || { echo '$name is not set' >&2; return 1; }

    cat <<- EOT
	server {
	    server_name $domain;
	    location / {
	        include proxy_params;
	        proxy_pass http://unix:/run/sock/$name.sock:/;
	    }
	}
	EOT
}


go-service-gen-run-script ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: go-service-gen-unit-file infovar\n' >&2; return 1; }
    local -n _appInfo=$1
    local binaryFilename=${_appInfo[binaryFilename]}
    local description=${_appInfo[description]}
    local name=${_appInfo[name]}
    # shellcheck disable=SC2016
    [[ -n "$binaryFilename" ]] || { echo '$binaryFilename is not set' >&2; return 1; }
    # shellcheck disable=SC2016
    [[ -n "$description" ]] || { echo '$description is not set' >&2; return 1; }
    # shellcheck disable=SC2016
    [[ -n "$name" ]] || { echo '$name is not set' >&2; return 1; }
    cat <<- EOT
	#! /usr/bin/env bash
	
	main ()
	{
	    # shellcheck disable=SC2016
	    [[ -n "\$APP_NETWORK" ]] || { echo 'Please set \$APP_NETWORK' >&2; return 1; }
	    # shellcheck disable=SC2016
	    [[ -n "\$APP_ADDRESS" ]] || { echo 'Please set \$APP_ADDRESS' >&2; return 1; }
		[[ -d "/run/sock" ]] || { echo "Non-existent folder: /run/sock" >&2; return 1; }

	    if [[ \$APP_NETWORK == 'unix' ]] && [[ -S "\$APP_ADDRESS" ]]; then
	       rm "\$APP_ADDRESS" || return
	    fi
	    
		./$binaryFilename || return
	}

	main "\$@"

	EOT
}


go-service-gen-stop-script ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: go-service-gen-unit-file infovar\n' >&2; return 1; }
    local -n _appInfo=$1

    cat <<- EOT
	#! /usr/bin/env bash

	main ()
	{
	    # shellcheck disable=SC2016
	    [[ -n "\$APP_NETWORK" ]] || { echo 'Please set \$APP_NETWORK' >&2; return 1; }
	    # shellcheck disable=SC2016
	    [[ -n "\$APP_ADDRESS" ]] || { echo 'Please set \$APP_ADDRESS' >&2; return 1; }

	    if [[ \$APP_NETWORK == 'unix' ]] && [[ -S "\$APP_ADDRESS" ]]; then
	        rm "\$APP_ADDRESS"
	    fi
	}

	main "\$@"

	EOT
}

go-service-gen-unit-file ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: go-service-gen-unit-file infovar\n' >&2; return 1; }
    local -n _appInfo=$1
    local description=${_appInfo[description]}
    local name=${_appInfo[name]}
    # shellcheck disable=SC2016
    [[ -n "$description" ]] || { echo '$description is not set' >&2; return 1; }
    # shellcheck disable=SC2016
    [[ -n "$name" ]] || { echo '$name is not set' >&2; return 1; }
    
    cat <<- EOT
	[Unit]
	Description=$description

	[Service]
	EnvironmentFile=/opt/svc/$name/config.env
	ExecStart=/opt/svc/$name/run.sh
	ExecStop=/opt/svc/$name/stop.sh
	Type=exec
	User=rayray
	WorkingDirectory=/opt/svc/$name

	[Install]
	WantedBy=multi-user.target
	EOT
}


go-service-install ()
{
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: go-service-install $user $name\n' >&2; return 1; }
	# shellcheck disable=SC2016
	[[ -n "$GITHUB_ACCESS_TOKEN" ]] || { echo 'Please set $GITHUB_ACCESS_TOKEN' >&2; return 1; }
	local user=$1
	local name=$2

	# Pull app info from cluster
	local -A appInfo
	pullAppInfo appInfo "$user" "$name" || return
	declare -p appInfo

	# Get name of vm to user
	local vmName; vmName=$(getVmName appInfo "$user") || return
	declare -p vmName

	# Get release info, in preparation for downloading the release binary
	local org=${appInfo[org]}
	local repo=${appInfo[repo]}
	local releaseName=${appInfo[releaseName]}
    # shellcheck disable=SC2016
	[[ -n "$org" ]] || { echo '$org is not set' >&2; return 1; }
    # shellcheck disable=SC2016
	[[ -n "$repo" ]] || { echo '$repo is not set' >&2; return 1; }
    # shellcheck disable=SC2016
	[[ -n "$releaseName" ]] || { echo '$releaseName is not set' >&2; return 1; }
	local -A releaseInfo
	github-get-release-package-info releaseInfo "$org" "$repo" "$releaseName" || return
	declare -p releaseInfo

	# download the release binary
	local downloadUrl=${releaseInfo[url]}
	local filename=${releaseInfo[filename]}
	local downloadPath="/tmp/$filename"
	# shellcheck disable=SC2016
	[[ -n "$GITHUB_ACCESS_TOKEN" ]] || { echo 'Please set $GITHUB_ACCESS_TOKEN' >&2; return 1; }
    curl --location \
         --verbose \
         --fail-with-body \
         --header "Accept: application/octet-stream" \
         --header "Authorization: Token $GITHUB_ACCESS_TOKEN" \
         --output "$downloadPath" \
         "$downloadUrl" \
    || return
    printf '%s' "$downloadPath"
	file "$downloadPath"

	# Create a tmp folder for service folder, and populate it
	local distroFolder; distroFolder=$(create-temp-folder "$name.distro") || return
	go-service-gen-unit-file appInfo >"$distroFolder/$name.service"
	go-service-gen-run-script appInfo >"$distroFolder/run.sh"
	chmod 777 "$distroFolder/run.sh"
	go-service-gen-stop-script appInfo >"$distroFolder/stop.sh"
	chmod 777 "$distroFolder/stop.sh"
	envFilePath=${appInfo[envFilePath]}
    # shellcheck disable=SC2016
	[[ -n "$envFilePath" ]] || { echo '$envFilePath is not set' >&2; return 1; }
	cp "$envFilePath" "$distroFolder/config.env" || return
	tar -C "$distroFolder" -xzvf "$downloadPath" || return
	echo
	printf '%s\n' "$distroFolder"

	# tar the distro
	echo
	printf '=== %s ===\n' "tar the distro"
	echo
	local tarballName="$name.distro.tgz"
	local tarballPath="./$tarballName"
	tar -C "$distroFolder/" -czf "$tarballPath" .
	# read -r -p "Ok? "

	# push distro to vm
	echo
	printf '=== %s ===\n' "push distro to vm"
	echo
    # shellcheck disable=SC2086
	incus exec "$vmName" -- bash -c "if [[ -f "/tmp/$tarballName" ]]; then rm "/tmp/$tarballName"; fi"
	incus file push "$tarballPath" "$vmName/tmp/$tarballName"
	# read -r -p "Ok? "

	# untar distro on vm
	echo
	printf '=== %s ===\n' "untar distro on vm"
	echo
	incus exec "$vmName" -- mkdir -p "/opt/svc/$name"
	incus exec "$vmName" -- tar --preserve-permissions -C "/opt/svc/$name" -xzf "/tmp/$tarballName"
	incus exec "$vmName" -- chown -R rayray:rayray "/opt/svc/$name"
	# read -r -p "Ok? "

	# enable + start service
	echo
	printf '=== %s ===\n' "enable + start service"
	echo
	incus exec "$vmName" -- systemctl enable "/opt/svc/$name/$name.service"
	incus exec "$vmName" -- systemctl start "$name"
	# read -r -p "Ok? "

	# create unix-to-unix incus proxy
	echo
	printf '=== %s ===\n' "create unix-to-unix incus proxy"
	echo
	incus config device add "$vmName" uu proxy "connect=unix:/run/sock/$name.sock" "listen=unix:/run/sock/$name.sock" mode=777
	# read -r -p "Ok? "

	# gen nginx file + create enabled symlink
	echo
	printf '=== %s ===\n' "gen nginx file + create enabled symlink"
	echo
	local domain=${appInfo[domain]}
    # shellcheck disable=SC2016
	[[ -n "$domain" ]] || { echo '$domain is not set' >&2; return 1; }
	local domainFilePath="/tmp/$domain"
	go-service-gen-nginx-domain-file appInfo >"$domainFilePath"
	cp "$domainFilePath" "/etc/nginx/sites-available/$domain"
	ln -s "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
	read -r -p "Ok? "

	# test endpoint
	echo
	printf '=== %s ===\n' "test endpoint"
	echo
	local testEndpoint=${appInfo[testEndpoint]}
    # shellcheck disable=SC2016
	[[ -n "$testEndpoint" ]] || { echo '$testEndpoint is not set' >&2; return 1; }
	curl --unix-socket "/run/sock/$name.sock" "http:/$testEndpoint"
	read -r -p "Ok? "

	# run certbot & restart nginx
	echo
	printf '=== %s ===\n' "run certbot & restart nginx"
	echo
	certbot --nginx -n -d "$domain" --agree-tos --email chris@dylt.dev  || return
	nginx -t || return
	read -r -p "Ok? "

	# test domain from public internet
	curl "$domain"
	read -r -p "Ok? "
}


go-service-uninstall ()
{
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: go-service-uninstall $user $name\n' >&2; return 1; }
	# shellcheck disable=SC2016
	# [[ -n "$GITHUB_ACCESS_TOKEN" ]] || { echo 'Please set $GITHUB_ACCESS_TOKEN' >&2; return 1; }
	local user=$1
	local name=$2

	# Pull app info from cluster
	local -A appInfo
	pullAppInfo appInfo "$user" "$name" || return
	declare -p appInfo
	
	# Get vm name for app from cluster	
	echo
	printf '=== %s ===\n' "Get vm name for app from cluster"
	echo
	local key="/#/$user/app/$name/vm"
	local vmName; vmName=$(ec get --print-value-only "$key") || return
	echo
	read -r -p "Ok? " _

	# Stop+disable service, and remove service folder
	echo
	printf '=== %s ===\n' "Stop+disable service, and remove service folder"
	echo
	if incus exec "$vmName" -- bash -c 'systemctl cat mc15 >/dev/null 2>&1'; then
		incus exec "$vmName" -- systemctl stop "$name"
		incus exec "$vmName" -- systemctl disable "$name"
		incus exec "$vmName" -- rm -r "/opt/svc/$name"
	fi
	echo
	read -r -p "Ok? " _

	# Remove UU proxy
	echo
	printf '=== %s ===\n' "Remove UU proxy"
	echo
	if incus config device get "$name" uu type >/dev/null 2>&1; then
		incus config device remove "$name" uu
	fi
	echo
	read -r -p "Ok? " _

	# Remove nginx symlink from sites-enabled and domain file from sites-available
	echo
	printf '=== %s ===\n' "Remove nginx stuff"
	echo
	domain=${appInfo[domain]}
    # shellcheck disable=SC2016
	[[ -n "$domain" ]] || { echo '$domain is not set' >&2; return 1; }
	if [[ -h "/etc/nginx/sites-enabled/$domain" ]]; then
		rm "/etc/nginx/sites-enabled/$domain" || return
	fi
	if [[ -f "/etc/nginx/sites-available/$domain" ]]; then
		rm "/etc/nginx/sites-available/$domain" || return
	fi
	echo
	read -r -p "Ok? " _

	# Delete certbot certificates
	echo
	printf '=== %s ---\n' "Delete certbot certificates"	
	echo
	domain=${appInfo[domain]}
    # shellcheck disable=SC2016
	[[ -n "$domain" ]] || { echo '$domain is not set' >&2; return 1; }
	certbot delete --cert-name "$domain"
	echo
	read -r -p "Ok? " _
}


###
# Upgrade go on the host. Install go if it hasn't been previously installed.
# There's currently no good way to query what the latest version of go is.
# go isn't released on GitHub, so the GitHub API is no help. The only way to 
# specify a version is to pass it on the command line.
###
go-upgrade ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: go-upgrade $version\n' >&2; return 1; }
    local version=$1

    local goDownloadFile="go$version.linux-amd64.tar.gz"
    local goDownloadUrl=https://go.dev/dl/$goDownloadFile
    local goDownloadPath; goDownloadPath=$(mktemp --tmpdir "$goDownloadFile.XXXXXX") || return
    curl --fail-with-body \
         --location \
         --silent \
         --output "$goDownloadPath" \
         "$goDownloadUrl" \
         || return
    if [[ -d /usr/local/go/ ]]; then
        if [[ -d /usr/local/go.backup ]]; then
            rm -rd /usr/local/go.backup || return
        fi
        mv /usr/local/go/ /usr/local/go.backup/ || return
        chown -R rayray:rayray /usr/local/go.backup/
    fi
    mkdir -p /usr/local/go/ || return
    tar --directory /usr/local/ --extract --gunzip --file "$goDownloadPath" || return
    chown -R rayray:rayray /usr/local/go/
    dt=$(date)
    cat >> /home/rayray/.bashrc <<- EOT

	# Added by daylight on $dt
	PATH=$PATH:/usr/local/go/bin

EOT
}


hello ()
{
    printf "Hello!\n"
}


incus-create-ssh-profile ()
{
	# shellcheck disable=SC2016
	{ (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: incus-create-www-profile [$sshPort]\n' >&2; return 1; }
	local sshPort=${1:-22}
    # profile: serve HTTP/S
    incus profile create www || return
    incus profile device add www ssh proxy listen="tcp:0.0.0.0:$sshPort" connect=tcp:127.0.0.1:22 || return
}


incus-create-www-profile ()
{
	# shellcheck disable=SC2016
	{ (( $# >= 0 )) && (( $# <= 2 )); } || { printf 'Usage: incus-create-www-profile [$httpPort [$httpsPort]]\n' >&2; return 1; }
	local httpPort=${1:-80}
	local httpsPort=${2:-443}
    # profile: serve HTTP/S
    incus profile create www || return
    incus profile device add www http proxy listen"=tcp:0.0.0.0:$httpPort" connect=tcp:127.0.0.1:80 || return
    incus profile device add www https proxy listen="tcp:0.0.0.0:$httpsPort" connect=tcp:127.0.0.1:443 || return
}


###
# 
# Pull a file from a vm to a newly created temp folder
# Return path of new file
#
incus-pull-file ()
{
	local vm=$1
	local srcPath=$2

	local tmpFolder; tmpFolder=$(mktemp --directory --tmpdir incus.pull.file.XXXXXX) || return
	local dstPath_q; dstPath_q=$(printf '%s' "$dstPath") || return
	incus file pull "$vm$srcPath" "$tmpFolder/" || return
	local filename; filename=$(basename "$srcPath") || return
	local remotePath="$tmpFolder/$filename"
	printf '%s' "$remotePath"
}

incus-push-file ()
{
	# shellcheck disable=SC2016
	(( $# == 3 )) || { printf 'Usage: incus-push-file "$srcPath" "$vm" "$dstPath"\n' >&2; return 1; }
	local srcPath=$1
	local vm=$2
	local dstPath=$3
	
	local dstPath_q; dstPath_q=$(printf '%s' "$dstPath") || return
	# incus requries a trailing slash if the destination is a folder
	if incus exec "$vm" -- bash -c "[[ -d $dstPath_q ]]"; then
		if [[ $dstPath != */ ]]; then
			dstPath="$dstPath/"
		fi
	fi
	incus file push "$srcPath" "$vm$dstPath"
}


incus-remove-file ()
{
	# shellcheck disable=SC2016
	(( $# == 2 )) || { printf 'Usage: incus-push-file "$vm" "$dstPath"\n' >&2; return 1; }
	local vm=$1
	local dstPath=$2

	# @note this possibly fails-to-fail on a missing/unavailable vm
	local dstPath_q; dstPath_q=$(printf '%q' "$dstPath") || return
	if incus exec "$vm" -- bash -c "[[ -e $dstPath_q ]]"; then
		incus exec "$vm" -- bash -c "rm $dstPath_q" || return
	fi
}


# Initialize an alpine VM with daylight's requirements
# - install packages
# - create rayray user & group
init-alpine ()
{
    apk update
    apk upgrade

    # Add packages
    apk add bash curl jq sudo

    # Add rayray user
    addgroup -g 2000 rayray
    adduser -g 'rayray - daylight user' -D -u 2000 -G rayray -s /bin/bash rayray

    # Add sudo + doas support for rayray
    echo 'permit nopass rayray' >/etc/doas.d/rayray.conf
    echo 'rayray ALL = (root) NOPASSWD: ALL' >/etc/sudoers.d/01-rayray
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


init-rpi ()
{
    # Create rayray user
    sudo: true
    # On Debian etc, adduser does not have a way to explicitly specify gid so 
    # that uid and guid match. It appears the current behavior is to create
    # a usergroup with matching gid by default, though that appears to be 
    # undocumented.
    adduser --comment 'rayray - daylight user' \
            --disabled-password \
            --uid 2000 \
            --shell /bin/bash \
            rayray \
            || { printf 'Unable to create rayray user.\n' >&2; return 1; }

    # Make rayray owner of all things /opt/bin/
    [[ -d "/opt/bin/" ]] || { printf 'Non-existent folder: /opt/bin/\n' >&2; return 1; }
    chown -R rayray:rayray /opt/bin/

    # Set rayray up for sudo
    [[ -d "/etc/sudoers.d" ]] || { printf 'Non-existent folder: /etc/sudoers.d\n' >&2; return 1; }
    echo 'rayray ALL = (root) NOPASSWD: ALL' >/etc/sudoers.d/01-rayray

    # Install service to check daylight.sh every hour for updates
    install-fresh-daylight-svc || return

    # Install dylt CLI
    install-dylt Linux_arm64 /opt/bin/ || return
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
    # This command needs to be run as rayray, since we want to set the rayray user's default region
    su rayray --login --command "aws configure set default.region $defaultRegion" || return
}


install-dylt ()
{
    # shellcheck disable=SC2016
    { (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: install-dylt [$dstFolder]\n' >&2; return 1; }
    local dstFolder=${1:-/opt/bin/}
    [[ -d "$dstFolder" ]] || { echo "Non-existent folder: $dstFolder" >&2; return 1; }

    tmpFolder=${TMPDIR:-/tmp}
    dyltPath=$(download-dylt "$dstFolder") || return
    tar -C "$dstFolder" -xzf "$dyltPath" || return
    chmod 777 "$dstFolder/dylt" || return
}


# Install etcd from source
#   - Get latest version
#   - Get the URL for the latest release
#   - Download the tarball of the latest release
#   - Install the release in the specified install folder
#   - Setup the data directory
#   - Generate the systemd unit file
#   - Generate a run script specifying the DNS SRV name for the cluster
#   - Setup permissions
#   - Enable + start the service
install-etcd ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: install-etcd $discSvr $ip $name\n' >&2; return 1; }
    local discSvr=$1
    local ip=$2
    local name=$3
    # Download and install the latest binary
    etcd-install-latest "$installFolder"
    # Handle the data directory
    etcd-setup-data-dir /var/lib/etcd
    # Create & start a systemd service
    etcd-install-service "$discSvr" "$name" "$ip"
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
    mkdir -p /opt/svc/fresh-daylight/bin 
    chown -R rayray:rayray /opt/svc/fresh-daylight
    curl --silent --remote-name --output-dir /opt/svc/fresh-daylight "$repo/svc/fresh-daylight/fresh-daylight.service"
    curl --silent --remote-name --output-dir /opt/svc/fresh-daylight "$repo/svc/fresh-daylight/fresh-daylight.timer"
    curl --silent --remote-name --output-dir /opt/svc/fresh-daylight/bin "$repo/svc/fresh-daylight/bin/run.sh"
    chmod 777 /opt/svc/fresh-daylight/bin/run.sh
    systemctl enable /opt/svc/fresh-daylight/fresh-daylight.service
    systemctl enable /opt/svc/fresh-daylight/fresh-daylight.timer
    systemctl start fresh-daylight.timer
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


install-pubbo ()
{
    [[ -d "/opt/bin/" ]] || { echo "Non-existent folder: /opt/bin/" >&2; return 1; }
    github-install-latest-release dylt-dev pubbo linux_amd64 /opt/bin/
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
    sudo chown -R rayray:rayray /app || return
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
    chown -R rayray:rayray "$serviceFolder"|| return

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
    # chown rayray:rayray /usr/bin/shell_script_per_*.py
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
    chown -R rayray:rayray "$shrHome"
    if [[ -f ./svc.sh ]] && ./svc.sh status >/dev/null; then
        ./svc.sh uninstall
        su -c "./config.sh remove --token $shrToken" rayray
    fi
    su -c "./config.sh --unattended \
          --url $repoUrl \
          --token $shrToken \
          --replace \
          --name ubuntu-dev \
          --labels $labels" \
          rayray
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


# list all bash functions in a bash script, sorted
# the bash script is a stdin redirection
list-bash-funcs ()
{
	# shellcheck disable=SC2016
	(( $# == 0 )) || { printf 'Usage: list-bash-funcs <bashScript.sh\n' >&2; return 1; }
	# Confirm user is not interactive
	if [[ -t 0 ]]; then
		printf '\nstdin is a terminal; please redirect input from stdin.\n\n';
		return 0
	fi

	# grep for all function declarations
	# then, grep again to get just the function names from the delcarations
	# @note this might be possible in one grep, but for now 2 greps is fine
    grep --extended-regexp \
          '^[A-Za-z0-9_-]+ \(\)' \
          /opt/bin/daylight.sh \
    | grep --extended-regexp \
           --only-matching \
           '^[A-Za-z0-9_-]+' \
    | sort
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


list-git-repos () 
{ 
	# shellcheck disable=SC2016
	{ (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: list-git-remotes $repo [$shrHome]\n' >&2; return 1; }
    repo=$1;
    shrHome=${2:-/opt/actions-runner/_work};
    shrPath="$shrHome/$repo/$repo";
    git -C "$shrPath" remote --verbose
}


list-host-public-keys ()
{
    # shellcheck disable=SC2016
    (( $# >= 0 && $# <= 1 )) || { printf 'Usage: list-host-public-keys [$keyFolder=/etc/ssh/]\n' >&2; return 1; }
    local keyFolder=${1:-/etc/ssh/}
    # shellcheck disable=SC2016
    [[ -d "$keyFolder" ]] || { printf 'Non-existent folder: $keyFolder\n' >&2; return 1; }

    local rx='^([[:digit:]]*) (.*):(.*) (.*) \((.*)\)'
    while read -r path; do
        local line; line=$(ssh-keygen -l -f "$path") || return
        if [[ "$line" =~ $rx ]]; then
            printf '%-10s\t%s\n' "${BASH_REMATCH[5]}" "${BASH_REMATCH[3]}"
        fi
    done < <(find "$keyFolder" -maxdepth 1 -name '*.pub')
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


list-shr-entries () 
{ 
	# shellcheck disable=SC2016
	{ (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: list-shr-entries [shrHome]\n' >&2; return 1; }
    shrHome=${1:-/opt/actions-runner/_work};

    ( cd "$shrHome" && find . -mindepth 1 -maxdepth 1 -type d -regex '^\./[A-Za-z0-9].*$' )
}

list-vms ()
{
    local bucket; bucket=$(get-bucket) || return
    aws s3api list-objects --bucket "$bucket" --prefix 'dist/vm' --query 'Contents[].Key[]' | jq -r '.[] | match("^dist/vm/(.*)\\.tgz$").captures[0].string' || return
}


lxd-dump-id-map ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: lxd-dump-id-map $container\n' >&2; return 1; }
    local container=$1

    local idMapPath; idMapPath=$(create-temp-file "$container.idmap.XXXXXX") || return
    lxc query "/1.0/containers/$container" | jq -r '.expanded_config["raw.idmap"] // empty' | awk NF > "$idMapPath"
    printf '%s' "$idMapPath"
}


lxd-instance-exists ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: lxc-instance-exists $container\n' >&2; return 1; }
    local name=$1
    lxc query "/1.0/instances/$name" >/dev/null 2>&1
}


lxd-set-id-map ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: lxd-set-id-map $container $idMapPath\n' >&2; return 1; }
    local container=$1
    local idMapPath=$2

    lxc config set "$container" raw.idmap - < <(sort "$idMapPath" | uniq)
    lxc restart "$container" 2>/dev/null || lxc start "$container"
    lxc exec "$container" -- cloud-init status --wait
}


lxd-share-folder ()
{
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: lxd-share-folder $container $share $srcDir $dstDir\n' >&2; return 1; }
    local container=$1
    lxd-instance-exists  "$container" || { printf 'Non-existent container: %s\n' "$container"; return 1; }
    local share=$2
    local srcDir=$3
    [[ -d "$srcDir" ]] || { echo "Non-existent folder: $srcDir" >&2; return 1; }
    local dstDir=$4
    lxc config device add "$container" "$share" disk source="$srcDir" path="$dstDir"
}



prep-filesystem ()
{
    mkdir -p /etc/nginx/streams.d/
    chmod 777 /etc/nginx/streams.d/
    mkdir -p /opt/actions-runner/
    mkdir -p /opt/bin/
    mkdir -p /opt/svc/
}


prep-service ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: prep-service $svcName\n' >&2; return 1; }
    [[ -d "/opt/svc/" ]] || { echo "Non-existent folder: /opt/svc/" >&2; return 1; }
    svcName=$1

    mkdir -p "/opt/svc/$svcName"
    mkdir -p "/opt/svc/$svcName/bin"
}


print-os-arch-vars ()
{
    print-vars HOSTTYPE MACHTYPE OSTYPE
}


print-vars ()
{
    for varname in "$@"; do
        printf '%s=%s\n' "$varname" "${!varname}"
    done
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


pullAppInfo ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: pullAppInfo infovar $user $appName\n' >&2; return 1; }
    local -n _appInfo=$1
    local user=$2
    local name=$3

    appInfo[name]=$name
    local -a args
    local prefix="/$/$user/app/$name"
    IFS=$'\t' read -r -a args < <( \
        ec get --prefix "$prefix" --write-out json \
        | jq -r '.kvs 
                | [.[] | {key: (.key | @base64d | match(".*/(.*)") | .captures[0].string),
                        value: .value | @base64d}]
                | from_entries
                | [.binaryFilename, .description, .domain, .org, .releaseName, .repo, .testEndpoint, .type] | @tsv') \
        || return
    _appInfo[binaryFilename]=${args[0]}
    _appInfo[description]=${args[1]}
    _appInfo[domain]=${args[2]}
    _appInfo[org]=${args[3]}
	_appInfo[releaseName]=${args[4]}
    _appInfo[repo]=${args[5]}
	_appInfo[testEndpoint]=${args[6]}
    # shellcheck disable=SC2154
    _appInfo[type]=${args[7]}
    # envFile requires special handling
    local tmpEnvFile; tmpEnvFile=$(create-temp-file "$name.envFile") || return
    local envFileKey="/$/$user/app/$name/envFile"
    ec get --print-value-only "$envFileKey" >"$tmpEnvFile"
    _appInfo[envFilePath]="$tmpEnvFile"
}

#
# Download and source the latest daylight.sh from github. Crucial for debugging.
#
# DEPRECATED - use download-daylight instead
#
pull-daylight ()
{
    curl -s https://raw.githubusercontent.com/daylight-public/daylight/master/daylight.sh >/usr/bin/daylight.sh
    chmod 777 /usr/bin/daylight.sh
    # shellcheck source=/dev/null
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
    # local repoPath="$repoFolder/$repo"

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
    # local baseRepo
    # local baseName
    # if [[ "$base" == *:* ]]; then
    #     baseRepo="${base%%:*}"
    #     baseName="${base##*:}"
    # else
    #     baseRepo='local'
    #     baseName="$base"
    # fi

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


###
#
# read-kvs()
#
# Consume a stream of NUL-delimited \n-terminated key-value pairs, and create an associative
# array from all the kvs
#
# Args
#   stdin       stream of key-value pairs
#   $1          assoc array nameref
#
# Returns
#   kvs         assoc array populated with keys+values
#
read-kvs ()
{
    # shellcheck disable=SC2016
    (( $# >= 1 && $# <= 2 )) || { printf "Usage: read-kvs nkvs\n" >&2; return 1; }
    # shellcheck disable=SC2178
    [[ $1 != nkvs ]] && { local -n nkvs; nkvs=$1; }
    if [[ -v ${!nkvs} ]] && [[ ! ${nkvs@a} =~ A ]]; then
        printf 'arg is not an associative array\n' >&2; return 1;
    fi
    nkvs=()

    # read all NUL-delimited data in at once. This is necessary since bash has
    # no way to store lines containing NULs.
    local -a data
    readarray -t -d '' data || return

    local i=0
    while (( i < ${#data[@]} )); do
        k=${data[i]}
        v=${data[i+1]} 
        if [[ -n "$k" ]]; then
            nkvs["$k"]=$v
        fi
        (( i=i+2 ))
    done
}


replace-nginx-conf ()
{
    # shellcheck disable=SC2016
    { (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: replace-nginx-conf [$nginxFolder]\n' >&2; return 1; }
    nginxFolder=${1:-/etc/nginx}
    nginxPath="$nginxFolder/nginx.conf"
    cp "$nginxPath" "$nginxPath.orig"
    cat >"$nginxPath" <<- 'EOT'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;
include /etc/nginx/streams.d/*.conf;

events {
    worker_connections 768;
    # multi_accept on;
}

http {

    ##
    # Basic Settings
    ##

    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;
    # server_tokens off;

    # server_names_hash_bucket_size 64;
    # server_name_in_redirect off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings
    ##

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
    ssl_prefer_server_ciphers on;

    ##
    # Logging Settings
    ##

    access_log /var/log/nginx/access.log;

    ##
    # Gzip Settings
    ##

    gzip on;

    # gzip_vary on;
    # gzip_proxied any;
    # gzip_comp_level 6;
    # gzip_buffers 16 8k;
    # gzip_http_version 1.1;
    # gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    ##
    # Virtual Host Configs
    ##

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOT

	# Restart nginx, to validate and pickup the new config file
	restart-nginx
}


restart-nginx ()
{
    if ! nginx -t; then
        printf "Error with nginx config.\n" >&2
        return 1
    fi
    systemctl restart nginx
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
    /opt/bin/nginxer "$domain" "$port" 2>/dev/null | cat - >"/etc/nginx/sites-available/$domain"
    ln -sf "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
    # User certbot to create the cert files and update the nginx unit files
    /opt/venv/main/bin/certbot --nginx -n --agree-tos --domain "$domain" --email "$email"
    # Create tar file of cert files
    tar -C /etc/letsencrypt/ -czf "/tmp/setup/$domain-certs.tar.gz" \
        "./archive/$domain" \
        "./live/$domain" \
        "./renewal/$domain.conf"
    # Create tar file of nginx unit files
    tar -C /etc/nginx/ -czf "/tmp/setup/$domain-nginx.tar.gz" \
        "./sites-available/$domain" \
        "./sites-enabled/$domain"
}


source-daylight ()
{
    local daylightPath; daylightPath=$(command -v daylight.sh) || return
    # shellcheck source=/dev/null
    source "$daylightPath"
}


source-service-environment-file ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: source-service-environment-file $serviceName\n' >&2; return 1; }
    local name=$1

    set -a
    # shellcheck source=/dev/null
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


sync-add-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	systemctl enable "$unitName" || return
	sync-run-service "$key" "$downloadPath" || return
	sync-follow-service "$key" "$downloadPath" || return

}


sync-create-unit-name () 
{ 
    key=$1;
    downloadPath=$2;
    systemd-escape --template 'sync-daylight@.service' "$key $downloadPath" || return
}


sync-daylight-gen-run-script ()
{
    cat <<- "EOT"
	#! /usr/bin/env bash

	get-key ()
	{
	    # shellcheck disable=SC2016
	    (( $# == 2 )) || { printf 'Usage: get-key $key $downloadPath\n' >&2; return 1; }
	    local key=$1
	    local downloadPath=$2

	    # etcdctl get, redirect to tempfile, and cp to proper location on success
	    local tmpfile; tmpfile="$(mktemp --tmpdir daylight.sh.XXXXXX)" || return
	    printf 'Reading %s from cluster & writing to temp file at %s ... ' "$key" "$tmpfile"
	    if ! /opt/etcd/etcdctl \
	        --discovery-srv hello.dylt.dev \
	        get --print-value-only "$key" >"$tmpfile"
	    then
	        local rc=$?
	        printf 'Failed to read %s from cluster\n' "$key" >&2
	        return $?
	    else
	        printf 'OK\n'
	        printf 'Copying %s to %s... ' "$tmpfile" "$downloadPath"
	        cp "$tmpfile" "$downloadPath" || return
	        printf 'OK\n'
	    fi
	}

	watch-key ()
	{
	    # shellcheck disable=SC2016
	    (( $# == 2 )) || { printf 'Usage: get-key $key $downloadPath\n' >&2; return 1; }
	    local key=$1
	    local downloadPath=$2

	    export -f get-key
	    printf 'Watching cluster key %s ...\n' "$key"
	    /opt/etcd/etcdctl \
	        --discovery-srv hello.dylt.dev \
	        watch "$key" \
	        -- bash -c "get-key $key $downloadPath" \
	        || return
	}

	main ()
	{
	    # shellcheck disable=SC2016
	    (( $# == 1 )) || { printf 'Usage: run.sh $argstring\n' >&2; return 1; }
	    local argstring=$1

	    # systemd passes in all the args as one single string, delimited by spaces.
	    # we read the argstring into an array to split it
	    local -a args=($argstring)
	    local key=${args[0]}
	    local downloadPath=${args[1]}

	    get-key "$key" "$downloadPath" || return
	    watch-key "$key" "$downloadPath" || return
	}

	(return 0 2>/dev/null) || main "$@"
	EOT
}


sync-daylight-gen-unit-file ()
{
    cat <<- "EOT"
	[Unit]
	Description=Watch cluster for updates to a key and write new value to a file.

	[Service]
	ExecStart=/opt/svc/sync-daylight/run.sh %I
	Restart=on-failure
	RestartMode=normal
	RestartSec=60
	Type=exec
	User=rayray
	WorkingDirectory=/opt/svc/sync-daylight

	[Install]
	WantedBy=multi-user.target
	EOT
}


sync-daylight-install-service ()
{
	local svc=sync-daylight
	local svcFolder="/opt/svc/$svc"
	mkdir -p "$svcFolder"
    sync-daylight-gen-unit-file >"$svcFolder/$svc@.service"
    sync-daylight-gen-run-script >"$svcFolder/run.sh"
    chown -R rayray:rayray "$svcFolder/"
    chmod 755 "$svcFolder/run.sh"
    sudo systemctl enable "$svcFolder/$svc@.service"
}


sync-follow-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	journalctl --unit "$unitName" --follow  || return
}


sync-remove-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	systemctl disable "$unitName" || return
}


sync-run-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	systemctl start "$unitName" || return
}


###
# Start a systemd service.
# On failure, run journalctl to look at what happened.
###
sys-start ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: sys-start $service\n' >&2; return 1; }
    local service=$1

    systemctl restart "$service" || journalctl --unit "$service"
}


# Uninstall an installed etcd service.
#
# @Note this doesn't do any checking to see if any of the assets exist.
# And it probably should.
uninstall-etcd ()
{
    systemctl stop etcd
    systemctl disable etcd 
    rm -r /var/lib/etcd/ 2>/dev/null
    rm -r /opt/etcd/ 2>/dev/null
    rm -r /opt/svc/etcd/ 2>/dev/null
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


###
# Pretty self-explanatory. A useful function to bounce VMs
###
update-and-restart ()
{
    if (( EUID != 0 )); then
        printf 'You must be root to do this\n' >&2
        return 1
    fi 

    apt update -y
    apt upgrade -y
    reboot
}


###
# @deprecated - Please use dylt if possible
#
# Generate a run script for the watch-daylight.service
watch-daylight-gen-run-script ()
{
    cat <<- "EOT"
	#! /usr/bin/env bash

	main () 
	{ 
	    printf "Downloading current script ...\n";
	    # etcdctl get, redirect to tempfile, and cp to proper location on success
	    local tmpfile; tmpfile="$(mktemp --tmpdir daylight.sh.XXXXXX)" || return
	    if ! /opt/etcd/etcdctl \
	        --discovery-srv hello.dylt.dev \
	        get --print-value-only /daylight.sh >"$tmpfile";
	    then
	        local rc=$?
	        printf '%s\n' "Failed to download /daylight.sh from cluster" >&2
	        return $?
	    else
	        printf 'Download succeeded. Copying script to final location ...\n'
	        cp "$tmpfile" /opt/bin/daylight.sh
	    fi
	    printf 'Watching for further updates ....\n'
	    /opt/etcd/etcdctl \
	        --discovery-srv hello.dylt.dev \
	        watch /daylight.sh \
	            -- sh -c '{ printf "Downloading update ..."; tmpfile="$(mktemp --tmpdir daylight.sh.XXXXXX)"; /opt/etcd/etcdctl --discovery-srv hello.dylt.dev get --print-value-only /daylight.sh >"$tmpfile"; cp "$tmpfile" /opt/bin/daylight.sh; printf "Complete.\n"; }' || return
	}

	main "$@"

	EOT
}


###
# @deprecated - Please use dylt if possible
#
watch-daylight-gen-unit-file ()
{
    cat <<- "EOT"
	[Unit]
	Description=Watch cluster for /daylight.sh 

	[Service]
	ExecStart=/opt/svc/watch-daylight/run.sh
	Restart=on-failure
	RestartMode=normal
	RestartSec=60
	Type=exec
	User=rayray
	WorkingDirectory=/opt/svc/watch-daylight

	[Install]
	WantedBy=multi-user.target
	EOT
}


###
# @deprecated - Please use dylt if possible
#
watch-daylight-install-service ()
{
	local svc=watch-daylight
	local svcFolder="/opt/svc/$svc"
	mkdir -p "$svcFolder"
    watch-daylight-gen-unit-file >"$svcFolder/$svc.service"
    watch-daylight-gen-run-script >"$svcFolder/run.sh"
    chmod 755 "$svcFolder/run.sh"
    sudo systemctl enable "$svcFolder/$svc.service"
    sudo systemctl start "$svc"
    chown -R rayray:rayray "$svcFolder/"
}


yesno ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: yesno varname $prompt\n' >&2; return 1; }
    local prompt=$1
    local -n varname=$2

    while :; do
        read -r -p "$prompt" varname
        if [[ ${varname,,} =~ y|n|yes|no ]]; then
            break
        fi
    done
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
    # shellcheck source=/dev/null
    source /opt/bin/daylight.sh
    printf '%s\n' "Installing fresh-daylight service ..."
    printf '\n' 
    install-fresh-daylight-svc
    if [[ -f /home/rayray/.bashrc ]]; then
    {
        printf '%s\n' ""
        printf '%s\n' "# hello from daylight"
        printf '%s\n' "source /opt/bin/daylight.sh"
    } >> /home/rayray/.bashrc;
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
            create-pubbo-service) create-pubbo-service "$@";;
            create-service-from-dist-script)	create-service-from-dist-script "$@";;
            create-static-website)	create-static-website "$@";;
            delete-lxd-instance)	delete-lxd-instance "$@";;
            download-app)	download-app "$@";;
            download-dylt)	download-dylt "$@";;
            download-daylight)	download-daylight "$@";;
            download-dist)	download-dist "$@";;
            download-flask-app)	download-flask-app "$@";;
            download-flask-service)	download-flask-service "$@";;
            download-public-key)	download-public-key "$@";;
            download-shr-tarball)	download-shr-tarball "$@";;
            download-svc)	download-svc "$@";;
            download-to-temp-dir)	download-to-temp-dir "$@";;
            download-vm)	download-vm "$@";;
            etcd-create-download-url) etcd-create-download-url "$@";;
            edit-daylight)	edit-daylight "$@";;
            etcd-download) etcd-download "$@";;
            etcd-download-latest) etcd-download-latest "$@";;
            etcd-gen-run-script) etcd-gen-run-script "$@";;
            etcd-gen-unit-file) etcd-gen-unit-file "$@";;
			etcd-get-latest-version) etcd-get-latest-version "$@";;
            etcd-install-latest) etcd-install-latest "$@";;
            etcd-setup-data-dir) etcd-setup-data-dir "$@";;
            gen-completion-script) gen-completion-script "$@";;
            gen-daylight-completion-script) gen-daylight-completion-script "$@";;
            gen-nginx-flask)	gen-nginx-flask "$@";;
            gen-nginx-static)	gen-nginx-static "$@";;
            generate-unit-file)	generate-unit-file "$@";;
            get-bucket)	get-bucket "$@";;
            get-container-ip)	get-container-ip "$@";;
            github-app-get-client-id) github-app-get-client-id "$@";;
            github-app-get-id) github-app-get-id "$@";;
            github-release-download) github-release-download "$@";;
            github-release-download-latest) github-release-download-latest "$@";;
            get-image-base)	get-image-base "$@";;
            get-image-name)	get-image-name "$@";;
            get-image-repo)	get-image-repo "$@";;
            get-service-file-value)	get-service-file-value "$@";;
            get-service-environment-file)	get-service-environment-file "$@";;
            get-service-exec-start)	get-service-exec-start "$@";;
            get-service-working-directory)	get-service-working-directory "$@";;
            github-create-user-access-token) github-create-user-access-token "$@";;
            github-download-latest-release)    github-download-latest-release "$@";;
            github-get-local-platform)  github-get-local-platform "$@";;
            github-get-release-name-list)   github-get-release-name-list "$@";;
            github-install-latest-release) github-install-latest-release "$@";;
            github-parse-args) github-parse-args "$@";;
            github-release-get-latest-tag) github-release-get-latest-tag "$@";;
            github-test-repo) github-test-repo "$@";;
            github-test-repo-with-auth) github-test-repo-with-auth "$@";;
            go-service-gen-nginx-domain-file) go-service-gen-nginx-domain-file "$@";;
            go-service-install) go-service-install "$@";;
            go-service-uninstall) go-service-uninstall "$@";;
            go-upgrade) go-upgrade "$@";;
            hello) hello "$@";;
            incus-pull-file) incus-pull-file "$@";;
            incus-push-file) incus-push-file "$@";;
            incus-remove-file) incus-remove-file "$@";;
            init-alpine) init-alpine "%@";;
            init-lxd)	init-lxd "$@";;
            init-nginx)	init-nginx "$@";;
            init-rpi) init-rpi "$@";;
            install-app)	install-app "$@";;
            install-awscli)	install-awscli "$@";;
            install-dylt) install-dylt "$@";;
            install-etcd)	install-etcd "$@";;
            install-flask-app)	install-flask-app "$@";;
            install-fresh-daylight-svc)	install-fresh-daylight-svc "$@";;
            install-gnome-keyring)	install-gnome-keyring "$@";;
            install-latest-httpie)	install-latest-httpie "$@";;
            install-mssql-tools)	install-mssql-tools "$@";;
            install-public-key)	install-public-key "$@";;
            install-pubbo) install-pubbo "$@";;
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
            list-funcs) list-funcs "$@";;
            list-host-public-keys) list-host-public-keys "$@";;
            list-public-keys)	list-public-keys "$@";;
            list-services)	list-services "$@";;
            list-vms)	list-vms "$@";;
            print-os-arch-vars) print-os-arch-vars "$@";;
            prep-filesystem) prep-filesystem "$@";;
            print-os-arch-vars) print-os-arch-vars "$@";;
            pullAppInfo) pullAppInfo "$@";;
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
            replace-nginx-conf)	replace-nginx-conf "$@";;
            run-conf-script)	run-conf-script "$@";;
            run-service)	run-service "$@";;
            setup-domain)	setup-domain "$@";;
            source-daylight)	source-daylight "$@";;
            source-service-environment-file)	source-service-environment-file "$@";;
            start-indexed-service)	start-indexed-service "$@";;
            start-service)	start-service "$@";;
            sync-add-service) sync-add-service "$@";;
            sync-create-unit-name) sync-create-unit-name "$@";;
            sync-follow-service) sync-follow-service "$@";;
            sync-remove-service) sync-remove-service "$@";;
            sync-run-service) sync-run-service "$@";;
            sync-daylight-install-service) sync-daylight-install-service "$@";;
            sys-start)	sys-start "$@";;
            uninstall-etcd)	uninstall-etcd "$@";;
            untar-to-temp-folder)	untar-to-temp-folder "$@";;
            update-and-restart)	update-and-restart "$@";;
            watch-daylight-gen-run-script) watch-daylight-gen-run-script "$@";;
            watch-daylight-gen-unit-file) watch-daylight-gen-unit-file "$@";;
            watch-daylight-install-service) watch-daylight-install-service "$@";;	
            *) printf 'Unknown command: %s \n' "$cmd" >&2; return 1;;
        esac
    fi
}

(return 0 2>/dev/null) || main "$@"
