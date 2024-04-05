#! /usr/bin/env bash

# Get etcd version
# VER=$(curl -L -s https://api.github.com/repos/etcd-io/etcd/releases/latest | jq -r .tag_name)


download-release ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: download-release $downloadUrl\n' >&2; return 1; }
    local downloadUrl=$1
    local releaseFolder=/tmp
    local releaseFile=etcd-release.tar.gz
    curl --location --silent "$downloadUrl" --output-dir "$releaseFolder" --output "$releaseFile"
    local releasePath="$releaseFolder/$releaseFile"
    printf '%s' "$releasePath"
}


get-download-url ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-download-url $version\n' >&2; return 1; }
    local version=$1

    local GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
    local downloadUrl=${GITHUB_URL}/${version}/etcd-${version}-linux-amd64.tar.gz
    printf '%s' "$downloadUrl"
}


get-latest-version ()
{
    command -v "jq" >/dev/null || { printf '%s is required, but was not found.\n' "jq"; return 255; }
    local VER
    
    VER=$(curl -L -s https://api.github.com/repos/etcd-io/etcd/releases/latest | jq -r .tag_name)
    printf '%s' "$VER"
}


install-release ()
{
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: install-release $releasePath $installFolder\n' >&2; return 1; }
    local releasePath=$1
    local installFolder=$2
    [[ -f "$releasePath" ]] || { echo "Non-existent path: $releasePath" >&2; return 1; }
    [[ -d "$installFolder" ]] || { printf 'Non-existent folder: %s\n' "$installFolder" >&2; return 1; }
    tar --gunzip --extract --file "$releasePath" --directory "$installFolder" --strip-components=1
}


setup-data-dir ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: setup-data-dir $dataDir\n' >&2; return 1; }
    local dataDir=$1    
    sudo mkdir -p "$dataDir"
    sudo chown -R ubuntu:ubuntu "$dataDir"
}


# Create download URL
main ()
{
    local version; version=$(get-latest-version) || return
    local downloadUrl; downloadUrl=$(get-download-url "$version") || return
    local releasePath; releasePath=$(download-release "$downloadUrl") || return
    local installFolder=/opt/etcd
    sudo mkdir -p $installFolder
    sudo chown -R ubuntu:ubuntu $installFolder
    install-release "$releasePath" "$installFolder"
    setup-data-dir /var/lib/etcd
}

main $@

# Curl the tarball

# Untar the tarball; that's all it takes to install
# sudo mkdir -p /opt/etcd/
# sudo chown -R ubuntu:ubuntu /opt/etcd/
# tar -zxf /tmp/etcd-${VER}-linux-amd64.tar.gz -C /opt/etcd/ --strip-components=1

# Create etcd data dir + make ubuntu owner
# sudo mkdir -p /var/lib/etcd
# sudo chown -R ubuntu:ubuntu /var/lib/etcd
