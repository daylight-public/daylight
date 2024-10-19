#! /usr/bin/env bash

main ()
{
    [[ -n "$vm" ]] || { echo 'Please set $vm' >&2; return 1; }
    ssh-keygen -R $vm
    # rsync files to the remote host
    [[ -d "./etc/files" ]] || { printf 'Non-existent folder: %s\n' "./etc/files" >&2; return 1; }
    rsync -ah --info=progress2 -e "ssh -o StrictHostKeyChecking=no" ./etc/files/ root@$vm:/
    [[ -f "./etc/run-on-host.sh" ]] || { echo "Non-existent path: ./etc/run-on-host.sh" >&2; return 1; }
    scp ./etc/run-on-host.sh root@$vm:/root/
    ssh root@$vm
}

main "$@"