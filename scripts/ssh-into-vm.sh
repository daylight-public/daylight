main () 
{ 
    # shellcheck disable=SC2016
    (( $# >= 1 )) || { printf 'Usage: ssh-into-vm $user $name [$cmd]\n' >&2; return 1; }
    # shellcheck disable=SC2016
    [[ -n "$DYLT_USER" ]] || { echo 'Please set $DYLT_USER' >&2; return 1; }
    local user=$DYLT_USER
    local name=$1
    shift 1
    local host; host=$(./get-host.sh "$user" "$name") || return
    ssh -t "ubuntu@$host" "$@"
}

main "$@";
