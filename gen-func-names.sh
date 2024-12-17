gen-func-names () 
{ 
    printf '\tlocal mainCmds=(\\\n%s\n\t)\n' "$(printf '\t\t%s \\\n' "${funcnames[@]}")" | pbcopy
}
