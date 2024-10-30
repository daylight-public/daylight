#! /usr/bin/env bash

main () 
{ 
	# shellcheck disable=SC2016
	(( $# == 1 )) || { printf 'Usage: create-user-access-token.sh $clientId\n' >&2; return 1; }
	clientId=$1
	
	# Get devide code data
	local -a dcData
	read -r -a dcData < <(curl --silent \
	                           --location \
							   --header 'Accept: application/json' \
							   --data '' \
							   "https://github.com/login/device/code?client_id=$clientId" accept:application/json \
		                  | jq -r '[.device_code, .user_code, .verification_uri] | @tsv')
	device_code=${dcData[0]}
	user_code=${dcData[1]}
	verification_uri=${dcData[2]}

	# printf '%s' "$user_code" | pbcopy
	# printf "Please copy/paste %s into the form at %s. (It's already in your clipboard. Yw.)" "%user_code" "verification_uri" 1>&2
	# open "$verification_uri"
	printf '%-20s%s\n' 'User Code' "$user_code"
	printf '%-20s%s\n' "Verification Url" "$verification_uri"
	# Copy user code to clipboard if possible
	if command -v pbcopy; then
		pbcopy <<< "$user_code"
		printf 'User Code %s copied to clipboard.\n' "$user_code"
	fi
	# Open url if possible
	if command -v open; then
		open "$verification_uri"
	else
		printf 'Please enter user code %s in your browser at %s\n' "$user_code" "$verification_uri"
	fi
	echo
	printf '(Hit Enter to proceed ...)' 1>&2
	read -r

	# Get the access code
	grant_type=urn:ietf:params:oauth:grant-type:device_code
	local -a atData	
	read -ra atData < <(http --body post https://github.com/login/oauth/access_token "client_id=$clientId" "device_code=$device_code" "grant_type=$grant_type" accept:application/json \
	                    | jq -r '[.access_token, .refresh_token] | @tsv')
	access_token=${atData[0]}
	# refresh_token=${atData[1]}
	printf '%s' "$access_token"
#    source <(python3 -m parse_query_string --names access_token refresh_token --output env <<< "$s")
}

main "$@"
