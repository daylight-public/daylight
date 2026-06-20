#! /usr/bin/env bash

list-funcs ()
{
	local line nextline
	local rxFunc='^[A-Za-z][A-Za-z0-9_-]*[[:blank:]]*\(\)$'
	local rxBrace='^\{$' 
	IFS= read -r line || return
	IFS= read -r nextline || return
	while :; do
		if [[ $line =~ $rxFunc ]] && [[ $nextline =~ $rxBrace ]]; then
			local func=${line%% ()}
			printf '%s\n' "$func"
		fi
		line=$nextline
		IFS= read -r nextline || return
	done
}
 

gen-completion-script ()
{ 
	if [[ -t 0 ]]; then
		printf '\nstdin is a terminal; please redirect input from stdin.\n\n';
		return 0
	fi

	# beggining of script
	cat <<- END
	_daylight-sh ()
	{
	    local curr=\$2
	    local last=\$3

	    local mainCmds=(\\
	END

	while read -r func; do
		printf '        %s \\\n' "$func"
	done < <(list-funcs)

	# end of script
	cat <<- END
	    )

	    # Trim everything up to + including the first slash
	    local lastCmd=\${last##*/}
	    case "\$lastCmd" in
	        daylight.sh)
	            # Typical mapfile + comgen -W idiom
	            mapfile -t COMPREPLY < <(compgen -W "\${mainCmds[*]}" -- "\$curr")
	            ;;
	    esac\n
	}
	
	complete -F _daylight-sh daylight.sh
	END
}

(return 0 2>/dev/null) || gen-completion-script "$@"
