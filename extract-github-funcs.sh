extract-func ()
{
    local script=$1
    local func_name=$2

    [[ -f "$script" ]] || { printf 'Error: script not found: %s\n' "$script" >&2; return 1; }
    [[ -n "$func_name" ]] || { printf 'Error: function name is required\n' >&2; return 1; }

    local preamble=""
    local in_func=false
    local found=false
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if ! $in_func; then
            if [[ "$line" == "$func_name ()" ]]; then
                printf '%s' "$preamble"
                printf '%s\n' "$line"
                in_func=true
                found=true
            elif [[ "$line" == '#'* ]]; then
                preamble+="$line"$'\n'
            elif [[ -z "$line" ]]; then
                preamble=""
            else
                preamble=""
            fi
        else
            printf '%s\n' "$line"
            if [[ "$line" == '}' ]]; then
                printf '\n'
                return 0
            fi
        fi
    done < "$script"

    if ! $found; then
        printf 'Error: function "%s" not found in %s\n' "$func_name" "$script" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    daylight_script="$script_dir/daylight.sh"

    [[ -f "$daylight_script" ]] || { printf 'Error: daylight.sh not found at %s\n' "$daylight_script" >&2; exit 1; }

    printf '# github-utils.sh -- generated from daylight.sh on %s. Do not edit directly.\n' "$(date)"
    printf '\n'

    for func in \
        github-app-get-client-id \
        github-app-get-data \
        github-app-get-id \
        github-app-get-info \
        github-create-flags \
        github-create-url \
        github-create-user-access-token \
        github-curl \
        github-curl-post \
        github-detect-platform \
        github-download-latest-release \
        github-get-release-data \
        github-get-release-name-list \
        github-get-release-package-data \
        github-get-release-package-info \
        github-curl-parse-args \
        github-release-create-url-path \
        github-release-download \
        github-release-download-latest \
        github-release-get-asset-name \
        github-release-get-data \
        github-release-get-latest-tag \
        github-release-get-package-data \
        github-release-get-package-info \
        github-release-install \
        github-release-install-latest \
        github-release-list \
        github-release-list-platforms \
        github-release-select \
        github-release-select-platform \
        github-test-repo \
        github-test-repo-with-auth; do
        extract-func "$daylight_script" "$func"
    done
fi
