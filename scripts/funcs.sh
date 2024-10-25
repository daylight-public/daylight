# Get raw JSON for a github app
github-get-app-data () 
{ 
    appSlug=$1;
    curl --silent \
	 --location \
	 "https://api.github.com/apps/$appSlug"
}


# Get github app data and package into an assoc array
# For fields that aren't in the assoc array, use github-get-app-data
github-get-app-info () 
{ 
	local -n _aa=$1
	appSlug=$2

	local -a args
	read -ra args < <(github-get-app-data "$appSlug" \
	                  | jq -r '[.id, .client_id] | @tsv')
	_aa['id']=${args[0]}
	_aa['client_id']=${args[1]}
}


github-get-device-code-data ()
{
	clientId=$1
	curl --silent \
	     --header 'Accept: application/json' \
	     --data '' \
	     "https://github.com/login/device/code?client_id=$clientId"
}


github-get-device-code-info ()
{
	# shellcheck disable=SC2178
	local -n _aa=$1
	local clientId=$2

	local -a args
	read -ra args < <(github-get-device-code-data "$clientId" \
	                  | jq -r '[.device_code, .expires_in, .interval, .user_code, .verification_uri] | @tsv')
	_aa['device_code']=${args[0]}
	_aa['expires_in']=${args[1]}
	_aa['interval']=${args[2]}
	_aa['user_code']=${args[3]}
	_aa['verification_url']=${args[4]}
}

