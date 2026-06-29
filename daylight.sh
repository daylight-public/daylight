#! /usr/bin/env bash

# SHR_GRAY=$'\e[90m'
# SHR_GREEN=$'\e[32m'
# SHR_RESET=$'\e[0m'
# SHR_CHECK=$'\u2713'
#-------------------------------------------------------------------------------
#
# activate-flask-app()
#
# Activate a Flask application as a systemd service
#
activate-flask-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: activate-flask-app $name [$srcFolder]\n' >&2; return 1; }
    local name=$1

    activate-svc "flask@" "$name"
}


#-------------------------------------------------------------------------------
# 
# activate-svc()
#
# Enable and start a systemd service unit, with optional timer
#
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


#-------------------------------------------------------------------------------
# 
# activate-vm()
#
# Launch an LXC image as a container and run finishing touches
#
activate-vm ()
{
    # shellcheck disable=SC2016
    # shellcheck disable=SC2016
    { (( $# >= 2 )) && (( $# <= 3 )); } || { printf 'Usage: activate-vm $name $folder [$instanceName] []\n' >&2; return 1; }
    local name=$1
    local srcFolder=$2
    local instanceName=${3:-$name}

    # Create the image, using the instance name
    incus launch "$name" "$instanceName" || return
    # Run the finsihing-touches script
    if [[ -f "$srcFolder/finishing-touches.sh" ]]; then
        # shellcheck disable=SC1091
        source "$srcFolder/finishing-touches.sh"
    fi
}


#-------------------------------------------------------------------------------
#
# add-container-user()
#
# Add a user to an LXC container with id mapping and SSH access
#
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
    # incus exec "$container" -- chown -R "$uid:$gid" "/home/$username" || return

    # Create group for the user, then add user: no home, set uid+gid -- and add to sudo2
    incus exec "$container" -- addgroup --gid "$gid" "$username" || return
    incus exec "$container" -- adduser --disabled-password --gecos '' --uid "$uid" --gid "$gid" "$username" || return
    incus exec "$container" -- bash -l -c 'source /usr/bin/daylight.sh && { getent group sudo2 >/dev/null || create-sudo2-group; }' 
    incus exec "$container" -- adduser "$username" sudo2 || return
    
    # Push the public key to the container, and invoke the public key setup function on the container
    local publicKeyName="${publicKeyPath##*/}"
    incus file push "$publicKeyPath" "$container/tmp/$publicKeyName" || return
    incus exec "$container" -- bash -l -c "source /usr/bin/daylight.sh && install-public-key /home/$username /tmp/$publicKeyName" || return
    
    # Setup the .bashrc so it sources daylight.sh
    incus exec "$container" -- sh -c "printf 'source %s\n' \"$(command -v daylight.sh)\" | sudo tee --append \"/home/$username/.bashrc\""

    incus exec "$container" -- chown -R "$username:$username" "/home/$username"
}


#-------------------------------------------------------------------------------
#
# add-rayray()
#
# Add the rayray user to the system
#
add-rayray ()
{
    (( $# == 0 )) || { printf 'Usage: add-rayray\n' >&2; return 1; }
    
    if ! is-debian; then
        printf 'Error: This system is not Debian-based. Cannot add rayray user.\n' >&2
        return 1
    fi
    
    add-rayray-debian || return
}


#-------------------------------------------------------------------------------
#
# add-rayray-debian()
#
# Create the rayray user on Debian-based systems
#
add-rayray-debian ()
{
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

    # Finish initializing rayray
    init-rayray || return
}


#-------------------------------------------------------------------------------
#
# add-ssh-to-container()
#
# Add an SSH proxy device to an LXC container
#
add-ssh-to-container ()
{
    # shellcheck disable=SC2016
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: add-ssh-to-container $container [$port]\n' >&2; return 1; }
    local container=$1
    local port=${2:-'22'}

    incus config device add "$container" "ssh-$port" proxy listen=tcp:0.0.0.0:"$port" connect=tcp:127.0.0.1:22
}


#-------------------------------------------------------------------------------
#
# add-superuser()
#
# Add a superuser with sudo2 group, SSH key, and shadow id mapping
#
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


#-------------------------------------------------------------------------------
#
# add-to-bashrc()
#
# Add a daylight() function alias to .bashrc
#
add-to-bashrc ()
{
    local bashrc="$HOME/.bashrc"
    local funcName='daylight'
    local daylightPath='/opt/bin/daylight.sh'

    if [[ ! -f "$daylightPath" ]]; then
        printf '`%s` not found at %s — install daylight.sh first\n' "$funcName" "$daylightPath" >&2
        return 1
    fi

    if grep -q "^${funcName}()" "$bashrc" 2>/dev/null; then
        printf '`%s` function already exists in %s — nothing to do\n' "$funcName" "$bashrc"
        return 0
    fi

    cat >> "$bashrc" << EOF

# added by opencode in loyal service to master
$funcName()
{
    $daylightPath "\$@"
}
EOF

    printf 'Added `%s` function to %s\n' "$funcName" "$bashrc"
    printf 'Restart your shell or run: source %s\n' "$bashrc"
    printf 'Then type: %s --help\n' "$funcName"
}


#-------------------------------------------------------------------------------
#
# add-user ()
#
# Add new user to a (probably) newly created VM or instance
#
# @note I've written more recent adduser scripts as one-offs. Maybe this
# functions needs a refresher.
# 
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


#-------------------------------------------------------------------------------
#
# add-user-to-idmap ()
#
# Append a user's uid/gid to an LXC container's id map
#
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


#-------------------------------------------------------------------------------
#
# add-user-to-shadow-ids ()
#
# Update /etc/subuid and /etc/subgid for a user's container mapping
#
# incus has some tricky stuff around user ids and shadow ids, that has
# something to do with making sure that uid/gid 0 on the host don't
# get mapped to uid/gid in the container. This could allow a root user in a
# container to jailbreak into the host and still have root. Or something.
#
# @note this appears to be lxd-specific and might need to be updated for incus
# @note I wrote a whold readme on this, and maybe some of that info would make
# for nice comments
# 
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


#-------------------------------------------------------------------------------
#
# cat-conf-script()
#
# Print a configuration script from the S3 dist bucket
#
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


#-------------------------------------------------------------------------------
#
# create-flask-app()
#
# Create an nginx site, cert, and directory for a Flask application
#
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


#-------------------------------------------------------------------------------
#
# create-github-user-access-token()
#
# @deprecated
# Use github-create-uat instead
#
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


#-------------------------------------------------------------------------------
#
# create-home-filesystem ()
#
# Create a loop device-backed home filesystem for a container user
#
# This appears to be a @legacy function, centered on creating a loop device on
# the host system, mounting the loop device, and then sharing the loop device
# with a container. The result is that the cointainer's filesystem is just a
# single file on the host system, since that's how loop devices work. The idea
# is that if the whole container is a single file, you gain a whole new level 
# of portability.
#
# @note it's unclear if this is actually useful. Containers are pretty portable
# via the lxc API, and layered filesystems (btrfs/zfs) might provide a lot of
# the same benefit under the hood.
# 
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


#-------------------------------------------------------------------------------
#
# create-loopback ()
#
# Helper function for @legacy loopback device functionality. Creates a loopback
# device of a certain size at a certain path.
# 
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


#-------------------------------------------------------------------------------
#
# create-lxd-user-data ()
#
# Create a cloud-init MIME including the special shellscript part-handlers
# (until they are a part of cloud-init!)
# @note now that my handlers are a part of cloud-init, I'm not sure this 
# function has any uses. However it is of historical interest. At least to me.
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


#-------------------------------------------------------------------------------
#
# create-publish-image-service()
#
# Create a systemd service to publish a VM image
#
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


#-------------------------------------------------------------------------------
#
# create-pubbo-service()
#
# Create a service to expose a file over a Unix socket via pubbo
#
# `pubbo` is a simple app that makes a file available over a Unix socket.
# Since Unix sockets already act like files, making a file available as
# a socket doesn't seem that useful. And it isn't _that_ useful. But there
# are tools like nginx and incus proxies that work on Unix sockets but not
# files. `pubbo` can then serve as a bridge, so static content can be published
# very easily without standing up a whole web server or reverse proxy
#
# @note this function is quite coarse-grained
#
create-pubbo-service ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: create-pubbo-service $svcName $filePath $port\n' >&2; return 1; }
    svcName=$1
    filePath=$2
    port=$3
    socketFolder=/run/sock/pubbo
    socketPath="$socketFolder/$svcName.sock"
    .
    prep-service "$svcName"
    
    # Catdoc the unit file
    # @note User=www-data ... not `rayray` or `pubbo`
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


#-------------------------------------------------------------------------------
#
# create-service-from-dist-script()
#
# Create a one-shot service from a dist conf script
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


#-------------------------------------------------------------------------------
#
# create-static-website()
#
# Create an nginx site, cert, and directory for a static website
#
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


#-------------------------------------------------------------------------------
#
# create-sudo2-group()
#
# Create the sudo2 group with passwordless sudo privileges
#
create-sudo2-group ()
{
    sudo addgroup --gid 2000 sudo2
    echo "%sudo2   ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee --append >/dev/null /etc/sudoers.d/%sudo2
}


#-------------------------------------------------------------------------------
#
# create-temp-file()
#
# Create a temporary file with optional template and folder
#
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
#-------------------------------------------------------------------------------
#
# create-temp-folder()
#
# Create a temporary directory with optional template
#
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


#-------------------------------------------------------------------------------
#
# delete-incus-instance()
#
# Safely delete an Incus instance if it exists
#
# incus does not have a nice way of safely deleting a VM if it does not exist; you end up with
# a non-zero RC. This function simply checks that the VM exists before foricbly deleting it.
#
delete-incus-instance ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: delete-incus-instance $vm\n' >&2; return 1; }
    local vm=$1

    if incus info "$vm" >/dev/null 2>&1; then
        incus delete --force "$vm" 2>/dev/null || return
    fi
}


#-------------------------------------------------------------------------------
#
# delete-lxd-instance()
#
# Safely delete an LXD instance if it exists
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


#-------------------------------------------------------------------------------
#
# download-app()
#
# Download an app tarball from the S3 dist bucket
#
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


#-------------------------------------------------------------------------------
#
# download-daylight-batch()
#
# Download daylight.sh from a GitHub branch or release
#
download-daylight-batch ()
{
    # shellcheck disable=SC2016
    local branch="" release="" latest=0
    local -a pass=()
    local dstFolder=""
    local extract_flag="" extract_dir="" extract_name=""

    local args=("$@")
    local i=0
    while (( i < $# )); do
        case "${args[i]}" in
            --branch)
                if [[ -n "$release" ]]; then
                    printf 'Error: --branch and --release are incompatible\n' >&2
                    return 1
                fi
                if (( i+1 < $# )) && [[ "${args[i+1]}" != --* ]]; then
                    branch=${args[i+1]}
                    (( i++ ))
                else
                    branch=main
                fi
                ;;
            --release)
                if [[ -n "$branch" ]]; then
                    printf 'Error: --branch and --release are incompatible\n' >&2
                    return 1
                fi
                if (( i+1 < $# )) && [[ "${args[i+1]}" != --* ]]; then
                    release=${args[i+1]}
                    (( i++ ))
                else
                    release=latest
                fi
                ;;
            --latest)
                latest=1
                ;;
            --token)
                if (( i+1 < $# )); then
                    pass+=("${args[i]}" "${args[i+1]}")
                    (( i++ ))
                else
                    printf 'Error: --token requires a value\n' >&2
                    return 1
                fi
                ;;
            --output-dir)
                if (( i+1 < $# )); then
                    pass+=("${args[i]}" "${args[i+1]}")
                    (( i++ ))
                else
                    printf 'Error: --output-dir requires a value\n' >&2
                    return 1
                fi
                ;;
            --remote-name)
                pass+=("${args[i]}")
                ;;
            --extract)
                extract_flag=1
                ;;
            --extract-dir)
                if (( i+1 < $# )); then
                    extract_dir=${args[i+1]}
                    (( i++ ))
                else
                    printf 'Error: --extract-dir requires a value\n' >&2
                    return 1
                fi
                ;;
            --extract-name)
                if (( i+1 < $# )); then
                    extract_name=${args[i+1]}
                    (( i++ ))
                else
                    printf 'Error: --extract-name requires a value\n' >&2
                    return 1
                fi
                ;;
            --)
                (( i++ ))
                break
                ;;
            --*)
                printf 'Unknown flag: %s\n' "${args[i]}" >&2
                return 1
                ;;
            *)
                if [[ -z "$dstFolder" ]]; then
                    dstFolder=${args[i]}
                else
                    printf 'Unexpected argument: %s\n' "${args[i]}" >&2
                    return 1
                fi
                ;;
        esac
        (( i++ ))
    done

    while (( i < $# )); do
        if [[ -z "$dstFolder" ]]; then
            dstFolder=${args[i]}
        else
            pass+=("${args[i]}")
        fi
        (( i++ ))
    done

    [[ -n "$dstFolder" ]] || { printf 'Usage: download-daylight-batch [--branch [<name>]] [--release [<tag>]] [--latest] [--token <pat>] [--output-dir <dir>] [--remote-name] [--extract] [--extract-dir <dir>] [--extract-name <name>] [--] <dstFolder>\n' >&2; return 1; }
    [[ -d "$dstFolder" ]] || { printf 'Non-existent folder: %s\n' "$dstFolder" >&2; return 1; }

    if (( latest )) && [[ -z "$release" ]]; then
        printf 'Error: --latest requires --release\n' >&2
        return 1
    fi
    if [[ -z "$branch" && -z "$release" ]]; then
        branch=main
    fi

    [[ -z "$extract_dir" ]] && extract_dir=$dstFolder

    local org=daylight-public
    local repo=daylight

    if [[ -n "$release" ]]; then
        local tag json assetName tmpDir releasePath checksumFile
        local checksumName=SHA256SUMS

        if [[ "$release" == "latest" ]]; then
            tag=$(github-release-get-latest-tag "${pass[@]}" "$org" "$repo") || return
        else
            tag=$release
        fi

        tmpDir=$(create-temp-folder) || return

        json=$(github-release-get-data --version "$tag" "${pass[@]}" "$org" "$repo") || return
        assetName=$(printf '%s' "$json" | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .name' | head -1) || {
            printf 'No tar.gz asset found in release %s\n' "$tag" >&2
            rm -rf "$tmpDir"
            return 1
        }

        releasePath=$(github-release-download --version "$tag" "${pass[@]}" --extract-dir "$extract_dir" --extract-name "${extract_name:-daylight.sh}" --asset-name "$assetName" --output-dir "$tmpDir" "$org" "$repo") || {
            rm -rf "$tmpDir"
            return 1
        }

        checksumFile=$(github-release-download --version "$tag" "${pass[@]}" --asset-name "$checksumName" --output-dir "$tmpDir" "$org" "$repo") || {
            printf 'SHA256SUMS not found in release %s — cannot verify integrity\n' "$tag" >&2
            rm -rf "$tmpDir"
            return 1
        }

        if ! (cd "$tmpDir" && grep -F "$assetName" "$checksumName" | sha256sum -c -); then
            printf 'Checksum verification failed for %s\n' "$assetName" >&2
            rm -rf "$tmpDir"
            return 1
        fi

        # releasePath now points to the extracted file from github-release-download
        rm -rf "$tmpDir"
    else
        local url="https://raw.githubusercontent.com/$org/$repo/$branch/daylight.sh"
        local target="$extract_dir/${extract_name:-daylight.sh}"
        mkdir -p "$extract_dir"
        curl --location --silent --fail --output "$target" "$url" || return
    fi
}


#-------------------------------------------------------------------------------
#
# download-daylight()
#
# Download daylight.sh with optional interactive prompts
#
download-daylight ()
{
    local gen_completions=""
    local completions_path=""
    local -a pass_args=()
    local args=("$@")

    local i=0
    while (( i < $# )); do
        case "${args[i]}" in
            --gen-bash-completions)
                gen_completions=1
                if (( i+1 < $# )) && [[ "${args[i+1]}" != --* ]]; then
                    completions_path=${args[i+1]}
                    (( i++ ))
                fi
                ;;
            *)
                pass_args+=("${args[i]}")
                ;;
        esac
        (( i++ ))
    done

    download-daylight-batch "${pass_args[@]}" || return

    if [[ -z "$gen_completions" ]] && [[ -t 0 ]]; then
        printf 'Generate bash completions for daylight.sh? [y/N] '
        local reply
        read -r reply
        [[ "$reply" =~ ^[yY] ]] || return 0
    fi

    # Find dstFolder from pass_args (last positional arg)
    local dstFolder="${pass_args[${#pass_args[@]}-1]}"

    [[ -n "$dstFolder" ]] || { printf 'error: could not determine destination folder\n' >&2; return 1; }

    local scriptPath="$dstFolder/daylight.sh"
    [[ -f "$scriptPath" ]] || { printf 'error: %s not found after download\n' "$scriptPath" >&2; return 1; }

    local compPath="${completions_path:-$HOME/bash-completion.d/daylight.sh}"
    mkdir -p "$(dirname "$compPath")" || return

    bash "$scriptPath" gen-completion-script daylight.sh < <(bash "$scriptPath" list-bash-funcs < "$scriptPath") > "$compPath" || return
    printf 'Bash completions written to %s\n' "$compPath" >&2
}


#-------------------------------------------------------------------------------
#
# download-dist()
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


#-------------------------------------------------------------------------------
#
# detect-platform()
#
# Detect the OS and architecture as a platform string
#
detect-platform ()
{
    (( $# == 0 )) || { printf 'Usage: detect-platform\n' >&2; return 1; }
    local os arch

    case "$(uname -s)" in
        Linux)                     os="linux" ;;
        Darwin)                    os="darwin" ;;
        MINGW*|MSYS*|CYGWIN*)     os="windows" ;;
        *) printf 'Unsupported OS: %s\n' "$(uname -s)" >&2; return 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)             arch="amd64" ;;
        aarch64|arm64)            arch="arm64" ;;
        armv7l|armv6l)            arch="arm" ;;
        *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; return 1 ;;
    esac

    printf '%s-%s' "$os" "$arch"
}


#-------------------------------------------------------------------------------
#
# download-dylt()
#
# Download latest dylt release
#
download-dylt ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    local -a flags=()
    github-create-flags argmap flags token
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 1 )) || { printf 'Usage: download-dylt $dstFolder [$platform]\n' >&2; return 1; }
    local dstFolder=$1
    local platform=$2
    [[ -d "$dstFolder" ]] || { echo "Non-existent folder: $dstFolder" >&2; return 1; }

    if [[ -z "$platform" ]]; then
        platform=$(detect-platform) || return
    fi

    local -a flags=()
    [[ -n "${argmap[token]+exists}" ]] && flags+=(--token "${argmap[token]}") 

    local version; version=$(github-release-get-latest-tag "${flags[@]}" dylt-dev dylt) || return

    local releaseName="dylt_${platform}.tar.gz"
    local legacyName="dylt_$(dylt-legacy-platform "$platform").tar.gz"
    local url="https://github.com/dylt-dev/dylt/releases/download/$version/$releaseName"

    if curl --fail --location --head "$url" >/dev/null 2>&1; then
        github-release-download-latest "${flags[@]}" dylt-dev dylt "$releaseName" "$dstFolder" || return
    else
        github-release-download-latest "${flags[@]}" dylt-dev dylt "$legacyName" "$dstFolder" || return
    fi
}


#-------------------------------------------------------------------------------
#
# download-flask-app()
#
# Download a Flask app tarball from the S3 dist bucket
#
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


#-------------------------------------------------------------------------------
#
# download-flask-service()
#
# Download a Flask service tarball from S3
#
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


#-------------------------------------------------------------------------------
#
# download-public-key()
#
# Download a public key from S3 by name
#
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


#-------------------------------------------------------------------------------
#
# detect-runner-platform()
#
# Detect the runner OS and architecture as a platform string
#
detect-runner-platform ()
{
    (( $# == 0 )) || { printf 'Usage: detect-runner-platform\n' >&2; return 1; }
    local os arch

    case "$(uname -s)" in
        Linux)                     os="linux" ;;
        Darwin)                    os="osx" ;;
        MINGW*|MSYS*|CYGWIN*)     os="win" ;;
        *) printf 'Unsupported OS: %s\n' "$(uname -s)" >&2; return 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)             arch="x64" ;;
        aarch64|arm64)            arch="arm64" ;;
        armv7l|armv6l)            arch="arm" ;;
        *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; return 1 ;;
    esac

    printf '%s-%s' "$os" "$arch"
}


#-------------------------------------------------------------------------------
#
# shr-download-tarball()
#
# Download the tarball for the latest GitHub Actions Self-Hosted Runner release
#
shr-download-tarball ()
{
    (( $# >= 1 )) || { printf 'Usage: shr-download-tarball $targetFolder' >&2; return 1; }
    local downloadFolder=$1
    local urlLatestRelease="https://api.github.com/repos/actions/runner/releases/latest"
    local platform;  platform=$(detect-runner-platform) || return
    local fileExt="tar.gz"

    if [[ $platform == win-* ]]; then
        fileExt="zip"
    fi

    local namePattern="^actions-runner-$platform-.*\\.$fileExt\$"
    local tarballFileName tarballUrl
    local args
    read -r -a args < <(curl --silent "$urlLatestRelease" \
        | jq -r --arg pat "$namePattern" '.assets[]? | select(.name | test($pat)) | [.name, .browser_download_url] | @tsv') \
        || return

    if [[ ${#args[@]} -eq 0 ]]; then
        printf 'No runner asset found for platform: %s\n' "$platform" >&2
        return 1
    fi

    tarballFileName=${args[0]}
    tarballUrl=${args[1]}
    local tarballPath; tarballPath="$(create-temp-file "XXX.$tarballFileName")" || return
    curl --location --silent --output "$tarballPath" "$tarballUrl"

    if [[ "$fileExt" == "zip" ]]; then
        unzip -t "$tarballPath" >/dev/null || return
        unzip -o -d "$downloadFolder" "$tarballPath" >/dev/null || return
    else
        tar --list --gunzip --file "$tarballPath" >/dev/null
        tar --directory "$downloadFolder" --extract --gunzip --file "$tarballPath" || return
    fi

    printf '%s' "$downloadFolder" 
}


#-------------------------------------------------------------------------------
#
# download-svc()
#
# Download a service tarball from the S3 dist bucket
#
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


#-------------------------------------------------------------------------------
#
# download-to-temp-dir()
#
# Download and extract an S3 tarball to a temporary directory
#
download-to-temp-dir ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-to-temp-dir $s3Url\n' >&2; return 1; }
    local s3Url=$1

    local tempDir; tempDir=$(mktemp -d) || return
    aws s3 cp "$s3Url" - | tar -C "$tempDir" -xzf - >/dev/null || return

    printf '%s' "$tempDir"
}


#-------------------------------------------------------------------------------
#
# download-vm()
#
# Download a VM tarball from the S3 dist bucket
#
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


#-------------------------------------------------------------------------------
#
# dylt-legacy-platform()
#
# Translate current platform spec into a legacy platform spec
#
dylt-legacy-platform ()
{
    (( $# == 1 )) || { printf 'Usage: dylt-legacy-platform $canonical_platform\n' >&2; return 1; }
    local platform=$1
    case $platform in
        linux-amd64)  printf 'Linux_x86_64' ;;
        linux-arm64)  printf 'Linux_arm64'  ;;
        linux-386)    printf 'Linux_i386'   ;;
        linux-arm)    printf 'Linux_armv7l' ;;
        darwin-amd64) printf 'Darwin_x86_64' ;;
        darwin-arm64) printf 'Darwin_arm64'  ;;
        windows-amd64) printf 'Windows_x86_64' ;;
        windows-arm64) printf 'Windows_arm64'  ;;
        *)            printf '%s' "$platform" ;;
    esac
}


#-------------------------------------------------------------------------------
#
# ec ()
#
# Run etcdctl on a cluster specified by --discovery-srv
#
# @note This is hardcoded to hello.dylt.dev which isn't great.
# 
ec ()
{
    local discSrv='hello.dylt.dev'
    /opt/etcd/etcdctl --discovery-srv "$discSrv" "$@"
}


#-------------------------------------------------------------------------------
#
# edit-daylight()
#
# Edit daylight.sh in vim and optionally push changes
#
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


#-------------------------------------------------------------------------------
#
# emit-os-arch-vars()
#
# Print HOSTTYPE, MACHTYPE, and OSTYPE environment variables
#
emit-os-arch-vars ()
{
    emit-vars HOSTTYPE MACHTYPE OSTYPE
}


#-------------------------------------------------------------------------------
#
# emit-vars()
#
# Emit variable names and values as null-delimited output
#
emit-vars ()
{
    for varname in "$@"; do
        printf '%s\0%s\0' "$varname" "${!varname}"
    done
}


#-------------------------------------------------------------------------------
#
# etcd-create-download-url()
#
# Create a download URL for a specific version of etcd
#
etcd-create-download-url ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    
    # get arg values from flags, if present (if not fall back to defaults
    local version=${argmap[version]:-''}
    [[ -n "$version" ]] || version=$(github-release-get-latest-tag etcd-io etcd) || return
    local platform=${argmap[platform]:-''}
    if [[ -z "$platform" ]]; then
        platform=$(detect-platform) || platform='linux-amd64'
    fi
    local releaseName; releaseName=$(etcd-create-release-name "$version" "$platform")

    local -A info
    github-release-get-package-info info etcd-io etcd "$releaseName" || return
    local downloadUrl=${info[url]}
    printf '%s' "$downloadUrl"
}


#-------------------------------------------------------------------------------
#
# etcd-create-release-name()
#
# Create an etcd release name based on version and platform
#
etcd-create-release-name ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: etcd-create-release-name "$version" "$platform"\n' >&2; return 1; }
    local version=$1
    local platform=$2

    # .tar.gz for Linux; .zip for Windows and macOS (etcd publishes macOS as .zip)
    local releaseName
    if [[ $platform == windows-* || $platform == darwin-* ]]; then
        releaseName="etcd-$version-$platform.zip"
    else
        releaseName="etcd-$version-$platform.tar.gz"
    fi
    printf '%s' "$releaseName" || return
}


#-------------------------------------------------------------------------------
#
# etcd-download-latest()
#
# Download the latest etcd release
#
etcd-download-latest ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: etcd-download-latest $downloadFolder\n' >&2; return 1; }

    local version; version=$(etcd-get-latest-version) || return
    etcd-download --version "$version" "$@"
}


#-------------------------------------------------------------------------------
#
# etcd-download()
#
# Download a release of etcd from the specified URL
#
# @Note this function changes the name of the release file to 
# etcd-release.tar.gz. This guarantees a consistent file name,
# but losing the version might not be a good tradeoff.
etcd-download ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: etcd-download $downloadFolder\n' >&2; return 1; }
    local downloadFolder=$1

    local version=${argmap[version]:-''}
    [[ -n "$version" ]] || version=$(github-release-get-latest-tag etcd-io etcd) || return
    local platform=${argmap[platform]:-''}
    if [[ -z "$platform" ]]; then
        platform=$(detect-platform) || platform='linux-amd64'
    fi
    local releaseName; releaseName=$(etcd-create-release-name "$version" "$platform") || return
    local -a flags
    github-create-flags argmap flags token
    flags+=(--version "$version")
    github-release-download "${flags[@]}" --asset-name "$releaseName" --output-dir "$downloadFolder" etcd-io etcd
}


#-------------------------------------------------------------------------------
#
# etcd-gen-join-script()
#
# Generate an etcd script to join an existing cluster
#
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


#-------------------------------------------------------------------------------
#
# etcd-gen-run-script()
#
# Generate an etcd script to start a new cluster
#
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

#-------------------------------------------------------------------------------
#
# etcd-gen-unit-file()
#
# Generate a systemd unit file for etcd
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


#-------------------------------------------------------------------------------
#
# etcd-get-latest-version()
#
# Get the latest etcd release version tag
#
etcd-get-latest-version ()
{
	local tag; tag=$(github-release-get-latest-tag etcd-io etcd) || return
	if [[ -t 0 ]]; then
		printf '%s\n' "$tag"
	else
		printf '%s' "$tag"
	fi
}


#-------------------------------------------------------------------------------
#
# etcd-install-latest()
#
# Install the latest etcd release to a folder
#
etcd-install-latest ()
{
	# parse github args
	local -A argmap=()
	local nargs=0
	github-curl-parse-args argmap nargs "$@" || return
	shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: etcd-install-latest $installFolder\n' >&2; return 1; }
	[[ -d "$1" ]] || { echo "Non-existent folder: $1" >&2; return 1; }
    local installFolder=$1
    local org=etcd-io
    local repo=etcd
    local platform=${argmap[platform]:-''}
    if [[ -z "$platform" ]]; then
        platform=$(detect-platform) || platform='linux-amd64'
    fi

	local version; version=$(etcd-get-latest-version) || return
	local releaseName; releaseName=$(etcd-create-release-name "$version" "$platform") || return
	local -a flags=(--version "$version")
    github-release-install "${flags[@]}" "$org" "$repo" "$releaseName" "$installFolder" || return
    chown -R rayray:rayray "$installFolder" || return
}


#-------------------------------------------------------------------------------
#
# etcd-install-release()
#
# Extract an etcd release tarball to an install folder
#
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


#-------------------------------------------------------------------------------
#
# etcd-install-service()
#
# Install etcd as a systemd service
#
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


#-------------------------------------------------------------------------------
#
# etcd-setup-data-dir()
#
# Set up the etcd data directory with proper ownership
#
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


#-------------------------------------------------------------------------------
#
# gen-completion-script-batch()
#
# Generate a bash completion script from a list of subcommands on stdin.
# Outputs to stdout. No interactivity.
#
gen-completion-script-batch () {
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: gen-completion-script-batch <cmdName>\n' >&2; return 1; }
    if [[ -t 0 ]]; then
        printf 'error: stdin is a terminal; pipe subcommand list from a script or file.\n' >&2;
        return 1
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


#-------------------------------------------------------------------------------
#
# gen-completion-script()
#
# Generate a bash completion script for a given script. Three modes:
#   0 args  — auto-detect script, install to ~/bash-completion.d, source it
#   1-2 args — generate to stdout; if stdin is a terminal, the first arg is a
#              script file path (file-path mode); otherwise it is a name and
#              the function list comes from stdin (stdin-pipe mode).
#   Optional second arg: function name (default derived from script name).
#
gen-completion-script ()
{
    # shellcheck disable=SC2016
    (( $# >= 0 && $# <= 2 )) || { printf 'Usage: gen-completion-script [$scriptPath [$functionName]]\n' >&2
                                  printf '       gen-completion-script $scriptName [$functionName] < (...subcommands...)\n' >&2
                                  return 1; }
    if [[ -t 0 ]]; then
        printf '\nstdin is a terminal; please redirect input from stdin.\n\n';
        return 0
    fi

    if (( $# == 0 )); then
        local scriptPath=${BASH_SOURCE[0]:-'/opt/bin/daylight.sh'}
        local compScriptFolder=$HOME/bash-completion.d
        printf 'Creating %s (if necessary) ...\n' "$compScriptFolder"
        mkdir -p "$compScriptFolder/" || return
        local compScriptPath="$compScriptFolder/daylight.sh"
        printf 'Writing completion script for %s to %s ...\n' "$scriptPath" "$compScriptPath"
        gen-completion-script-batch "$(basename "$scriptPath")" < <(list-bash-funcs <"$scriptPath") \
            >"$compScriptPath" || return
        printf 'Sourcing %s ...\n' "$compScriptPath"
        # shellcheck disable=SC1090
        source "$compScriptPath" || return
        printf 'Done - bash completions for %s have been updated.\n' "$compScriptPath"
    elif [[ -t 0 ]]; then
        # File-path mode — extract functions from file
        local scriptPath=$1
        local scriptName; scriptName=$(basename "$scriptPath") || return
        local functionName
        if (( $# >= 2 )); then
            functionName=$2
        else
            functionName=_${scriptName//./-}
        fi
        gen-completion-script-batch "$scriptName" < <(list-bash-funcs <"$scriptPath") \
            | sed "s/^$functionName ()/$functionName ()/" || return
    else
        # Stdin-pipe mode — subcommand list comes from stdin
        local scriptName=$1
        local functionName
        if (( $# >= 2 )); then
            functionName=$2
        else
            functionName=_${scriptName//./-}
        fi
        gen-completion-script-batch "$scriptName" \
            | sed "s/^$functionName ()/$functionName ()/" || return
    fi
}


#-------------------------------------------------------------------------------
#
# gen-daylight-completion-script()
#
# Generate and install a bash completion script for daylight.sh
#
gen-daylight-completion-script () {
	# shellcheck disable=SC2016
	(( $# >= 0 && $# <= 1 )) || { printf 'Usage: gen-daylight-completion-script [$folder] []\n' >&2; return 1; }
	local folder=${1:-~/bash-completion.d}
	# shellcheck disable=SC2016
    if [[ ! -d "$folder" ]]; then
        printf 'Creating folder %s\n' "$folder" >&2;
        mkdir -p "$folder" || return
    fi

    local path="$folder/daylight.sh"
    local scriptPath='/opt/bin/daylight.sh'
    gen-completion-script "$(basename "$scriptPath")" < <(list-bash-funcs <"$scriptPath") >"$path" || return
}


#-------------------------------------------------------------------------------
#
# gen-nginx-flask()
#
# Generate an nginx config for a Flask app behind a Unix socket
#
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


#-------------------------------------------------------------------------------
#
# gen-nginx-static()
#
# Generate an nginx config for a static website
#
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


#-------------------------------------------------------------------------------
#
# generate-unit-file()
#
# Generate a systemd oneshot unit file
#
generate-unit-file ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: generate-unit-file $cmd $description [$args]\n' >&2; return 1; }
    local cmd=$1
    local description=$2
    shift 2;

    local -a args=("$@")
    local argsStr
    printf -v argsStr '%q ' "${args[@]}"

    cat <<EOD
[Unit]
Description=$description

[Service]
User=rayray
Type=oneshot
ExecStart=$cmd ${argsStr% }

[Install]
WantedBy=multi-user.target
EOD
}


#-------------------------------------------------------------------------------
#
# get-bucket()
#
# Get the S3 bucket name for this host
#
get-bucket ()
{
    local bucket; bucket=$(aws sts get-caller-identity --query 'Account' --output text) || return

    printf '%s' "$bucket"
}


#-------------------------------------------------------------------------------
#
# get-container-ip()
#
# Get the IP address of a container
#
get-container-ip ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-container-ip $container\n' >&2; return 1; }
    local container=$1

    incus query "/1.0/containers/$container/state" | jq -r '.network.eth0.addresses[] | select(.family=="inet").address'
}


#-------------------------------------------------------------------------------
#
# get-image-base()
#
# Get the base image name from a VM config folder
#
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


#-------------------------------------------------------------------------------
#
# get-image-name()
#
# Get the image name from a VM config folder
#
get-image-name ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-image-name $vmConfigFolder\n' >&2; return 1; }
    local srcFolder=$1

    local base; base=$(get-image-base "$srcFolder") || return
    local name="${base##*:}"
    printf '%s' "$name"
}


#-------------------------------------------------------------------------------
#
# get-image-repo()
#
# Get the image repository from a VM config folder
#
get-image-repo ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-image-repo $vmConfigFolder\n' >&2; return 1; }
    local srcFolder=$1

    local base; base=$(get-image-base "$srcFolder") || return
    local repo="${base%%:*}"
    printf '%s' "$repo"
}


#-------------------------------------------------------------------------------
#
# get-linux-version-codename()
#
# Get the Debian/Ubuntu version codename
#
get-linux-version-codename ()
{
    # shellcheck disable=SC2016
    (( $# == 0 )) || { printf 'Usage: get-linux-version-codename\n' >&2; return 1; }
    # shellcheck disable=SC2016
    [[ -f "/etc/os-release" ]] || { printf 'Non-existent path: /etc/os-release\n' >&2; return 1; }
    local versionCodeName=''
    local rx='VERSION_CODENAME=(.*)'
    while read -r line; do
        if [[ "$line" =~ $rx ]]; then
            versionCodeName=${BASH_REMATCH[1]}
        fi
    done </etc/os-release
    # shellcheck disable=SC2016
    [[ -n "$versionCodeName" ]] || { printf 'Variable is unset or empty: $versionCodeName\n' >&2; return 1; }
    # printf with \n if interactive
    printf '%s' "$versionCodeName"
    [[ -t 0 ]] && printf '\n'
}


#-------------------------------------------------------------------------------
#
# get-service-file-value()
#
# Parse a value from a systemd service file
#
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


#-------------------------------------------------------------------------------
#
# get-service-environment-file()
#
# Get the EnvironmentFile path from a systemd service
#
get-service-environment-file ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-service-environment-file $serviceName\n' >&2; return 1; }
    local name=$1

    get-service-file-value "$name" 'EnvironmentFile'
}


#-------------------------------------------------------------------------------
#
# get-service-exec-start()
#
# Get the ExecStart command from a systemd service
#
get-service-exec-start ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-service-exec-start $serviceName\n' >&2; return 1; }
    local name=$1

    get-service-file-value "$name" 'ExecStart'
}


#-------------------------------------------------------------------------------
#
# get-service-working-directory()
#
# Get the WorkingDirectory from a systemd service
#
get-service-working-directory ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-service-working-directory $serviceName\n' >&2; return 1; }
    local name=$1

    get-service-file-value "$name" 'WorkingDirectory'
}


#-------------------------------------------------------------------------------
#
# getVmName()
#
# Get the Incus VM name for an application
#
getVmName ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: getVmName infovar $user\n' >&2; return 1; }
    local -n _appInfo=$1
    local user=$2

    printf '%s' "$user"
}


#-------------------------------------------------------------------------------
#
# github-app-get-client-id()
#
# Get the OAuth client ID for a GitHub App
#
github-app-get-client-id ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-app-get-data()
#
# Get GitHub App installation data from the API
#
github-app-get-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: github-app-get-data $appSlug\n' >&2; return 1; }
    local appSlug=$1

    local -a flags=()
    [[ -v argmap[token] ]] && flags+=(--token "${argmap[token]}")
    github-curl "${flags[@]}" "/apps/$appSlug" || return
}


#-------------------------------------------------------------------------------
#
# github-app-get-id()
#
# Get the ID of a GitHub App
#
github-app-get-id ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-app-get-info()
#
# Get detailed info about a GitHub App
#
github-app-get-info ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-create-flags()
#
# Create curl flags from a parsed argument map
#
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


#-------------------------------------------------------------------------------
#
# github-create-url()
#
# Create a full GitHub API URL from a path
#
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


#-------------------------------------------------------------------------------
#
# github-create-uat()
#
# Create a GitHub user access token via API
#
github-create-uat ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-create-uat tokenvar $appslug\n' >&2; return 1; }
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


#-------------------------------------------------------------------------------
#
# github-curl()
#
# Make an authenticated request to the GitHub API
#
github-curl ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@"
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
    # Append per_page parameter if requested
    if [[ -v argmap[per-page] ]]; then
        local pageSize=${argmap[per-page]}
        if [[ $url == *\?* ]]; then url+="&per_page=$pageSize"
        else url+="?per_page=$pageSize"
        fi
    fi
    # Can't really parameterize on token -- we need separate curl calls for with token, and without
    local -a flags=(--fail-with-body --location --silent)
    flags+=(--header "Accept: $accept")
    if [[ -v argmap[remote-name] ]] && ! [[ -v argmap[output] ]]; then
        flags+=(--remote-name)
    else
        flags+=(--output "$output")
    fi
    [[ -v argmap[output-dir] ]] && flags+=(--output-dir "${argmap[output-dir]}")
    [[ -v argmap[data] ]] && flags+=(--data "${argmap[data]}")
    local tokenVal
    if [[ -v argmap[token] ]]; then
        tokenVal=${argmap[token]}
    elif [[ -n "${GITHUB_TOKEN-}" ]]; then
        tokenVal=$GITHUB_TOKEN
    elif [[ -n "${GH_TOKEN-}" ]]; then
        tokenVal=$GH_TOKEN
    elif type gh &>/dev/null; then
        tokenVal=$(gh auth token 2>/dev/null) || tokenVal=''
    fi
    [[ -n "$tokenVal" ]] && flags+=(--header "Authorization: Bearer $tokenVal")
    curl "${flags[@]}" "$url" \
        || { printf 'curl failed inside github-curl\n' >&2; return 1; }
}


#-------------------------------------------------------------------------------
#
# github-curl-post()
#
# @deprecated
# Use github-curl with --data 'your-data'
#
github-curl-post ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@"
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


#-------------------------------------------------------------------------------
#
# github-detect-platform()
#
# Detect the OS and architecture as a platform string
#
github-detect-platform ()
{
    (( $# == 0 )) || { printf 'Usage: github-detect-platform\n' >&2; return 1; }
    local os arch

    case "$(uname -s)" in
        Linux)                     os="linux" ;;
        Darwin)                    os="darwin" ;;
        MINGW*|MSYS*|CYGWIN*)     os="windows" ;;
        *) printf 'Unsupported OS: %s\n' "$(uname -s)" >&2; return 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)             arch="amd64" ;;
        aarch64|arm64)            arch="arm64" ;;
        armv7l|armv6l)            arch="arm" ;;
        *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; return 1 ;;
    esac

    printf '%s-%s' "$os" "$arch"
}


#-------------------------------------------------------------------------------
#
# github-download-latest-release()
#
# Download the latest release asset from a GitHub repository
#
github-download-latest-release ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@"
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


#-------------------------------------------------------------------------------
#
# github-get-release-data()
#
# @deprecated
# Use github-release-get-data
#
github-get-release-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@"
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


#-------------------------------------------------------------------------------
#
# github-get-release-name-list()
#
# @deprecated
# Use github-release-get-name-list
#
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


#-------------------------------------------------------------------------------
#
# github-get-release-package-data()
#
# @deprecated
# Use github-release-get-package-data
#
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


#-------------------------------------------------------------------------------
#
# github-get-release-package-info()
#
# @deprecated
# Use github-release-get-package-info
#
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


#-------------------------------------------------------------------------------
#
# github-shr-load-uat
#
# Read the saved user access token from its path
#
github-shr-load-uat ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-load-uat $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2

    local uatPath; uatPath=$(github-shr-uat-path "$org" "$repo") || return
    [[ -f "$uatPath" ]] || { printf 'User Access Token not found (%s)\n' "$uatPath"; return 1; }
    local uat; uat=$(< "$uatPath") || return
    [[ -n "$uat" ]] || { printf 'UAT file is empty (%s)\n' "$uatPath" >&2; return 1; }
    printf '%s' "$uat"
}


#-------------------------------------------------------------------------------
#
# github-shr-uat-path
#
# Get the path for the uat for this org + repo
#
github-shr-uat-path ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-uat-path $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2

    local shrFolder; shrFolder=$(github-shr-folder-name "$org" "$repo") || return
    local uatPath=$(printf '%s/.uat' "$shrFolder")
    printf '%s' "$uatPath"
}


#-------------------------------------------------------------------------------
#
# github-shr-swap-tokens()
#
# Redeem a GitHub access token for a self-hosted runner registration token
#
github-shr-swap-tokens ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-swap-tokens $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2

    local shrFolder; shrFolder=$(github-shr-folder-name "$org" "$repo") || return
    local uat; uat=$(github-shr-load-uat "$org" "$repo") || return

    local apiUrl="https://api.github.com/repos/$org/$repo/actions/runners/registration-token"
    local tmpCurl; tmpCurl=$(create-temp-file curl.get.shr.token.json) || return
    curl --fail-with-body --location --silent --request POST \
        --header "Authorization: Bearer $uat" \
        --header "Accept: application/json" \
        --output "$tmpCurl" \
        "$apiUrl" || {
        local httpCode
        httpCode=$(jq -r '.status // "unknown"' <"$tmpCurl")
        local msg
        msg=$(jq -r '.message // "unknown"' <"$tmpCurl")
        printf 'github-shr-swap-tokens: %s — %s\n' "$httpCode" "$msg" >&2
        if [[ "$httpCode" == "403" ]]; then
            printf 'The GitHub App may not be installed on %s/%s.\n' "$org" "$repo" >&2
            printf 'Run: github-is-gha-installed %s <app-slug>\n' "$org" >&2
            printf 'Install at: https://github.com/apps/<app-slug>/installations/new\n' >&2
        fi
        return 1
    }
    local shrToken
    shrToken=$(jq -r '.token' <"$tmpCurl")
    if [[ -z "$shrToken" || "$shrToken" == "null" ]]; then
        printf 'github-shr-swap-tokens: response did not contain a token\n' >&2
        jq . <"$tmpCurl" >&2
        return 1
    fi
    printf '%s' "$shrToken"
}


#-------------------------------------------------------------------------------
#
# github-is-gha-installed()
#
# Check whether a GitHub App is installed on an org (or user account).
# Prints Yes (exit 0) or No (exit 1).
#
github-is-gha-installed ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-is-gha-installed $org $appSlug $uatPath\n' >&2; return 1; }
    local org=$1 appSlug=$2 uatPath=$3

    [[ -f "$uatPath" ]] || { printf 'github-is-gha-installed: UAT file not found: %s\n' "$uatPath" >&2; return 1; }
    local uat; uat=$(< "$uatPath")
    [[ -n "$uat" ]] || { printf 'github-is-gha-installed: UAT file is empty: %s\n' "$uatPath" >&2; return 1; }

    local tmpCurl; tmpCurl=$(create-temp-file curl.is.gha.installed.json) || return

    curl --fail-with-body --location --silent \
        --header "Authorization: Bearer $uat" \
        --header "Accept: application/vnd.github+json" \
        --output "$tmpCurl" \
        "https://api.github.com/user/installations" || {
        printf 'github-is-gha-installed: failed to list installations\n' >&2
        return 1
    }

    local found
    found=$(jq -r --arg slug "$appSlug" --arg org "$org" \
        '.installations[] | select(.app_slug == $slug and ($org == "" or .account.login == $org)) | .id' <"$tmpCurl")

    if [[ -z "$found" ]]; then
        return 1
    fi

    return 0
}


#-------------------------------------------------------------------------------
#
# github-curl-parse-args()
#
# Parse common GitHub API arguments into an associative array
#
github-curl-parse-args ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-curl-parse-args infovar nargs [$args]\n' >&2; return 1; }
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
            '--accept'     |\
            '--data'       |\
            '--output'     |\
            '--output-dir' |\
            '--per-page'   |\
            '--token'      |\
            '--label'      |\
            '--platform'   |\
            '--version'    |\
            '--workflow'   \
            )
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                argmap["${1##--}"]=$2
                ((nargs+=2))
                shift 2
                ;;
            '--remote-name')
                argmap[remote-name]=1
                ((nargs++))
                shift
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


#-------------------------------------------------------------------------------
#
# github-release-create-url-path()
#
# Create a URL path for a GitHub release
#
github-release-create-url-path ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-release-download()
#
# Download a release asset from a GitHub repository
#
# Flags (function-native, not handled by github-curl-parse-args):
#   --asset-name <name>  Asset name to download. If omitted, auto-detect
#                        (first .tar.gz, then .zip, then first asset)
#   --extract            Extract the downloaded archive
#   --extract-dir <dir>  Extraction target directory (default: download folder)
#   --extract-name <name>
#   --verify             Verify download against a checksum file (auto-detected)
#                        Rename the extracted content
#
# Positional args:
#   $org    GitHub organization or user
#   $repo   Repository name
#
# github-curl-parse-args flags also accepted:
#   --token, --version, --output, --output-dir, --remote-name
#
github-release-download ()
{
    # Pre-parse extract, verify, and asset-name flags (not handled by github-curl-parse-args)
    local extract_flag=""
    local extract_dir=""
    local extract_dir_set=""
    local extract_name=""
    local asset_name_flag=""
    local verify_flag=""
    local -a rest=()
    while (( $# > 0 )); do
        case $1 in
            --extract)
                extract_flag=1
                shift
                ;;
            --extract-dir)
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                extract_dir=$2
                extract_dir_set=1
                shift 2
                ;;
            --extract-name)
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                extract_name=$2
                shift 2
                ;;
            --asset-name)
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                asset_name_flag=$2
                shift 2
                ;;
            --verify)
                verify_flag=1
                shift
                ;;
            *)
                rest+=("$1")
                shift
                ;;
        esac
    done
    set -- "${rest[@]}"

    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-release-download [flags] $org $repo [$name] [$downloadFolder]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=""
    local downloadFolder=""

    # Determine name: --asset-name flag > positional $3 > auto-detect
    if [[ -n "$asset_name_flag" ]]; then
        name=$asset_name_flag
    elif (( $# >= 3 )) && [[ -n "$3" ]]; then
        name=$3
    fi

    # Determine download folder: --output-dir flag > positional $4 > temp dir
    if [[ -n "${argmap[output-dir]:-}" ]]; then
        downloadFolder=${argmap[output-dir]%%/}
    elif (( $# >= 4 )) && [[ -n "$4" ]]; then
        downloadFolder=${4%%/}
    else
        downloadFolder=$(create-temp-folder "${repo}.release") || return
    fi

    # Auto-detect name if not provided
    if [[ -z "$name" ]]; then
        local -a detect_flags=()
        [[ -v argmap[token] ]] && detect_flags+=(--token "${argmap[token]}")
        [[ -v argmap[version] ]] && detect_flags+=(--version "${argmap[version]}")
        name=$(github-release-get-asset-name "${detect_flags[@]}" "$org" "$repo") || return
    fi

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

    if [[ -n "$verify_flag" ]]; then
        github-release-verify-checksum "${flags[@]}" "$org" "$repo" "$name" "$downloadFolder" || return
    fi

    if [[ -n "$extract_flag" || -n "$extract_dir_set" || -n "$extract_name" ]]; then
        [[ -z "$extract_dir" ]] && extract_dir=$downloadFolder
        [[ -f "$output" ]] || { printf 'Archive not found: %s\n' "$output" >&2; return 1; }
        local extractTmp; extractTmp=$(mktemp -d) || return
        case "$filename" in
            *.tar.gz|*.tgz)
                tar -xzf "$output" -C "$extractTmp" || { rm -rf "$extractTmp"; return 1; }
                ;;
            *.zip)
                unzip -o "$output" -d "$extractTmp" || { rm -rf "$extractTmp"; return 1; }
                ;;
            *)
                printf 'Cannot extract: unknown format %s\n' "$filename" >&2
                rm -rf "$extractTmp"
                return 1
                ;;
        esac
        local -a extractedEntries
        extractedEntries=($(find "$extractTmp" -mindepth 1 -maxdepth 1))
        if (( ${#extractedEntries[@]} == 1 )); then
            local targetPath="${extract_dir}/${extract_name:-$(basename "${extractedEntries[0]}")}"
            mkdir -p "$extract_dir"
            mv "${extractedEntries[0]}" "$targetPath" || { rm -rf "$extractTmp"; return 1; }
            printf '%s' "$targetPath"
        elif (( ${#extractedEntries[@]} > 1 )); then
            mkdir -p "$extract_dir"
            local subdir="${extract_dir}/${extract_name:-extracted}"
            mkdir -p "$subdir"
            mv "$extractTmp"/* "$subdir"/ || { rm -rf "$extractTmp"; return 1; }
            rmdir "$extractTmp" 2>/dev/null || true
            printf '%s' "$subdir"
        else
            printf 'Nothing found inside archive\n' >&2
            rm -rf "$extractTmp"
            return 1
        fi
        rm -rf "$extractTmp"
    else
        printf '%s' "$output"
    fi
}


#-------------------------------------------------------------------------------
#
# github-release-download-latest()
#
# Download the latest release asset for a named package
#
# Flags (function-native, not handled by github-curl-parse-args):
#   --asset-name <name>  Asset name to download. If omitted, auto-detect
#                        (first .tar.gz, then .zip, then first asset)
#   --extract            Extract the downloaded archive
#   --extract-dir <dir>  Extraction target directory (default: download folder)
#   --extract-name <name>
#                        Rename the extracted content
#   --verify             Verify download against a checksum file (auto-detected)
#
# Positional args:
#   $org    GitHub organization or user
#   $repo   Repository name
#
# github-curl-parse-args flags also accepted:
#   --token, --version, --output, --output-dir, --remote-name
#
github-release-download-latest ()
{
    # Pre-parse extract, verify, and asset-name flags (not handled by github-curl-parse-args)
    local extract_flag=""
    local extract_dir=""
    local extract_name=""
    local asset_name_flag=""
    local verify_flag=""
    local -a rest=()
    while (( $# > 0 )); do
        case $1 in
            --extract)
                extract_flag=1
                shift
                ;;
            --extract-dir)
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                extract_dir=$2
                shift 2
                ;;
            --extract-name)
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                extract_name=$2
                shift 2
                ;;
            --asset-name)
                (( $# >= 2 )) || { printf -- '%s specified but no value provided.\n' "$1" >&2; return 1; }
                asset_name_flag=$2
                shift 2
                ;;
            --verify)
                verify_flag=1
                shift
                ;;
            *)
                rest+=("$1")
                shift
                ;;
        esac
    done
    set -- "${rest[@]}"

    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-release-download-latest [flags] $org $repo [$name] [$downloadFolder]\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local name=""
    local downloadFolder=""

    if [[ -n "$asset_name_flag" ]]; then
        name=$asset_name_flag
    elif (( $# >= 3 )) && [[ -n "$3" ]]; then
        name=$3
    fi

    if [[ -n "${argmap[output-dir]:-}" ]]; then
        downloadFolder=${argmap[output-dir]%%/}
    elif (( $# >= 4 )) && [[ -n "$4" ]]; then
        downloadFolder=${4%%/}
    fi

    local -a flags
    github-create-flags argmap flags token || return
    local version; version=$(github-release-get-latest-tag "${flags[@]}" "$org" "$repo") || return
    flags+=(--version "$version")
    local -a dl_flags=()
    [[ -n "$name" ]] && dl_flags+=(--asset-name "$name")
    [[ -n "$downloadFolder" ]] && dl_flags+=(--output-dir "$downloadFolder")
    [[ -n "$extract_flag" ]] && dl_flags+=(--extract)
    [[ -n "$extract_dir" ]] && dl_flags+=(--extract-dir "$extract_dir")
    [[ -n "$extract_name" ]] && dl_flags+=(--extract-name "$extract_name")
    [[ -n "$verify_flag" ]] && dl_flags+=(--verify)
    github-release-download "${flags[@]}" "${dl_flags[@]}" "$org" "$repo" || return
}


#-------------------------------------------------------------------------------
#
# github-release-get-data()
#
# Get release data from a GitHub repository
#
github-release-get-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@"
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


#-------------------------------------------------------------------------------
#
# github-release-get-asset-name()
#
# Determine the best asset name from a GitHub release by priority:
#   1. .tar.gz  2. .zip  3. first asset in the array
#
# Usage: github-release-get-asset-name [flags] $org $repo
# Output: prints the best asset name, exits 1 if no assets found
#
github-release-get-asset-name ()
{
    command -v "jq" >/dev/null || { printf '%s is required, but was not found.\n' "jq" >&2; return 1; }
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-release-get-asset-name [flags] $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2

    local -a flags
    github-create-flags argmap flags version token || return
    local assetName
    assetName=$(github-release-get-data "${flags[@]}" "$org" "$repo" \
        | jq -r '
            [.assets[]
             | select(.name | test("\\.tar\\.gz$"))
             | .name][0]
            // ([.assets[]
               | select(.name | test("\\.zip$"))
               | .name][0])
            // ([.assets[].name][0])
            // empty' ) || return
    if [[ -z "$assetName" ]]; then
        printf 'No assets found for %s/%s\n' "$org" "$repo" >&2
        return 1
    fi
    printf '%s' "$assetName"
}


#-------------------------------------------------------------------------------
#
# github-release-get-latest-tag()
#
# Get the latest release tag from a GitHub repo
#
github-release-get-latest-tag ()
{
    command -v "jq" >/dev/null || { printf '%s is required, but was not found.\n' "jq" >&2; return 1; }
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-release-get-latest-tag [flags] $org $repo\n' >&2; return 1; }
    local org=$1
    local repo=$2
    
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


#-------------------------------------------------------------------------------
#
# github-release-get-package-data()
#
# Get raw asset data for a named release package
#
github-release-get-package-data ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-release-get-package-info()
#
# Get structured package info for a named release asset
#
github-release-get-package-info ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-release-install()
#
# Download and install a GitHub release asset
#
github-release-install ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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
    local releasePath; releasePath=$(github-release-download "${flags[@]}" --asset-name "$name" --output-dir "$downloadFolder" "$org" "$repo") || return
    case "$releasePath" in
        *.tgz|*.tar.gz)
            tar --strip-components=1 -C "$installFolder" -xzf "$releasePath";;
        *)
            printf "Unsupported file type - can't install (%s)\n" "$releasePath" >&2
            return 1;;
    esac
	printf '%s' "$installFolder"
}


#-------------------------------------------------------------------------------
#
# github-release-install-latest()
#
# Install the latest release from a GitHub repo
#
# @note - github-release-install will install the latest by default, if you don't specify a version
#
github-release-install-latest ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-release-list()
#
# List releases for a GitHub repository
#
github-release-list ()
{
	# parse github args
	local -A argmap=()
	local nargs=0
	github-curl-parse-args argmap nargs "$@"
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


#-------------------------------------------------------------------------------
#
# github-release-list-platforms()
#
# List available platforms for a release
#
github-release-list-platforms ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
	# shellcheck disable=SC2016
	(( $# = 2 )) || { printf 'Usage: github-release-list [flags] $org $repo\n' >&2; return 1; }
	local org=$1
	local repo=$2

	# get release name list, using token if provided
    readarray -t -d $'\t' releases < <(github-release-list "$@")
    local platform
    for release in "${releases[@]}"; do
        if [[ ! "$release" =~ checksums.txt ]]; then
            platform="${release##"${repo}"_}"
            platform="${platform%%.*}"
        	printf '%s\n' "$platform"
        fi
    done
}


#-------------------------------------------------------------------------------
#
# github-release-select()
#
# Select a release from a list of choices
#
github-release-select ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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


#-------------------------------------------------------------------------------
#
# github-release-select-platform()
#
# Select a platform for a release download
#
github-release-select-platform ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
	# shellcheck disable=SC2016
	(( $# = 2 )) || { printf 'Usage: github-release-select-platforms [flags] $org $repo' >&2; return 1; }
    local platforms
    readarray -t -d $'\n' platforms < <(github-release-list-platforms "$@")
	select platform in "${platforms[@]}"; do
        printf '%s' "$platform" || return
        break
    done
}


#-------------------------------------------------------------------------------
#
# github-release-verify-checksum()
#
# Verify a downloaded release asset against a checksum file from the same
# release. Auto-detects the checksum file by trying these names in order:
#   SHA256SUMS > SHA256SUMS.txt > $assetName.sha256 > checksums.txt
#
# The checksum file is downloaded alongside the asset and left in place
# after verification (pass or fail).
#
github-release-verify-checksum ()
{
    command -v "jq" >/dev/null || { printf '%s is required, but was not found.\n' "jq" >&2; return 1; }
    command -v "sha256sum" >/dev/null || { printf '%s is required, but was not found.\n' "sha256sum" >&2; return 1; }
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: github-release-verify-checksum [flags] $org $repo $assetName $downloadFolder\n' >&2; return 1; }
    local org=$1
    local repo=$2
    local assetName=$3
    local downloadFolder=$4

    local -a flags
    github-create-flags argmap flags token version || return

    # Fetch release data
    local releaseJson
    releaseJson=$(github-release-get-data "${flags[@]}" "$org" "$repo") || return

    # Candidate checksum names, in priority order
    local -a candidates=("SHA256SUMS" "SHA256SUMS.txt" "${assetName}.sha256" "checksums.txt")

    # Get list of available asset names
    local available
    available=$(printf '%s' "$releaseJson" | jq -r '.assets[].name') || return

    # Find first candidate that exists in the release
    local checksumName=""
    local candidate
    for candidate in "${candidates[@]}"; do
        if printf '%s' "$available" | grep -qFx "$candidate"; then
            checksumName=$candidate
            break
        fi
    done

    if [[ -z "$checksumName" ]]; then
        printf 'Warning: no checksum file found in %s/%s release (tried: %s)\n' \
            "$org" "$repo" "${candidates[*]}" >&2
        return 0
    fi

    # Extract API URL for the checksum asset
    local csApiUrl
    csApiUrl=$(printf '%s' "$releaseJson" | jq -r --arg name "$checksumName" '
        .assets[] | select(.name == $name) | .url' | head -1
    ) || return
    local csUrlPath="${csApiUrl#https://api.github.com/}"
    local csFile="$downloadFolder/$checksumName"

    # Download checksum file (reuse flags array: $2 must be "flags" literal)
    flags=()
    github-create-flags argmap flags token || return
    flags+=(--accept "application/octet-stream" --output "$csFile")
    github-curl "${flags[@]}" "$csUrlPath" || return

    # Verify
    if ! (cd "$downloadFolder" && grep -F "$assetName" "$checksumName" | sha256sum -c -); then
        printf 'Checksum verification failed for %s (checksum file: %s)\n' \
            "$assetName" "$checksumName" >&2
        return 1
    fi

    printf 'Checksum verified for %s (%s)\n' "$assetName" "$checksumName" >&2
    return 0
}


#-------------------------------------------------------------------------------
#
# github-shr-create-folder
#
# Create parent folder for an shr installation
github-shr-create-folder ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-create-folder $org $repo' >&2; return 1; }
    local org=$1 repo=$2

    folder=$(github-shr-folder-name "$org" "$repo")
    mkdir -p "$folder" || return
    printf '%s' "$folder"
}


#-------------------------------------------------------------------------------
#
# github-shr-folder-name
#
# Parent folder name for an shr installation
github-shr-folder-name ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-folder-name $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2

    printf "/opt/actions-runner/shr-%s-%s" "$org" "$repo"
}


#-------------------------------------------------------------------------------
#
# github-shr-install()
#
# Everything required after SHR setup. 
#
github-shr-install ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-shr-install $org $repo' >&2; return 1; }
    local org=$1 repo=$2
    
    printf '%sStarting runner service and running verification...%s\n' "$SHR_GRAY" "$SHR_RESET"
    github-shr-start "$org" "$repo"
}


#-------------------------------------------------------------------------------
#
# github-shr-install-runner()
#
# Register a self-hosted runner via a GitHub App UAT.
# Downloads the runner, exchanges the UAT for a registration token,
# and configures the runner. Does NOT start svc.
# Prints the runner folder path on success.
#
github-shr-install-runner ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-shr-install-runner $org $repo' >&2; return 1; }
    local org=$1 repo=$2

    local labels="linux"
    local svcName="shr-$org-$repo"
    local shrHome="/opt/actions-runner"
    local shrFolder; shrFolder="$(github-shr-folder-name "$org" "$repo")" || return
    printf '%sDownloading runner tarball...%s\n' "$SHR_GRAY" "$SHR_RESET"
    shr-download-tarball "$shrFolder"
    cd "$shrFolder" || return
    chown -R rayray:rayray "$shrHome"
    local repoUrl="https://github.com/$org/$repo"
    local shrToken
    printf '%sExchanging credential for registration token...%s\n' "$SHR_GRAY" "$SHR_RESET"
    shrToken=$(github-shr-swap-tokens "$org" "$repo") || return
    if [[ -f ./svc.sh ]] && ./svc.sh status >/dev/null; then
        printf '%sRemoving previous runner registration...%s\n' "$SHR_GRAY" "$SHR_RESET"
        ./svc.sh uninstall
        ./config.sh remove --token "$shrToken"
    fi
    printf '%sRegistering runner...%s\n' "$SHR_GRAY" "$SHR_RESET"
    ./config.sh --unattended \
          --url "$repoUrl" \
          --token "$shrToken" \
          --replace \
          --name ubuntu-dev \
          --labels "$labels" \
	  || return
    printf '%s' "$shrFolder"
}


#-------------------------------------------------------------------------------
#
# github-shr-setup()
#
# End-to-end runner install: device-code auth, tarball download, registration,
# systemd service install + start, and verification. Must be run as root.
#
github-shr-setup ()
{
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: github-shr-setup $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2
    
    local appSlug="shrboy"
    local shrHome="/opt/actions-runner"

    local USER_ACCESS_TOKEN
    github-create-uat USER_ACCESS_TOKEN "$appSlug" || return
    github-shr-save-uat "$org" "$repo" "$USER_ACCESS_TOKEN" || return

    printf '%sDownloading and registering runner...%s\n' "$SHR_GRAY" "$SHR_RESET"
    github-shr-install-runner "$org" "$repo" || return
}


#-------------------------------------------------------------------------------
#
# github-shr-save-uat()
#
# Save a user access token to the appropriate path for $org and $repo
#
github-shr-save-uat ()
{
   (( $# == 3 )) || { printf 'Usage: github-shr-save-uat $org $repo $uat'; return 1; }
   local org=$1 repo=$2 uat=$3

   local shrFolder; shrFolder=$(github-shr-folder-name "$org" "$repo")
   printf '%sSaving credential...%s\n' "$SHR_GRAY" "$SHR_RESET"
   mkdir -p "$shrFolder" || { printf 'Unable to create folder (%s)\n' "$shrFolder"; return 1; }
   local uatPath; uatPath=$(github-shr-uat-path "$org" "$repo") || return
   printf '%s' "$uat" >"$uatPath"
   chmod 600 "$uatPath" || return
}


#-------------------------------------------------------------------------------
#
# github-shr-start()
#
# Install and start a self-hosted runner's systemd service, then run a
# verification workflow. Derives the runner folder from $org-$repo.
# Requires sudo.
#
github-shr-start ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-start $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2
    [[ $EUID -eq 0 ]] || { printf 'github-shr-start: must be run as root (try sudo)\n' >&2; return 1; }
    
    local svcName="shr-$org-$repo"
    local shrFolder; shrFolder=$(github-shr-folder-name "$org" "$repo")
    [[ -d "$shrFolder" ]] || { printf 'github-shr-start: runner not found: %s/%s (%s)\n' "$org" "$repo" "$shrFolder" >&2; return 1; }

    cd "$shrFolder" || return
    # confirm ./svc.sh exists
    [[ -f "$shrFolder/svc.sh" ]] || { printf './svc.sh does not exist'; return 1; }
    printf '%sInstalling systemd service...%s\n' "$SHR_GRAY" "$SHR_RESET"
    ./svc.sh install 2>/dev/null || true
    printf '%sStarting runner service...%s\n' "$SHR_GRAY" "$SHR_RESET"
    ./svc.sh start || return

    printf '%sRunning verification workflow...%s\n' "$SHR_GRAY" "$SHR_RESET"
    if github-shr-test "$org" "$repo"; then
        printf '%s%s%s Runner is online and verified for %s/%s\n' "$SHR_GREEN" "$SHR_CHECK" "$SHR_RESET" "$org" "$repo"
    else
        printf 'Warning: runner started but verification workflow failed\n' >&2
    fi
}


#-------------------------------------------------------------------------------
#
# github-shr-test()
#
# Test a self-hosted runner by creating/triggering a test workflow.
# Uses the REST API with the UAT to create the workflow file, trigger it,
# and tail the runner log.
#
github-shr-test ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-test $org $repo' >&2; return 1; }
    local org=$1 repo=$2

    local svcName="shr-$org-$repo"
    local shrFolder; shrFolder=$(github-shr-folder-name "$org" "$repo")
    local uat; uat=$(github-shr-load-uat "$org" "$repo") || return

    local workflowPath=".github/workflows/test-shr.yml"
    local workflowName="test-shr"

    # Check if workflow exists via GitHub API
    local exists
    exists=$(curl --silent --request GET \
        --header "Authorization: Bearer $uat" \
        --header "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$org/$repo/contents/$workflowPath" \
        --write-out '%{http_code}' --output /dev/null)

    if [[ "$exists" != "200" ]]; then
        printf 'Workflow %s does not exist in %s/%s.\n' "$workflowPath" "$org" "$repo" >&2
        printf 'Create it? (Y/n): ' >&2
        local response; read -r response
        if [[ "$response" =~ ^[Yy]?$ ]]; then
            local workflowContent
            workflowContent=$(printf 'name: test-shr\non: workflow_dispatch\njobs:\n  test:\n    runs-on: [self-hosted, linux]\n    steps:\n      - run: echo "Testing SHR: ${{ github.repository }}"\n')
            local encoded
            encoded=$(printf '%s' "$workflowContent" | base64 -w0)
            local commitMsg="Add test-shr workflow for SHR verification"
            local payload
            payload=$(printf '{"message":"%s","content":"%s"}' "$commitMsg" "$encoded")

            curl --silent --request PUT \
                --header "Authorization: Bearer $uat" \
                --header "Accept: application/vnd.github+json" \
                --header "Content-Type: application/json" \
                --data "$payload" \
                "https://api.github.com/repos/$org/$repo/contents/$workflowPath" >/dev/null || {
                printf 'Failed to create workflow file.\n' >&2
                return 1
            }
            printf 'Workflow created.\n' >&2
        else
            printf 'Skipping workflow creation.\n' >&2
        fi
    fi

    # Trigger the workflow
    printf 'Triggering workflow %s...\n' "$workflowName" >&2
    curl --silent --request POST \
        --header "Authorization: Bearer $uat" \
        --header "Accept: application/vnd.github+json" \
        --header "Content-Type: application/json" \
        --data '{"ref":"main"}' \
        "https://api.github.com/repos/$org/$repo/actions/workflows/$workflowName/dispatches" || {
        printf 'Failed to trigger workflow.\n' >&2
        return 1
    }
    printf 'Workflow triggered. Watching runner logs...\n' >&2

    # Tail the runner log
    local logFile
    logFile=$(ls -t /opt/actions-runner/"$svcName"/_diag/Worker_*.log 2>/dev/null | head -1)
    if [[ -n "$logFile" ]]; then
        tail -f "$logFile"
    else
        printf 'No runner log found at /opt/actions-runner/%s/_diag/Worker_*.log\n' "$svcName" >&2
        printf 'Check https://github.com/%s/%s/actions for workflow status.\n' "$org" "$repo" >&2
    fi
}


#-------------------------------------------------------------------------------
#
# github-shr-clean()
#
# Remove a self-hosted runner: stop/uninstall svc, deregister from GitHub,
# delete runner directory. Derives svcName from $org-$repo, reads UAT
# from the uat folder in the runner folder. Must be run as root (try sudo).
#
github-shr-clean ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: github-shr-clean $org $repo\n' >&2; return 1; }
    local org=$1 repo=$2
    local svcName="shr-$org-$repo"
    local shrFolder="/opt/actions-runner/$svcName"

    [[ $EUID -eq 0 ]] || { printf 'github-shr-clean: must be run as root (try sudo)\n' >&2; return 1; }

    local reg_token
    reg_token=$(github-shr-swap-tokens "$org" "$repo") || return $?

    if [[ -f "$shrFolder/.service" ]]; then
        cd "$shrFolder" || return
        ./svc.sh stop 2>/dev/null || true
        ./svc.sh uninstall 2>/dev/null || true
    fi

    if [[ -f "$shrFolder/.runner" ]]; then
        cd "$shrFolder" 2>/dev/null || true
        ./config.sh remove --token "$reg_token" || \
            printf 'Warning: config.sh remove failed — orphaned runner may need manual cleanup\n' >&2
    fi

    rm -rf "$shrFolder"
    printf 'info: Cleaned up runner %s for %s/%s\n' "$svcName" "$org" "$repo"
}


#-------------------------------------------------------------------------------
#
# github-test-repo()
#
# Test if a GitHub repo exists
#
# Simple attempt to get info for a repo
# If it does not succeed, it could mean the org or repo are nonexistent or misspelled
# But it could also mean that the repo is non-public and requires a token for authentication
# The Github API returns 404s for all of the above, so the error status doesn't tell us anything
github-test-repo ()
{
    # parse github args
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
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
#-------------------------------------------------------------------------------
#
# github-test-repo-with-auth()
#
# Test if a GitHub repo exists with authentication
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


#-------------------------------------------------------------------------------
#
# github-validate-uat()
#
# Validate a user access token for a GitHub App.
# Checks whether the token can see an installation for the app.
# Prints a warning with remediation if not.
#
github-validate-uat ()
{
    # shellcheck disable=SC2016
    (( $# == 3 )) || { printf 'Usage: github-validate-uat $org $appSlug $uatPath\n' >&2; return 1; }
    local org=$1 appSlug=$2 uatPath=$3

    [[ -f "$uatPath" ]] || { printf 'github-validate-uat: UAT file not found: %s\n' "$uatPath" >&2; return 1; }

    github-is-gha-installed "$org" "$appSlug" "$uatPath" && return 0
    printf 'WARNING: %s is not installed on %s.\n' "$appSlug" "$org" >&2
    printf 'Install it at: https://github.com/apps/%s/installations/new\n' "$appSlug" >&2
    return 1
}


#-------------------------------------------------------------------------------
#
# go-service-gen-nginx-domain-file()
#
# Generate an nginx server block for a Go service domain
#
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


#-------------------------------------------------------------------------------
#
# go-service-gen-run-script()
#
# Generate a run script for a Go service
#
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


#-------------------------------------------------------------------------------
#
# go-service-gen-stop-script()
#
# Generate a stop script for a Go service
#
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


#-------------------------------------------------------------------------------
#
# go-service-gen-unit-file()
#
# Generate a systemd unit file for a Go service
#
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


#-------------------------------------------------------------------------------
#
# go-service-install()
#
# @note bigpickle no sure
# Install a Go service from a GitHub release onto an Incus VM
#
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


#-------------------------------------------------------------------------------
#
# go-service-uninstall()
#
# Uninstall a Go service from an Incus VM
#
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


#-------------------------------------------------------------------------------
#
# go-upgrade()
#
# Upgrade go on the host, or install it if not previously installed
#
# There's currently no good way to query what the latest version of go is.
# go isn't released on GitHub, so the GitHub API is no help. The only way to 
# specify a version is to pass it on the command line.
#
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


#-------------------------------------------------------------------------------
#
# hello()
#
# Print a greeting message
#
hello ()
{
    printf "Hello!\n"
}


#-------------------------------------------------------------------------------
#
# incus-api-call()
#
# Call the Incus API and return filtered JSON output
#
incus-api-call ()
{
    # shellcheck disable=SC2016
    (( $# >= 1 && $# <= 5 )) || { printf 'Usage: incus-api-curl $path [$jqexp [$schemeAndHost [$socketPath [$version]]]]\n' >&2; return 1; }
    local path=$1
    local jqexp=${2:-'.'}
    local schemeAndHost=${3:-'http://localhost'}
    local socketPath=${4:-"$HOME/.colima/default/incus.sock"}
    local version=${5:-'1.0'}

    # trim path leading slash if necessary
    path=${path#/}
    local url="$schemeAndHost/$version/$path"
    local tmpCurl; tmpCurl=$(mktemp --tmpdir incus.api.call.XXXXXX) || return
    curl --fail \
         --silent \
         --unix-socket "$socketPath" \
         "$url" \
         > "$tmpCurl" \
         || return
    cat "$tmpCurl" | jq -r "$jqexp" || return
}


#-------------------------------------------------------------------------------
#
# incus-api-curl()
#
# Call the Incus API via curl and return raw output
#
incus-api-curl ()
{
    # shellcheck disable=SC2016
    (( $# >= 1 && $# <= 2 )) || { printf 'Usage: incus-api-curl $path [$socketPath]\n' >&2; return 1; }
    local url=$1
    local socketPath=${2:-"$HOME/.colima/default/incus.sock"}

    local tmpCurl; tmpCurl=$(mktemp --tmpdir incus.api.curl.XXXXXX) || return
    curl --fail \
         --silent \
         --unix-socket "$socketPath" \
         "$url" \
         > "$tmpCurl" \
         || return
    cat "$tmpCurl"
}


#-------------------------------------------------------------------------------
#
# incus-api-instances()
#
# List Incus instance names via the API
#
incus-api-instances ()
{
    # shellcheck disable=SC2016
    (( $# >= 0 && $# <= 3 )) || { printf 'Usage: incus-api-instances [$schemeAndHost [$socketPath [$version]]]\n' >&2; return 1; }
    local schemeAndHost=${1:-'http://localhost'}
    local socketPath=${2:-"$HOME/.colima/default/incus.sock"}
    local version=${3:-'1.0'}

    local path='/instances'
    local jqexp='.metadata[] | ltrimstr("/1.0/instances/")'
    incus-api-call "$path" "$jqexp" || return
}


#-------------------------------------------------------------------------------
#
# incus-api-versions()
#
# List available Incus API versions
#
incus-api-versions ()
{
    # shellcheck disable=SC2016
    (( $# >= 0 && $# <= 1 )) || { printf 'Usage: incus-api-versions [$socketPath]\n' >&2; return 1; }
    local socketPath=${1:-"$HOME/.colima/default/incus.sock"}

    local path="http://localhost/"
    incus-api-curl "$path" \
    | jq -r '.metadata.[]' \
    || return
}


#####
#
# incus-config-snapshots $instanceName $schedule $expiry [$pattern]
# 
#-------------------------------------------------------------------------------
#
# incus-config-snapshots()
#
# Configure automatic snapshots for an incus container
#
# `incus snapshot --help` && incus docs for more info on the incus arg syntax
#
incus-config-snapshots ()
{
    local name=$1
    local schedule=$2
    local expiry=$3
    local pattern=${4:-"{{ creation_date|date:'2006-01-02_15-04-05' }}"}
    incus config set "$name" \
        snapshots.schedule="$schedule" \
        snapshots.expiry="$expiry" \
        snapshots.pattern="$pattern"
}


#-------------------------------------------------------------------------------
#
# incus-create-profiles()
#
# Create Incus resource limit profiles
#
incus-create-profiles ()
{
    # create small profile from docstring
    incus profile create small <<- 'EOT'
config:
	limits.cpu.allowance: 50%
	limits.memory: 512MiB 
EOT

    # create medium profile from docstring
    incus profile create medium <<- 'EOT'
config:
	limits.cpu.allowance: 100%
	limits.memory: 1GiB
EOT
}


#-------------------------------------------------------------------------------
#
# incus-create-ssh-profile()
#
# Create an Incus profile with an SSH proxy device
#
incus-create-ssh-profile ()
{
	# shellcheck disable=SC2016
	{ (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: incus-create-www-profile [$sshPort]\n' >&2; return 1; }
	local sshPort=${1:-22}
    # profile: serve HTTP/S
    incus profile create www || return
    incus profile device add www ssh proxy listen="tcp:0.0.0.0:$sshPort" connect=tcp:127.0.0.1:22 || return
}


#-------------------------------------------------------------------------------
#
# incus-create-www-profile()
#
# Create an Incus profile with HTTP/S proxy devices
#
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


#-------------------------------------------------------------------------------
#
# incus-dump-id-map()
#
# Dump the UID/GID mapping for an instance
#
incus-dump-id-map ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: incus-dump-id-map $container\n' >&2; return 1; }
    local container=$1

    local idMapPath; idMapPath=$(create-temp-file "$container.idmap.XXXXXX") || return
    incus query "/1.0/containers/$container" | jq -r '.expanded_config["incus.idmap"] // empty' | awk NF > "$idMapPath"
    printf '%s' "$idMapPath"
}


#-------------------------------------------------------------------------------
#
# incus-install()
#
# @note bigpickle no sure
# Install Incus from zabbly or snap package sources
#
incus-install ()
{
	apt-get update -y
	apt-get upgrade -y
	apt-get install incus -y
}


#-------------------------------------------------------------------------------
#
# incus-instance-exists()
#
# Check if an Incus instance exists
#
incus-instance-exists ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: incus-instance-exists $container\n' >&2; return 1; }
    local name=$1
    incus query "/1.0/instances/$name" >/dev/null 2>&1
}


#-------------------------------------------------------------------------------
# 
# incus-pull-file()
#
# Pull a file from a vm to a newly created temp folder
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


#-------------------------------------------------------------------------------
#
# incus-push-file()
#
# Push a file into an Incus instance
#
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


#-------------------------------------------------------------------------------
#
# incus-remove-file()
#
# Remove a file from an Incus instance
#
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


#-------------------------------------------------------------------------------
#
# incus-set-id-map()
#
# Set UID/GID mapping on an instance and restart it
#
incus-set-id-map ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: incus-set-id-map $container $idMapPath\n' >&2; return 1; }
    local container=$1
    local idMapPath=$2

    incus config set "$container" incus.idmap - < <(sort "$idMapPath" | uniq)
    incus restart "$container" 2>/dev/null || incus start "$container"
    incus exec "$container" -- cloud-init status --wait
}


#-------------------------------------------------------------------------------
#
# incus-share-folder()
#
# Share a host folder with an instance via disk device
#
incus-share-folder ()
{
    # shellcheck disable=SC2016
    (( $# == 4 )) || { printf 'Usage: incus-share-folder $container $share $srcDir $dstDir\n' >&2; return 1; }
    local container=$1
    incus-instance-exists  "$container" || { printf 'Non-existent container: %s\n' "$container"; return 1; }
    local share=$2
    local srcDir=$3
    [[ -d "$srcDir" ]] || { echo "Non-existent folder: $srcDir" >&2; return 1; }
    local dstDir=$4
    incus config device add "$container" "$share" disk source="$srcDir" path="$dstDir"
}


#-------------------------------------------------------------------------------
#
# init-alpine()
#
# Initialize an Alpine Linux container with daylight's requirements
#
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


#-------------------------------------------------------------------------------
#
# init-incus()
#
# @note opencode nosure - review these steps to see if they are correct for incus
# Initialize Incus with BTRFS storage, id mapping, and proxy profiles
#
init-incus ()
{
    # Remove the packaged lxc/d since it causes problems
    apt-get remove -y lxd lxd-client liblxc-common liblxc-dev liblxc1 lxc-dev lxcfs nova-compute-lxc
    # Setup subuid+subgid to allow for mapping ubuntu
    add-user-to-shadow-ids ubuntu
    # Setup /dev/xvdf as a btrfs volume, then bind mount it onto the incus images folder
    [[ -b "/dev/xvdf" ]] || { echo "Non-existent device: /dev/xvdf" >&2; return 1; }
    mkfs -t btrfs /dev/xvdf || return
    mkdir -p /mnt/data/incus || return
    mount /dev/xvdf /mnt/data/incus || return
    mkdir /mnt/data/incus/images || return
    # Install the incus snap
    snap install incus || return
    # Initialize incus with btrfs and use the volume on /dev/xvdg for incus stuff
    [[ -b "/dev/xvdg" ]] || { echo "Non-existent device: /dev/xvdg" >&2; return 1; }
    incus admin init --auto --storage-backend btrfs --storage-create-device /dev/xvdg --storage-pool default || return
    # Bind mount the images folder from above and restart incus
    mount -o bind /mnt/data/incus/images /var/snap/incus/common/incus/images || return
    snap restart incus || return
    # Setup xvdh to be the volume for instance home dirs
    [[ -b "/dev/xvdh" ]] || { echo "Non-existent device: /dev/xvdh" >&2; return 1; }
    mkfs -t ext4 /dev/xvdh
    mkdir -p /mnt/home
    mount /dev/xvdh /mnt/home
    chown -R ubuntu:ubuntu /mnt/home
    # profile: map ubuntu from host to container
    incus profile create map-ubuntu || return
    local uid; uid=$(id --user ubuntu) || return
    local gid; gid=$(id --group ubuntu) || return
    incus profile set map-ubuntu incus.idmap - < <(printf 'uid %d %d\ngid %d %d\n' "$uid" "$uid" "$gid" "$gid") || return
    # profile: serve HTTP/S
    incus profile create www || return
    incus profile device add www https proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443 || return
    incus profile device add www http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80 || return
# }

    # install the shell script handlers ... clunky but it'll do for now
    aws s3 cp --recursive --exclude "*" --include "shell_script_per_*.py" "s3://$bucket/conf/scripts" /usr/bin
}


#-------------------------------------------------------------------------------
#
# init-lxd()
#
# @note bigpickle no sure
# Initialize LXD with BTRFS storage, id mapping, and proxy profiles
#
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


#-------------------------------------------------------------------------------
#
# init-nginx()
#
# @note bigpickle no sure
# Initialize nginx with configuration
#
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


#-------------------------------------------------------------------------------
#
# init-rayray()
#
# Initialize the rayray user environment
#
init-rayray ()
{
    # Set rayray up for sudo
    [[ -d "/etc/sudoers.d" ]] || { printf 'Non-existent folder: /etc/sudoers.d\n' >&2; return 1; }
    echo 'rayray ALL = (root) NOPASSWD: ALL' >/etc/sudoers.d/rayray

    # init ssh folder
	mkdir -p /home/rayray/.ssh || return
    touch /home/rayray/.ssh/authorized_keys || return
	chmod 700 /home/rayray/.ssh/ || return
	chmod 600 /home/rayray/.ssh/authorized_keys || return
	
	# setup rayray for ssh login
	local pubkey='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGM3ZAxYzH+1xiEYJ051UsmJkWWLR6zZ5dXx1ZPS1Bvj rayray@dylt.dev'
   	printf '%s\n' "$pubkey" >> /home/rayray/.ssh/authorized_keys || return

    # make rayray:rayray owner of everything in home folder
    chown -R rayray:rayray /home/rayray/ || return
}


#-------------------------------------------------------------------------------
#
# init-rpi()
#
# @note bigpickle no sure
# Initialize a Raspberry Pi system
#
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
    install-dylt /opt/bin/ || return
}


#-------------------------------------------------------------------------------
#
# install-app()
#
# Copy application files to an install destination
#
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


#-------------------------------------------------------------------------------
#
# install-awscli()
#
# Install and configure the AWS CLI
#
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


#-------------------------------------------------------------------------------
#
# install-build-nightly-svc()
#
# Install a systemd indexed service for nightly releases of a repo.
# Downloads template unit files from the daylight repo and writes a
# repo-specific run.sh that calls trigger-nightly-release on dispatch.
# Enables the timer and warns about the missing env file.
#
install-build-nightly-svc ()
{
    (( $# == 1 )) || { printf 'Usage: install-build-nightly-svc $repo\n' >&2; return 1; }
    local repo=$1
    local instance=${repo//\//-}
    local base="https://raw.githubusercontent.com/daylight-public/daylight/main"
    local svcDir=/opt/svc/nightly-release

    mkdir -p "$svcDir/$instance/bin"
    chown -R rayray:rayray "$svcDir"

    curl -s --remote-name --output-dir /etc/systemd/system \
        "$base/svc/nightly-release/nightly-release@.service"
    curl -s --remote-name --output-dir /etc/systemd/system \
        "$base/svc/nightly-release/nightly-release@.timer"

    cat > "$svcDir/$instance/bin/run.sh" <<'RUNEOF'
#!/usr/bin/env bash
main ()
{
    local svcDir=/opt/svc/nightly-release
    cd "$svcDir/INSTANCE/repo" || exit 1
    git pull --ff-only origin main || exit 1
    source ./sunbeam.sh 2>/dev/null || source ./daylight.sh 2>/dev/null || {
        printf 'error: no script to source\n'; exit 1
    }
    trigger-nightly-release "REPO" || exit 1
}
main "$@"
RUNEOF
    sed -i "s/INSTANCE/$instance/g; s|REPO|$repo|g" "$svcDir/$instance/bin/run.sh"
    chmod 755 "$svcDir/$instance/bin/run.sh"

    systemctl enable "nightly-release@$instance.service"
    systemctl enable "nightly-release@$instance.timer"
    systemctl start "nightly-release@$instance.timer"

    printf 'NOTE: Create %s/%s/env with GITHUB_TOKEN=... before timer fires\n' "$svcDir" "$instance"
}


#-------------------------------------------------------------------------------
#
# install-dylt ()
#
# download the latest dylt binary and install it in the specified folder.
# installation folder defaults to /opt/bin/
#  
install-dylt ()
{
    { (( $# >= 0 )) && (( $# <= 2 )); } || { printf 'Usage: install-dylt [$platform [$dstFolder]]\n' >&2; return 1; }
    local platform=${1:-''}
    local dstFolder=${2:-/opt/bin/}
    [[ -d "$dstFolder" ]] || { echo "Non-existent folder: $dstFolder" >&2; return 1; }

    local tmpFolder; tmpFolder=$(mktemp --directory --tmpdir dylt-XXXXXX) || return
    if [[ -n "$platform" ]]; then
        download-dylt "$tmpFolder" "$platform" || return
    else
        download-dylt "$tmpFolder" || return
    fi

    local tarball
    tarball=$(find "$tmpFolder" -name 'dylt_*.tar.gz' -type f | head -1) || return
    [[ -n "$tarball" ]] || { printf 'No tarball found in %s\n' "$tmpFolder" >&2; return 1; }

    tar --directory "$dstFolder" --extract --gunzip --file "$tarball" || return
    chmod 777 "$dstFolder/dylt" || return
}


# Install etcd from source
#   - Get latest version
#   - Get the URL for the latest release
#   - Download the tarball of the latest release
#   - Install the release in the specified install folder
#   - Setup the data directory
#-------------------------------------------------------------------------------
#
# install-etcd()
#
# Install etcd from GitHub releases as a systemd service
#
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


#-------------------------------------------------------------------------------
#
# install-flask-app()
#
# Install a Flask app as a systemd service
#
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


#-------------------------------------------------------------------------------
#
# install-fresh-daylight-svc()
#
# Install a fresh daylight systemd service
#
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


#-------------------------------------------------------------------------------
#
# install-gnome-keyring()
#
# Install and configure the GNOME keyring
#
install-gnome-keyring ()
{
    sudo apt-get install libsecret-1-0 libsecret-1-dev
    make -C /usr/share/doc/git/contrib/credential/libsecret
    git config --global credential.helper /usr/share/doc/git/contrib/credential/libsecret/git-credential-libsecret
}


#-------------------------------------------------------------------------------
#
# install-latest-httpie()
#
# Install the latest version of HTTPie
#
install-latest-httpie ()
{
    curl -SsL -o /etc/apt/sources.list.d/httpie.list https://packages.httpie.io/deb/httpie.list
    curl -SsL https://packages.httpie.io/deb/KEY.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/httpie.gpg >/dev/null
    apt update -y
    apt install -y httpie
}


#-------------------------------------------------------------------------------
#
# install-mssql-tools()
#
# Install SQL Server command-line tools
#
install-mssql-tools ()
{
    curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
    apt-get -y update
    sudo ACCEPT_EULA=Y apt-get install -y mssql-tools
}


#-------------------------------------------------------------------------------
#
# install-pubbo()
#
# Install the pubbo utility
#
install-pubbo ()
{
    [[ -d "/opt/bin/" ]] || { echo "Non-existent folder: /opt/bin/" >&2; return 1; }
    github-release-install dylt-dev pubbo linux_amd64 /opt/bin/
}


#-------------------------------------------------------------------------------
#
# install-public-key()
#
# Install an SSH public key for a user
#
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


#-------------------------------------------------------------------------------
#
# install-python()
#
# Install Python 3 with pip, setuptools, and wheel from deadsnakes PPA
#
install-python ()
{
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update -y
    apt-get install -y python3 python3-dev python3-pip python3-testresources python3-venv
    pip3 install --upgrade pip setuptools wheel
}


#
# Given a tar, create a service folder, copy the tars contents to the service folder, and create
#-------------------------------------------------------------------------------
#
# install-service()
#
# Install a systemd service from a tarball
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


#-------------------------------------------------------------------------------
#
# install-service-from-script()
#
# Install a systemd service from a script file
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


#-------------------------------------------------------------------------------
#
# install-service-from-command()
#
# Install a systemd service from a command
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


#-------------------------------------------------------------------------------
#
# install-shellscript-part-handlers()
#
# Install cloud-init part-handler scripts
#
install-shellscript-part-handlers ()
{
    download-dist || return
    srcFolder=$(untar-to-temp-folder /tmp/dist/conf.tgz)
    cp "$srcFolder"/scripts/shell_script_per_*.py /usr/bin
    # chown rayray:rayray /usr/bin/shell_script_per_*.py
}


#-------------------------------------------------------------------------------
#
# install-svc()
#
# Install a service from a tarball
#
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


#-------------------------------------------------------------------------------
#
# install-venv()
#
# Create and install a Python virtual environment
#
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


#-------------------------------------------------------------------------------
#
# install-vm()
#
# Install a VM from a config folder and publish it
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
    incus init "$imageBase" "$instance" || return
    incus config set "$instance" user.user-data - <"$userDataPath" || return
    incus start "$instance" || return
    incus exec "$instance" -- cloud-init status --wait || return
     # Publish the instance as an instance
    incus stop "$instance" || return
    incus publish "$instance" "$imageRepo:" --alias "$imageName" || return
    incus delete "$instance" || return
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
    # incus init "$base" "$vm" || return
    # incus config set "$vm" user.user-data - <"$userDataPath" || return
    # incus start "$vm" || return
    # incus exec "$vm" -- cloud-init status --wait || return
    # # Publish the instance as an image
    # incus stop "$vm" || return
    # incus publish "$vm" "$imageRepo:" --alias "$vm" || return
    # [[ -f "$userDataPath" ]] || { echo "Non-existent path: $userDataPath" >&2; return 1; }
}


#-------------------------------------------------------------------------------
#
# is-debian()
#
# Check if the host OS is Debian-based
#
is-debian ()
{
    (( $# == 0 )) || { printf 'Usage: is-debian\n' >&2; return 1; }
    
    # Check if /etc/os-release exists
    [[ -f /etc/os-release ]] || return 1
    
    # Source the os-release file
    source /etc/os-release
    
    # Check if ID is debian or ID_LIKE contains debian
    if [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
        return 0
    fi
    
    return 1
}


#-------------------------------------------------------------------------------
#
# list-apps()
#
# List application tarballs in the S3 dist bucket
#
list-apps ()
{
    local bucket; bucket=$(get-bucket) || return
    aws s3api list-objects --bucket "$bucket" --prefix 'dist/app' --query 'Contents[].Key[]' | jq -r '.[] | match("^dist/app/(.*)\\.tgz$").captures[0].string' || return
}


#-------------------------------------------------------------------------------
#
# list-bash-funcs()
#
# List all bash functions in a bash script, sorted
#
list-bash-funcs ()
{
	# shellcheck disable=SC2016
	(( $# == 0 )) || { printf 'Usage: list-bash-funcs <bashScript.sh\n' >&2; return 1; }
	# Confirm user is not interactive
	if [[ -t 0 ]]; then
		printf '\nstdin is a terminal; please redirect input from stdin.\n\n';
		return 0
	fi

	local in_case=0
	local line
	while IFS= read -r line; do
		# Track when we enter/exit the case block
		if [[ "$line" =~ ^[[:space:]]*case[[:space:]]+\"[$]cmd\"[[:space:]]+in ]]; then
			in_case=1
			continue
		fi
		if [[ "$line" =~ ^[[:space:]]*esac ]]; then
			in_case=0
			continue
		fi
		
		# Only process lines within the case block
		(( in_case )) || continue
		
		# Check if line matches case label pattern
		if [[ "$line" =~ ^[[:space:]]+[a-zA-Z0-9_-]+\) ]]; then
			# Remove everything from ) onward
			line="${line%%)*}"
			# Strip leading whitespace
			line="${line#"${line%%[![:space:]]*}"}"
			# Output the result
			printf '%s\n' "$line"
		fi
	done | sort
}


#-------------------------------------------------------------------------------
#
# list-conf-scripts()
#
# List configuration scripts from the S3 conf bucket
#
list-conf-scripts ()
{
    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/conf.tgz"
    local confDir; confDir=$(download-to-temp-dir "$s3url") || return
    local scriptDir="$confDir/scripts"
    [[ -d "$scriptDir" ]] || { printf 'Non-existent folder: %s\n' "$scriptDir" >&2; return 1; }
    ls -1 "$scriptDir"
}


#-------------------------------------------------------------------------------
#
# list-git-repos()
#
# List git repositories from etcd
#
list-git-repos () 
{ 
	# shellcheck disable=SC2016
	{ (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: list-git-remotes $repo [$shrHome]\n' >&2; return 1; }
    repo=$1;
    shrHome=${2:-/opt/actions-runner/_work};
    shrPath="$shrHome/$repo/$repo";
    git -C "$shrPath" remote --verbose
}


#-------------------------------------------------------------------------------
#
# list-host-public-keys()
#
# List SSH public keys installed on the host
#
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


#-------------------------------------------------------------------------------
#
# list-public-keys()
#
# List SSH public keys
#
list-public-keys ()
{
    local bucket; bucket=$(get-bucket) || return
    local s3url="s3://$bucket/dist/ssh.tgz"

    aws s3 cp "$s3url" - | tar -tzf - | while read -r f; do [[ $f =~ .*/$ ]] || printf '%s\n' "${f##*/}"; done
}


#-------------------------------------------------------------------------------
#
# list-services()
#
# List systemd services managed by daylight
#
list-services ()
{
    local bucket; bucket=$(get-bucket) || return
    aws s3api list-objects --bucket "$bucket" --prefix 'dist/svc' --query 'Contents[].Key' | jq -r '.[] | match("^dist/svc/(.*)\\.tgz$").captures[0].string'
}


#-------------------------------------------------------------------------------
#
# list-shr-entries()
#
# List self-hosted runner registrations from etcd
#
list-shr-entries () 
{ 
	# shellcheck disable=SC2016
	{ (( $# >= 0 )) && (( $# <= 1 )); } || { printf 'Usage: list-shr-entries [shrHome]\n' >&2; return 1; }
    shrHome=${1:-/opt/actions-runner/_work};

    ( cd "$shrHome" && find . -mindepth 1 -maxdepth 1 -type d -regex '^\./[A-Za-z0-9].*$' )
}


#-------------------------------------------------------------------------------
#
# list-vms()
#
# List Incus VM instances
#
list-vms ()
{
    local bucket; bucket=$(get-bucket) || return
    aws s3api list-objects --bucket "$bucket" --prefix 'dist/vm' --query 'Contents[].Key[]' | jq -r '.[] | match("^dist/vm/(.*)\\.tgz$").captures[0].string' || return
}


#-------------------------------------------------------------------------------
#
# lxd-dump-id-map()
#
# Dump the UID/GID mapping for a container
#
lxd-dump-id-map ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: lxd-dump-id-map $container\n' >&2; return 1; }
    local container=$1

    local idMapPath; idMapPath=$(create-temp-file "$container.idmap.XXXXXX") || return
    lxc query "/1.0/containers/$container" | jq -r '.expanded_config["raw.idmap"] // empty' | awk NF > "$idMapPath"
    printf '%s' "$idMapPath"
}


#-------------------------------------------------------------------------------
#
# lxd-instance-exists()
#
# Check if an LXD instance exists
#
lxd-instance-exists ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: lxc-instance-exists $container\n' >&2; return 1; }
    local name=$1
    lxc query "/1.0/instances/$name" >/dev/null 2>&1
}


#-------------------------------------------------------------------------------
#
# lxd-set-id-map()
#
# Set UID/GID mapping on a container and restart it
#
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


#-------------------------------------------------------------------------------
#
# lxd-share-folder()
#
# Share a host folder with a container via disk device
#
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


#-------------------------------------------------------------------------------
#
# pgql-add-repo()
#
# Add the PostgreSQL APT repository
#
pgql-add-repo ()
{
    local versionCodeName; versionCodeName=$(get-linux-version-codename) || return
    local signedBy=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
    local aptUrl="https://apt.postgresql.org/pub/repos/apt"
    local aptListdPath="/etc/apt/sources.list.d/pgdg.list"
    sh -c "echo 'deb [signed-by=$signedBy] $aptUrl $versionCodeName-pgdg main' >$aptListdPath"
}


#-------------------------------------------------------------------------------
#
# pgql-install-client()
#
# Install the PostgreSQL client
#
pgql-install-client ()
{
    # shellcheck disable=SC2016
    (( $# >= 0 && $# <= 1 )) || { printf 'Usage: pgql-install-client [$version]\n' >&2; return 1; }
    local version=${1:-''}

    pgql-install-repo-key || return
    pgql-add-repo || return
    apt update -y || return
    local packageName
    if [[ -n "$version" ]]; then
        packageName="postgresql-client-$version"
    else
        packageName="postgresql-client"
    fi
    apt install "$packageName" -y || return
}


#-------------------------------------------------------------------------------
#
# pgql-install-repo-key()
#
# Import the PostgreSQL APT repository signing key
#
pgql-install-repo-key ()
{
    apt update -y
    apt install curl ca-certificates || return
    install -d /usr/share/postgresql-common/pgdg || return
    curl --silent \
         --fail \
         --output /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
         https://www.postgresql.org/media/keys/ACCC4CF8.asc
}


#-------------------------------------------------------------------------------
#
# prep-filesystem()
#
# Prepare the daylight filesystem structure
#
prep-filesystem ()
{
    mkdir -p /etc/nginx/streams.d/
    chmod 777 /etc/nginx/streams.d/
    mkdir -p /opt/actions-runner/
    mkdir -p /opt/bin/
    mkdir -p /opt/svc/
}


#-------------------------------------------------------------------------------
#
# prep-service()
#
# Prepare a service folder structure and install it
#
prep-service ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: prep-service $svcName\n' >&2; return 1; }
    [[ -d "/opt/svc/" ]] || { echo "Non-existent folder: /opt/svc/" >&2; return 1; }
    svcName=$1

    mkdir -p "/opt/svc/$svcName"
    mkdir -p "/opt/svc/$svcName/bin"
}


#-------------------------------------------------------------------------------
#
# print-os-arch-vars()
#
# Print OS and architecture variables
#
print-os-arch-vars ()
{
    print-vars HOSTTYPE MACHTYPE OSTYPE
}


#-------------------------------------------------------------------------------
#
# print-vars()
#
# Print shell variables matching a given prefix
#
print-vars ()
{
    for varname in "$@"; do
        printf '%s=%s\n' "$varname" "${!varname}"
    done
}


#-------------------------------------------------------------------------------
#
# pull-app()
#
# Download and install an application from S3
#
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


#-------------------------------------------------------------------------------
#
# pullAppInfo()
#
# Pull application metadata from etcd
#
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
#-------------------------------------------------------------------------------
#
# pull-daylight()
#
# Download and source the latest daylight.sh from GitHub
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


#-------------------------------------------------------------------------------
#
# pull-flask-app()
#
# Download and install a Flask app from S3
#
pull-flask-app ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: pull-flask-app $name [$dstFolder]\n' >&2; return 1; }
    local name=$1
    local dstFolder=${2:-"/app/flask/$name"}

    local srcFolder; srcFolder=$(download-flask-app "$name") || return
    install-flask-app "$name" "$srcFolder" >/dev/null || return
}


#-------------------------------------------------------------------------------
#
# pull-git-repo()
#
# Clone or pull a git repository
#
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


#-------------------------------------------------------------------------------
#
# pull-image()
#
# Pull a VM image from S3
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
    incus init "$base" "$instance" || return
    incus config set "$instance" user.user-data - <"$userDataPath" || return
    incus start "$instance" || return
    incus exec "$instance" -- cloud-init status --wait || return
     # Publish the instance as an instance
    incus stop "$instance" || return
    incus publish --public "$instance" "$imageRepo:" --alias "$imageName" || return
    incus delete "$instance" || return
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
    # incus init "$base" "$vm" || return
    # incus config set "$vm" user.user-data - <"$userDataPath" || return
    # incus start "$vm" || return
    # incus exec "$vm" -- cloud-init status --wait || return
    # # Publish the instance as an image
    # incus stop "$vm" || return
    # incus publish "$vm" "$imageRepo:" --alias "$vm" || return
    # [[ -f "$userDataPath" ]] || { echo "Non-existent path: $userDataPath" >&2; return 1; }
}


#-------------------------------------------------------------------------------
#
# pull-ssh-tarball()
#
# Download SSH key tarball from S3
#
pull-ssh-tarball ()
{
    local bucket; bucket=$(get-bucket) || return
    sshUrl="s3://$bucket/conf/ssh.tgz"
    local sshDir; sshDir=$(download-to-temp-dir "$sshUrl") || return
    printf '%s' "$sshDir"
}


#-------------------------------------------------------------------------------
#
# pull-svc()
#
# Download and install a service from S3
#
pull-svc ()
{
    # shellcheck disable=SC2016
    { (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: pull-svc $name [$dstFolder]\n' >&2; return 1; }
    local name=$1
    local dstFolder=${2:-"/app/svc/$name"}

    local srcFolder; srcFolder=$(download-svc "$name") || return
    install-svc "$name" "$srcFolder" >/dev/null || return
}


#-------------------------------------------------------------------------------
#
# pull-vm()
#
# Pull VM config and install files from S3
#
pull-vm ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: pull-vm $name\n' >&2; return 1; }
    local name=$1

    local srcFolder; srcFolder=$(download-vm "$name") || return
    install-vm "$name" "$srcFolder"
    activate-vm "$name" "$srcFolder"
}


#-------------------------------------------------------------------------------
#
# pull-webapp()
#
# Download and install a webapp from S3
#
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


#-------------------------------------------------------------------------------
#
# push-app()
#
# Push an application tarball to S3
#
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


#-------------------------------------------------------------------------------
#
# push-daylight()
#
# Push daylight.sh to the S3 dist bucket
#
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


#-------------------------------------------------------------------------------
#
# push-flask-app()
#
# Push a Flask app tarball to S3
#
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


#-------------------------------------------------------------------------------
#
# push-svc()
#
# Push a service tarball to S3
#
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


#-------------------------------------------------------------------------------
#
# push-webapp()
#
# Push a webapp tarball to S3
#
push-webapp ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: push-webapp $name\n' >&2; return 1; }
    local name=$1

    tar -C "/www/$name" --exclude ./**/__pycache__ -czf "/tmp/$name.tgz" . || return
    local s3key; s3key="s3://$(get-bucket)/dist/webapp/$name.tgz" || return
    aws s3 cp "/tmp/$name.tgz" "$s3key" || return
}


#-------------------------------------------------------------------------------
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


#-------------------------------------------------------------------------------
#
# replace-nginx-conf()
#
# Replace nginx.conf with a standardized configuration
#
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


#-------------------------------------------------------------------------------
#
# restart-nginx()
#
# Test nginx config and restart the service
#
restart-nginx ()
{
    if ! nginx -t; then
        printf "Error with nginx config.\n" >&2
        return 1
    fi
    systemctl restart nginx
}


#-------------------------------------------------------------------------------
#
# run-conf-script()
#
# Download and run a configuration script from S3
#
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


#-------------------------------------------------------------------------------
#
# run-service()
#
# Run a service in the foreground with its environment
#
run-service ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: run-service $serviceName\n' >&2; return 1; }
    local name=$1

    cd "$(get-service-working-directory "$name")" || return
    source-service-environment-file "$name"
    bash -ux -c "$(get-service-exec-start "$name")"
}


#-------------------------------------------------------------------------------
#
# setup-domain()
#
# Set up nginx and certbot for a domain
#
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


#-------------------------------------------------------------------------------
#
# sanitize-label()
#
# Sanitize a human-readable label for use in a git tag.
# Spaces become dashes; non-alphanumeric, non-dot, non-underscore,
# non-hyphen characters are stripped.
#
sanitize-label ()
{
    (( $# == 1 )) || { printf 'Usage: sanitize-label $label\n' >&2; return 1; }
    local label=$1
    label=${label// /-}
    label=${label//[^a-zA-Z0-9._-]/}
    printf '%s' "$label"
}


#-------------------------------------------------------------------------------
#
# source-daylight()
#
# Source the daylight.sh script
#
source-daylight ()
{
    local daylightPath; daylightPath=$(command -v daylight.sh) || return
    # shellcheck source=/dev/null
    source "$daylightPath"
}


#-------------------------------------------------------------------------------
#
# source-service-environment-file()
#
# Source the environment file for a service
#
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


#-------------------------------------------------------------------------------
#
# start-indexed-service()
#
# Start templated systemd service instances for each parameter
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


#-------------------------------------------------------------------------------
#
# start-service()
#
# Enable and start a systemd service, with optional timer
#
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


#-------------------------------------------------------------------------------
#
# sync-add-service()
#
# Enable and start a sync service as a systemd unit
#
sync-add-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	systemctl enable "$unitName" || return
	sync-run-service "$key" "$downloadPath" || return
	sync-follow-service "$key" "$downloadPath" || return

}


#-------------------------------------------------------------------------------
#
# sync-create-unit-name()
#
# Generate a systemd unit name for a sync service
#
sync-create-unit-name () 
{ 
    key=$1;
    downloadPath=$2;
    systemd-escape --template 'sync-daylight@.service' "$key $downloadPath" || return
}


#-------------------------------------------------------------------------------
#
# sync-daylight-gen-run-script()
#
# Generate a run script for a sync-daylight service
#
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


#-------------------------------------------------------------------------------
#
# sync-daylight-gen-unit-file()
#
# Generate a systemd unit file for sync-daylight
#
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


#-------------------------------------------------------------------------------
#
# sync-daylight-install-service()
#
# Install a sync-daylight systemd service
#
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


#-------------------------------------------------------------------------------
#
# sync-follow-service()
#
# Follow logs for a sync service
#
sync-follow-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	journalctl --unit "$unitName" --follow  || return
}


#-------------------------------------------------------------------------------
#
# sync-remove-service()
#
# Disable and remove a sync systemd service
#
sync-remove-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	systemctl disable "$unitName" || return
}


#-------------------------------------------------------------------------------
#
# sync-run-service()
#
# Start a sync-daylight service
#
sync-run-service ()
{
	key=$1
	downloadPath=$2

	unitName=$(sync-create-unit-name "$key" "$downloadPath") || return
	systemctl start "$unitName" || return
}


#-------------------------------------------------------------------------------
#
# trigger-nightly-release-batch()
#
# Trigger a GHA workflow for a given repo via workflow_dispatch.
# Requires --workflow; accepts --token (falls back to GITHUB_TOKEN env var)
# and --label. No interactivity, no token inference.
#
trigger-nightly-release-batch ()
{
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: trigger-nightly-release-batch --workflow <name> [--token <pat>] [--label <label>] $owner/$repo\n' >&2; return 1; }
    local repo=$1

    local workflow=${argmap[workflow]}
    [[ -n "$workflow" ]] || { printf 'error: --workflow is required\n' >&2; return 1; }

    local token=${argmap[token]:-${GITHUB_TOKEN:?error: --token not given and GITHUB_TOKEN not set}}

    local wf_name=${workflow%.yml}
    wf_name=${wf_name%.yaml}
    if ! curl -sf -o /dev/null \
        "https://api.github.com/repos/$repo/actions/workflows/${wf_name}.yml"; then
        printf 'error: workflow "%s" not found in %s\n' "$workflow" "$repo" >&2
        return 1
    fi

    local -a flags=(--token "$token")
    local data
    if [[ -n "${argmap[label]}" ]]; then
        local label
        label=$(sanitize-label "${argmap[label]}") || return
        data=$(printf '{"ref":"main","inputs":{"label":"%s"}}' "$label")
    else
        data='{"ref":"main"}'
    fi
    flags+=(--data "$data")

    github-curl "${flags[@]}" "/repos/$repo/actions/workflows/${wf_name}.yml/dispatches" || return
}


#-------------------------------------------------------------------------------
#
# trigger-nightly-release()
#
# Trigger a GHA workflow for a given repo via workflow_dispatch.
# Auth is resolved automatically by github-curl (GITHUB_TOKEN → GH_TOKEN → gh auth token).
#
trigger-nightly-release ()
{
    local -A argmap=()
    local nargs=0
    github-curl-parse-args argmap nargs "$@" || return
    shift "$nargs"
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: trigger-nightly-release [--workflow <name>] [--token <pat>] [--label <label>] $owner/$repo\n' >&2; return 1; }
    local repo=$1

    local workflow=${argmap[workflow]:-nightly-release}
    local label=${argmap[label]:-''}

    local token
    if [[ -v argmap[token] ]]; then
        token=${argmap[token]}
    elif [[ -n "${GITHUB_TOKEN-}" ]]; then
        token=$GITHUB_TOKEN
    elif [[ -n "${GH_TOKEN-}" ]]; then
        token=$GH_TOKEN
    elif type gh &>/dev/null; then
        token=$(gh auth token 2>/dev/null) || token=''
    fi

    local -a batch_args=(--workflow "$workflow" --token "$token")
    [[ -n "$label" ]] && batch_args+=(--label "$label")
    trigger-nightly-release-batch "${batch_args[@]}" "$repo" || return
}


#-------------------------------------------------------------------------------
#
# sys-start()
#
# Start a systemd service and show journalctl on failure
#
sys-start ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: sys-start $service\n' >&2; return 1; }
    local service=$1

    systemctl restart "$service" || journalctl --unit "$service"
}


#-------------------------------------------------------------------------------
#
# uninstall-etcd()
#
# Uninstall an installed etcd service
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


#-------------------------------------------------------------------------------
#
# untar-to-temp-folder()
#
# Extract a tar archive to a temporary directory
#
untar-to-temp-folder ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: untar-to-temp-folder $1\n' >&2; return 1; }
    local tarPath=$1
    local dstFolder; dstFolder=$(mktemp -d) || return
    tar -C "$dstFolder" -xzf "$tarPath" >/dev/null || return

    printf '%s' "$dstFolder"
}


#-------------------------------------------------------------------------------
#
# update-and-restart()
#
# Update package list and reboot
#
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


#-------------------------------------------------------------------------------
#
# watch-daylight-gen-run-script()
#
# @deprecated - Please use dylt if possible
#
# Generate a run script for the watch-daylight.service
#
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


#-------------------------------------------------------------------------------
#
# watch-daylight-gen-unit-file()
#
# @deprecated - Please use dylt if possible
#
# Generate a unit file for the watch-daylight.service
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


#-------------------------------------------------------------------------------
#
# watch-daylight-install-service()
#
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


#-------------------------------------------------------------------------------
#
# yesno()
#
# Prompt the user for a yes/no answer
#
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


#-------------------------------------------------------------------------------
#
# zabbly-add-package-repo()
#
# Add the zabbly Incus package repository
#
zabbly-add-package-repo ()
{
	sh -c 'cat <<EOT >/etc/apt/sources.list.d/zabbly-incus-lts-6.0.sources
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/lts-6.0
Suites: $(. /etc/os-release && echo ${VERSION_CODENAME})
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc

EOT'
}


#-------------------------------------------------------------------------------
#
# zabbly-get-fingerprint()
#
# Get the GPG fingerprint for the zabbly package repo
#
zabbly-get-fingerprint ()
{
    command -v "gpg" >/dev/null || { printf '%s is required, but was not found.\n' "gpg" >&2; return 255; }
    
    # curl gpg key to a temp folder
    local url=https://pkgs.zabbly.com/key.asc 
    local tmpCurl; tmpCurl=$(mktemp --tmpdir curl.XXXXXX) || return
    curl --fail \
         --location \
         --show-error \
         --silent \
         "$url" \
         >"$tmpCurl" \
    || return
    
    # burn one call to avoid extraneous gpg init output
    gpg --show-keys <"$tmpCurl" >/dev/null || return

    # clunky script to get the second line
    {
        read -r _
        read -r line
        echo "$line"
    } < <(gpg --show-keys --fingerprint <"$tmpCurl") \
    || return
}


#-------------------------------------------------------------------------------
#
# zabbly-init()
#
# Initialize the zabbly Incus package repository
#
zabbly-init ()
{
    # shellcheck disable=SC2016
    (( $# == 0 )) || { printf 'Usage: zabbly-init\n' >&2; return 1; }

    # validate the zabbly key fingerprint
    if ! zabbly-validate-fingerprint; then
        printf 'Unable to validate fingerprint\n' >&2
        return 1
    fi

    # download the zabbly key
    if ! zabbly-save-key; then
        printf 'Unable to save zabbly key\n' >&2
        return 1
    fi

    # Add the zabbly packge repository
    if ! zabbly-add-package-repo; then
        printf 'Error adding zabbly package repo\n' >&2
        return 1
    fi
}


#-------------------------------------------------------------------------------
#
# zabbly-save-key()
#
# Download and save the zabbly GPG key
#
zabbly-save-key ()
{
	mkdir -p /etc/apt/keyrings/						# confirm folder exists
    curl -fsSL https://pkgs.zabbly.com/key.asc -o /etc/apt/keyrings/zabbly.asc
    local url=https://pkgs.zabbly.com/key.asc 
    curl --fail \
         --location \
         --show-error \
         --silent \
         --output /etc/apt/keyrings/zabbly.asc \
         "$url" \
        || return
}


#-------------------------------------------------------------------------------
#
# zabbly-validate-fingerprint()
#
# Validate the zabbly GPG key fingerprint
#
zabbly-validate-fingerprint ()
{
    local fgValid='4EFC 5906 96CB 15B8 7C73  A3AD 82CC 8797 C838 DCFD'
    local fg; fg=$(zabbly-get-fingerprint) || return

    [[ "$fgValid" == "$fg" ]] || return 1
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


#-------------------------------------------------------------------------------
#
# main()
#
# Dispatch daylight.sh subcommands when invoked as a command
#
main ()
{
    if (( $# >= 1 )); then
        cmd=$1
        shift
        case "$cmd" in 
            activate-flask-app)                       activate-flask-app "$@";;
            activate-svc)                             activate-svc "$@";;
            activate-vm)                              activate-vm "$@";;
            add-container-user)                       add-container-user "$@";;
            add-rayray)                                 add-rayray "$@";;
            add-rayray-debian)                        add-rayray-debian "$@";;
            add-ssh-to-container)                     add-ssh-to-container "$@";;
            add-superuser)                            add-superuser "$@";;
            add-to-bashrc)                            add-to-bashrc "$@";;
            add-user)                                 add-user "$@";;
            add-user-to-idmap)                        add-user-to-idmap "$@";;
            add-user-to-shadow-ids)                   add-user-to-shadow-ids "$@";;
            cat-conf-script)                          cat-conf-script "$@";;
            create-flask-app)                         create-flask-app "$@";;
            create-github-user-access-token)          create-github-user-access-token "$@";;
            create-home-filesystem)                   create-home-filesystem "$@";;
            create-loopback)                          create-loopback "$@";;
            create-lxd-user-data)                     create-lxd-user-data "$@";;
            create-pubbo-service)                     create-pubbo-service "$@";;
            create-publish-image-service)             create-publish-image-service "$@";;
            create-service-from-dist-script)          create-service-from-dist-script "$@";;
            create-static-website)                    create-static-website "$@";;
            delete-incus-instance)                   delete-incus-instance "$@";;
            delete-lxd-instance)                      delete-lxd-instance "$@";;
            download-app)                             download-app "$@";;
            download-daylight)                        download-daylight "$@";;
            download-daylight-batch)                  download-daylight-batch "$@";;
            download-dist)                            download-dist "$@";;
            download-dylt)                            download-dylt "$@";;
            download-flask-app)                       download-flask-app "$@";;
            download-flask-service)                   download-flask-service "$@";;
            download-public-key)                      download-public-key "$@";;
            shr-download-tarball)                     shr-download-tarball "$@";;
            download-svc)                             download-svc "$@";;
            download-to-temp-dir)                     download-to-temp-dir "$@";;
            download-vm)                              download-vm "$@";;
            edit-daylight)                            edit-daylight "$@";;
            etcd-create-download-url)                 etcd-create-download-url "$@";;
            etcd-download)                            etcd-download "$@";;
            etcd-download-latest)                     etcd-download-latest "$@";;
            etcd-gen-run-script)                      etcd-gen-run-script "$@";;
            etcd-gen-unit-file)                       etcd-gen-unit-file "$@";;
            etcd-get-latest-version)                  etcd-get-latest-version "$@";;
            etcd-install-latest)                      etcd-install-latest "$@";;
            etcd-setup-data-dir)                      etcd-setup-data-dir "$@";;
            gen-completion-script)                    gen-completion-script "$@";;
            gen-completion-script-batch)              gen-completion-script-batch "$@";;
            gen-daylight-completion-script)           gen-daylight-completion-script "$@";;
            gen-nginx-flask)                          gen-nginx-flask "$@";;
            gen-nginx-static)                         gen-nginx-static "$@";;
            generate-unit-file)                       generate-unit-file "$@";;
            get-bucket)                               get-bucket "$@";;
            get-container-ip)                         get-container-ip "$@";;
            get-image-base)                           get-image-base "$@";;
            get-image-name)                           get-image-name "$@";;
            get-image-repo)                           get-image-repo "$@";;
            get-service-environment-file)             get-service-environment-file "$@";;
            get-service-exec-start)                   get-service-exec-start "$@";;
            get-service-file-value)                   get-service-file-value "$@";;
            get-service-working-directory)            get-service-working-directory "$@";;
            github-app-get-client-id)                 github-app-get-client-id "$@";;
            github-app-get-id)                        github-app-get-id "$@";;
            github-create-uat)                        github-create-uat "$@";;
            github-curl)                              github-curl "$@";;
            github-detect-platform)                   github-detect-platform "$@";;
            github-download-latest-release)           github-download-latest-release "$@";;
            github-get-release-name-list)             github-get-release-name-list "$@";;
            github-shr-swap-tokens)                     github-shr-swap-tokens "$@";;
            github-is-gha-installed)                  github-is-gha-installed "$@";;
            github-release-install)                   github-release-install "$@";;
            github-curl-parse-args)                   github-curl-parse-args "$@";;
            github-release-download)                  github-release-download "$@";;
            github-release-get-asset-name)            github-release-get-asset-name "$@";;
            github-release-get-data)                  github-release-get-data "$@";;
            github-release-download-latest)           github-release-download-latest "$@";;
            github-release-get-latest-tag)            github-release-get-latest-tag "$@";;
            github-release-select-platform)           github-release-select-platform "$@";;
            github-shr-clean)                         github-shr-clean "$@";;
            github-shr-create-folder)                         github-shr-create-folder "$@";;
            github-shr-folder-name)                         github-shr-folder-name "$@";;
            github-shr-install)                       github-shr-install "$@";;
            github-shr-install-runner)                github-shr-install-runner "$@";;
            github-shr-save-uat)                          github-shr-save-uat "$@";;
	    github-shr-setup)                         github-shr-setup "$@";;
            github-shr-start)                         github-shr-start "$@";;
            github-shr-test)                          github-shr-test "$@";;
            github-test-repo)                         github-test-repo "$@";;
            github-test-repo-with-auth)               github-test-repo-with-auth "$@";;
            github-validate-uat)                      github-validate-uat "$@";;
            github-validate-uat)                      github-validate-uat "$@";;
            go-service-gen-nginx-domain-file)         go-service-gen-nginx-domain-file "$@";;
            go-service-install)                       go-service-install "$@";;
            go-service-uninstall)                     go-service-uninstall "$@";;
            go-upgrade)                               go-upgrade "$@";;
            hello)                                    hello "$@";;
            incus-config-snapshots)                   incus-config-snapshots "$@";;
            incus-create-profiles)                    incus-create-profiles "$@";;
            incus-dump-id-map)                        incus-dump-id-map "$@";;
            incus-install)                            incus-install "$@";;
            incus-instance-exists)                    incus-instance-exists "$@";;
            incus-pull-file)                          incus-pull-file "$@";;
            incus-push-file)                          incus-push-file "$@";;
            incus-remove-file)                        incus-remove-file "$@";;
            incus-set-id-map)                         incus-set-id-map "$@";;
            incus-share-folder)                       incus-share-folder "$@";;
            init-alpine)                              init-alpine "$@";;
            init-incus)                               init-incus "$@";;
            init-lxd)                                 init-lxd "$@";;
            init-nginx)                               init-nginx "$@";;
            init-rayray)                              init-rayray "$@";;
            init-rpi)                                 init-rpi "$@";;
            install-app)                              install-app "$@";;
            install-awscli)                           install-awscli "$@";;
            install-build-nightly-svc)                install-build-nightly-svc "$@";;
            install-dylt)                             install-dylt "$@";;
            install-etcd)                             install-etcd "$@";;
            install-flask-app)                        install-flask-app "$@";;
            install-fresh-daylight-svc)               install-fresh-daylight-svc "$@";;
            install-gnome-keyring)                    install-gnome-keyring "$@";;
            install-latest-httpie)                    install-latest-httpie "$@";;
            install-mssql-tools)                      install-mssql-tools "$@";;
            install-pubbo)                            install-pubbo "$@";;
            install-public-key)                       install-public-key "$@";;
            install-python)                           install-python "$@";;
            install-service)                          install-service "$@";;
            install-service-from-command)             install-service-from-command "$@";;
            install-service-from-script)              install-service-from-script "$@";;
            install-shellscript-part-handlers)        install-shellscript-part-handlers "$@";;
            install-svc)                              install-svc "$@";;
            install-venv)                             install-venv "$@";;
            install-vm)                               install-vm "$@";;
            list-apps)                                list-apps "$@";;
            list-conf-scripts)                        list-conf-scripts "$@";;
            list-funcs)                               list-funcs "$@";;
            list-host-public-keys)                    list-host-public-keys "$@";;
            list-public-keys)                         list-public-keys "$@";;
            list-services)                            list-services "$@";;
            list-vms)                                 list-vms "$@";;
            pgql-install-client)                      pgql-install-client "$@";;
            prep-filesystem)                          prep-filesystem "$@";;
            print-os-arch-vars)                       print-os-arch-vars "$@";;
            pull-app)                                 pull-app "$@";;
            pull-daylight)                            pull-daylight "$@";;
            pull-flask-app)                           pull-flask-app "$@";;
            pull-git-repo)                            pull-git-repo "$@";;
            pull-image)                               pull-image "$@";;
            pull-ssh-tarball)                         pull-ssh-tarball "$@";;
            pull-svc)                                 pull-svc "$@";;
            pull-vm)                                  pull-vm "$@";;
            pull-webapp)                              pull-webapp "$@";;
            pullAppInfo)                              pullAppInfo "$@";;
            push-app)                                 push-app "$@";;
            push-daylight)                            push-daylight "$@";;
            push-flask-app)                           push-flask-app "$@";;
            push-svc)                                 push-svc "$@";;
            push-webapp)                              push-webapp "$@";;
            replace-nginx-conf)                       replace-nginx-conf "$@";;
            run-conf-script)                          run-conf-script "$@";;
            run-service)                              run-service "$@";;
            sanitize-label)                           sanitize-label "$@";;
            setup-domain)                             setup-domain "$@";;
            source-daylight)                          source-daylight "$@";;
            source-service-environment-file)          source-service-environment-file "$@";;
            start-indexed-service)                    start-indexed-service "$@";;
            start-service)                            start-service "$@";;
            sync-add-service)                         sync-add-service "$@";;
            sync-create-unit-name)                    sync-create-unit-name "$@";;
            sync-daylight-install-service)            sync-daylight-install-service "$@";;
            sync-follow-service)                      sync-follow-service "$@";;
            sync-remove-service)                      sync-remove-service "$@";;
            sync-run-service)                         sync-run-service "$@";;
            trigger-nightly-release)                  trigger-nightly-release "$@";;
            trigger-nightly-release-batch)            trigger-nightly-release-batch "$@";;
            sys-start)                                sys-start "$@";;
            uninstall-etcd)                           uninstall-etcd "$@";;
            untar-to-temp-folder)                     untar-to-temp-folder "$@";;
            update-and-restart)                       update-and-restart "$@";;
            watch-daylight-gen-run-script)            watch-daylight-gen-run-script "$@";;
            watch-daylight-gen-unit-file)             watch-daylight-gen-unit-file "$@";;
            watch-daylight-install-service)           watch-daylight-install-service "$@";;
            zabbly-init)                              zabbly-init "$@";;
            *) printf 'Unknown command: %s \n' "$cmd" >&2; return 1;;
        esac
    fi
}

(return 0 2>/dev/null) || main "$@"
