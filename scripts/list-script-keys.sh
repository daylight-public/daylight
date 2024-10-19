#! /usr/bin/env bash

main ()
{ 
    ec get --keys-only --prefix /scripts | grep -v -E '^$'
}

main "$@"
