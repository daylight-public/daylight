#! /usr/bin/env bash

main ()
{
    [[ -n "$vm" ]] || { echo 'Please set $vm' >&2; return 1; }
    ssh-keygen -R $vm
    ssh -vvvv root@$vm 'apt update -y; apt upgrade -y; printf "Done - %d\n" $?;' || echo 'ssh failed (exit code %d)\n' $?
    echo
    echo "Done - $0"
}

main "$@"