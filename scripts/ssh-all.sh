main () 
{ 
    # shellcheck disable=SC2016
    (( $# >= 2 )) || { printf 'Usage: ssh-all $user $arg [$arg ... $arg]\n' >&2; return 1; }
    local user=$1
    shift 1
    # while/read uses a {fd} idiom here to dup stdin. https://mywiki.wooledge.org/BashFAQ/089
    while read -r -u "$fd" host; do
        printf 'Connecting to %s ...' "$host"
        ssh -n -o ConnectTimeout=300 "ubuntu@$host" "$@"
    done {fd}< <(./list-vm-hosts.sh "$user" | jq -r '.[].host')
    # Delete the fd
    exec {fd}<&-
}

main "$@";
