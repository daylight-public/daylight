#! /usr/bin/env bash

main ()
{
    [[ -n "$vm" ]] || { echo 'Please set $vm' >&2; return 1; }
    ssh-keygen -R $vm
    ssh -vvvv root@$vm <./mini-run-on-host.sh || echo 'ssh failed (exit code %d)\n' $?
    echo
    echo "Done"
}

main "$@"