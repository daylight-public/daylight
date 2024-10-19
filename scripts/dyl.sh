#! /usr/bin/env bash

main ()
{
    if (( $# >= 1 )); then
        cmd=$1
        shift 1
        case "$cmd" in
            cp)     ./scp.sh "$@";;
            exec)	./ssh-into-vm.sh "$@";;
            shell)	./ssh-into-vm.sh "$@";;
            *) printf 'Unknown command: %s \n' "$cmd";;
        esac
    fi
}

main "$@"