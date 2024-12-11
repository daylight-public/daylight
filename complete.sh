# Some completions use a bash function for their source of words.
# This is actually hard to do.
# 
# compgen does have a -F option. It's natural to assume the compgen -F function lets you use
# a function as a word source, just as -W lets you use an array of words, etc. But this isn't
# the case. -F has a very strange implementation that is never useful. It only exists because
# complete has an -F option, which is in fact useful, and the authors wanted complete and 
# compgen have the same set of options. So compgen has at least two options -- -F and -C -- 
# that are not useful, and only exist so that compgen and complete's options match. You could
# say that they exist for - ahem - completeness.
#
# We definitely want to be able to use bash functions or caommands as completion word sources.
# If we can't use compgen -F, or anything that already exists, we'll need to build the support
# ourselves. We'll build around compgen -W. compgen -W is great at taking an array of words, and
# the current partial word, and returning all matches.
#
# That gets us most of the way there. Unfortunately compgen -W returns a list of words one per line,
# and complete & COMPREPLY prefer an array. So we need to convert compgen's response into an array using
# mapfile. This is a bit confusing, since the initial source of words for compgen is typically a one-per-line
# list of words that also needs to be converted to mapfile. So the basic flow looks like this:
#   - Call function or command to produce list of words
#   - Convert wordlist to an array with mapfile
#   - Call compgen to filter word array on COMP_CWORD
#   - Convert filtered wordlist to an array with mapfile
#   - Set COMPREPLY to array
#
# The last two steps are naturally combined, because the last mapfile can take COMPREPLY as an argument. But the other
# steps are a bit challenging to combine, since functions can't return arrays and passing arrays as namerefs is not 
# composable. So what's the best way to make it easy to map an arbitrary command's output to an array, then filter it
# with compgen, then mapfile to COMPREPLY? Maybe something like ...
#
#	mapfile -t COMREPLY <(cmd | func-that-mapfiles-stdin-and-calls compgen -W)
#
# I'm not sure if there's any way to reduce this. But it might be worth trying to play with

# write stdin to tmpfile
# map tmpfile to an array (maybe tee can handle this, maybe not)
# compgen array into a tmpfile
# mapfile tmpfile into COMPREPLY
read-into-compreply ()
{
	local curr=${COMP_WORDS[COMP_CWORD]}
	local last=${COMP_WORDS[COMP_CWORD-1]}

	local tmpStdin; tmpStdin=$(mktemp --tmpdir bc.ric.stdin.XXXXXX) || return
	cat >"tmpStdin" || return 
	local words; mapfile -t words <"tmpStdin" || return
	local tmpCompgen; tmpCompgen=$(mktemp --tmpdir fc.ric.compgen.XXXXXX) || return
	compgen -W "${words[*]}" -- "$curr" >"$tmpCompgen" || return
	mapfile -t COMPREPLY <"$tmpCompgen" || return
}


_daylight-sh ()
{
	local curr=$2
	local last=$3

	print-comp-args "$@"
	local mainCmds=(\
		activate-flask-app \
		activate-svc \
		activate-vm \
		add-container-user \
		add-ssh-to-container \
		add-superuser \
		add-user \
		add-user-to-idmap \
		add-user-to-shadow-ids \
		cat-conf-script \
		create-flask-app \
		create-github-user-access-token \
		create-home-filesystem \
		create-loopback \
		create-lxd-user-data \
		create-pubbo-service \
		create-publish-image-service \
		create-service-from-dist-script \
		create-static-website \
		create-temp-file \
		create-temp-folder \
		daylight \
		delete-lxd-instance \
		download-app \
		download-daylight \
		download-dist \
		download-dylt \
		download-flask-app \
		download-flask-service \
		download-public-key \
		download-shr-tarball \
		download-svc \
		download-to-temp-dir \
		download-vm \
		ec \
		edit-daylight \
		error \
		error_log \
		etcd-download-latest \
		etcd-download-release \
		etcd-gen-join-script \
		etcd-gen-run-script \
		etcd-gen-unit-file \
		etcd-get-download-url \
		etcd-get-latest-version \
		etcd-install-latest \
		etcd-install-release \
		etcd-install-service \
		etcd-setup-data-dir \
		events \
		gen-nginx-flask \
		gen-nginx-static \
		generate-unit-file \
		get-bucket \
		get-container-ip \
		get-image-base \
		get-image-name \
		get-image-repo \
		get-service-environment-file \
		get-service-exec-start \
		get-service-file-value \
		get-service-working-directory \
		getVmName \
		github-create-user-access-token \
		github-curl \
		github-curl-post \
		github-download-latest-release \
		github-get-app-client-id \
		github-get-app-data \
		github-get-app-info \
		github-get-latest-release-tag \
		github-get-release-data \
		github-get-release-name-list \
		github-get-release-package-data \
		github-get-release-package-info \
		github-get-releases-url-path \
		github-install-latest-release \
		github-test-repo \
		github-test-repo-with-auth \
		go-service-gen-nginx-domain-file \
		go-service-gen-run-script \
		go-service-gen-stop-script \
		go-service-gen-unit-file \
		go-service-install \
		go-service-uninstall \
		hello \
		http \
		incus-create-ssh-profile \
		incus-create-www-profile \
		incus-pull-file \
		incus-push-file \
		incus-remove-file \
		init-lxd \
		init-nginx \
		install-app \
		install-awscli \
		install-dylt \
		install-etcd \
		install-flask-app \
		install-fresh-daylight-svc \
		install-gnome-keyring \
		install-latest-httpie \
		install-mssql-tools \
		install-pubbo \
		install-public-key \
		install-python \
		install-service \
		install-service-from-command \
		install-service-from-script \
		install-shellscript-part-handlers \
		install-shr-token \
		install-svc \
		install-venv \
		install-vm \
		list-apps \
		list-conf-scripts \
		list-funcs \
		list-git-repos \
		list-public-keys \
		list-services \
		list-shr-entries \
		list-vms \
		log \
		lxd-dump-id-map \
		lxd-instance-exists \
		lxd-set-id-map \
		lxd-share-folder \
		mkdir \
		modules-enabled \
		prep-filesystem \
		prep-service \
		pull-app \
		pull-daylight \
		pull-flask-app \
		pull-git-repo \
		pull-image \
		pull-ssh-tarball \
		pull-svc \
		pull-vm \
		pull-webapp \
		pullAppInfo \
		push-app \
		push-daylight \
		push-flask-app \
		push-svc \
		push-webapp \
		replace-nginx-conf \
		restart-nginx \
		run-conf-script \
		run-service \
		setup-domain \
		socketFolder \
		source-daylight \
		source-service-environment-file \
		start-indexed-service \
		start-service \
		stream \
		streams \
		sys-start \
		uninstall-etcd \
		untar-to-temp-folder \
		update-and-restart \
		watch-daylight-gen-run-script \
		watch-daylight-gen-unit-file \
		watch-daylight-install-service \
		worker_processes \
		www-data \
		yesno \
	)

	local lastCmd=${last##*/}
	case "$lastCmd" in
		daylight.sh)
			mapfile -t COMPREPLY < <(compgen -W "${mainCmds[*]}" -- "$curr")
			;;
	esac
	exec 10>&-
}


print-comp-args ()
{
	exec 10>/tmp/daylight.sh.fc.txt
	printf 'cmd=%q last=%q curr=%q\n' "$1" "$3" "$2">&10
	printf '%-25s %s\n' COMP_WORDS "$(printf '<%q>' "${COMP_WORDS[@]}")" >&10
	printf '%-25s %d\n' COMP_CWORD "$COMP_CWORD" >&10
	# shellcheck disable=SC2016
	printf '%-25s %s\n' '${COMP_WORDS[COMP_CWORD]}' "${COMP_WORDS[COMP_CWORD]}" >&10
	printf '%-25s %s\n' '${COMP_WORDS[COMP_CWORD-1]}' "${COMP_WORDS[COMP_CWORD-1]}" >&10
	printf '%-25s %d\n' COMP_KEY "$COMP_KEY" >&10
	printf '%-25s %s\n' COMP_LINE "$COMP_LINE" >&10
	printf '%-25s %d\n' COMP_POINT "$COMP_POINT" >&10
	printf '%-25s %d\n' COMP_TYPE "$COMP_TYPE" >&10
	echo >&10
}


complete -F _daylight-sh daylight.sh
