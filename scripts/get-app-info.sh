#! /usr/bin/env bash


get-app-info ()
{
    # shellcheck disable=SC2016
    (( $# == 1 )) || { printf 'Usage: get-app-info $infovar\n' >&2; return 1; }
    local -n _info; _info=$1

    _info[test]="1 2 3"
}

main ()
{
    declare -A info
    get-app-info info
    declare -p info
}


main "$@"