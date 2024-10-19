#! /usr/bin/env bash

if read -r
then
	printf '%s\n' '#!/usr/bin/env bash' "" 'main()'
	cat
	printf '%s\n' "" 'main "$@"'
fi < <(declare -f "$1")
