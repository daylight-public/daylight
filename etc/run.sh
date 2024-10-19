#! /usr/bin/env bash

main ()
{
    [[ -n "$vm" ]] || { echo 'Please set $vm' >&2; return 1; }
    ssh-keygen -R $vm
    # rsync files to the remote host
    [[ -d "./etc/files" ]] || { printf 'Non-existent folder: %s\n' "./etc/files" >&2; return 1; }
    rsync -ah --info=progress2 -e "ssh -o StrictHostKeyChecking=no" ./etc/files/ root@$vm:/
    [[ -f "./etc/run-on-host.sh" ]] || { echo "Non-existent path: ./etc/run-on-host.sh" >&2; return 1; }
    ssh -vvvv root@$vm <./etc/run-on-host.sh
    sleep 5
    echo
    echo "VM initialization is now complete. We did it!"
    echo
    read -r -p "One more step - hit <Enter> to ssh in and run 'passwd' to change the weak host password"
    echo "If the system is rebooting, there might be a slight delay before connecting"
    ssh -o ConnectTimeout=600 ubuntu@$vm "sudo ls /"
    ssh -o ConnectTimeout=600 root@$vm
}

main "$@"