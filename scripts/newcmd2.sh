#! /usr/bin/env bash

fnName=$1
echo "#! /usr/bin/env bash"
echo
pattern="$(printf '^%q$' "$fnName ()")"
IFS=''
while read -r line; do
	if [[ $line =~ $pattern ]]; then
		printf 'main ()\n'
	else
		printf '%s\n' "$line"
	fi
done < <(declare -f "$fnName")
echo
echo 'main "$@"' 
