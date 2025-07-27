#! /usr/bin/env bash

main ()
{
	printf '%s\n' "Installing daylight ..."
	local downloadFolder=/opt/bin/
	# Confirm downloadFolder exists
	if [[ ! -d $downloadFolder ]]; then
		printf 'Download folder %s does not exist\n' "$downloadFolder"
		exit 1
	fi

	# Download script from github
	url=https://raw.githubusercontent.com/daylight-public/daylight/main/daylight.sh
	curl --remote-name --output-dir "$downloadFolder" "$url" || { local rc=$?; printf "Failed downloading & installing daylight.sh (%d)\n" $rc; exit $rc; }

	printf '%s\n' Done.
}

main "$@"
