#! /usr/bin/env bash

upload-scripts ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: upload-scripts $ip\n' >&2; return 1; }
    local ip=$1
    [[ -f "./install-etcd.sh" ]] || { echo "Non-existent path: ./install-etcd.sh" >&2; return 1; }
    [[ -f "./reset-etcd.sh" ]] || { echo "Non-existent path: ./reset-etcd.sh" >&2; return 1; }
    [[ -f "./uninstall-etcd.sh" ]] || { echo "Non-existent path: ./uninstall-etcd.sh" >&2; return 1; }

    scp ./install-etcd.sh "ubuntu@$ip:/home/ubuntu/tmp/"
    scp ./reset-etcd.sh "ubuntu@$ip:/home/ubuntu/tmp/"
    scp ./uninstall-etcd.sh "ubuntu@$ip:/home/ubuntu/tmp/"
}

main ()
{
    upload-scripts $@
}


main "$@"