dylt-get-all-vms ()
{
	# shellcheck disable=SC2016
	(( $# == 1 )) || { printf 'Usage: get-all-vms.sh $user\n' >&2; return 1; }
	declare -F ec >/dev/null || { printf 'Unknown function: %s\n' "ec"; return 1; }
	local user=$1
	while IFS= read -r key; do
		keyPrefix=${key%/host}
		vm=${keyPrefix#/$user/vm/}
		echo $vm;
	done < <(ec get --keys-only --prefix /mc15/vm -w json | jq -r '.kvs[].key | @base64d')
}
