_main () 
{
	# shellcheck disable=SC2016
	# shellcheck disable=SC2016
	{ (( $# >= 1 )) && (( $# <= 2 )); } || { printf 'Usage: $fnName [$scriptPath]\n' >&2; return 1; }
    local fnName=$1
	declare -F $fnName >/dev/null || { printf 'Unknown function: %s\n' "$fnName"; return 1; }
    local scriptPath=${2:-"./$fnName.sh"}
	[[ ! -f "$scriptPath" ]] || { printf 'Path exists: %s\n' $scriptPath >&2; return 1; }

    touch "$scriptPath"
    chmod 777 "$scriptPath"

	# preamble
	printf '%s\n' '#! /usr/bin/env bash' '' 'main ()' >>"$scriptPath"
	
	# function body
	if read -r; then
		cat >>"$scriptPath"
	fi < <(declare -f -- "$fnName")
    
	# postamble
	printf '%s\n' '' 'main "$@"' >>"$scriptPath"
}

_main "$@"
