#! /usr/bin/env bash

main ()
{
    ec get --prefix /mc15/vm -w json | jq '[ .kvs[] | select(.key | @base64d | contains("host")) | {"key": .key | @base64d, "value": .value | @base64d} ]'
}

main "$@"
