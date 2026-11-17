#! /usr/bin/env bash

SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
source "$SCRIPT_DIR/test-utils.sh" || exit 1
source "$SCRIPT_DIR/../daylight.sh" || exit 1


#-------------------------------------------------------------------------------
#
# check-eq()
#
# @internal
# Compare an actual value to an expected one and print PASS or FAIL
# Usage: check-eq desc expected actual
#
check-eq()
{
    local desc=$1 expected=$2 actual=$3
    if [[ $actual != "$expected" ]]; then
        printf '  FAIL (%s): expected "%s", got "%s"\n' "$desc" "$expected" "$actual"
        return 1
    fi
    printf '  PASS\n'
}


test-variants-lists-all-three()
{
    local got; got=$(k8s-get-variants | sort | tr '\n' ' ')
    check-eq variants 'k3s kind rke2 ' "$got"
}


test-latest-version-from-redirect()
{
    curl() { printf 'https://github.com/k3s-io/k3s/releases/tag/v9.9.9+k3s1'; }
    local got; got=$(k8s-get-latest-version --variant k3s)
    unset -f curl
    check-eq latest-tag 'v9.9.9+k3s1' "$got"
}


test-latest-version-fails-without-a-tag()
{
    curl() { printf 'https://github.com/k3s-io/k3s/releases'; }
    fail-check no-tag 'Could not determine the latest k3s release' k8s-get-latest-version --variant k3s
    local rc=$?
    unset -f curl
    return $rc
}


test-resolve-variant-defaults-to-k3s()
{
    local got; got=$(unset DAYLIGHT_K8S_VARIANT; k8s-resolve-variant '')
    check-eq default k3s "$got"
}


test-resolve-variant-honors-env()
{
    local got; got=$(DAYLIGHT_K8S_VARIANT=kind k8s-resolve-variant '')
    check-eq env kind "$got"
}


test-resolve-variant-rejects-unknown()
{
    fail-check unknown-variant 'Unknown variant: minikube' k8s-resolve-variant minikube
}


test-release-names()
{
    local rc=0 got
    got=$(k8s-create-release-name --variant kind --platform linux-amd64); check-eq kind-amd64 kind-linux-amd64 "$got" || rc=1
    got=$(k8s-create-release-name --variant kind --platform darwin-arm64); check-eq kind-darwin kind-darwin-arm64 "$got" || rc=1
    got=$(k8s-create-release-name --variant k3s --platform linux-amd64); check-eq k3s-amd64 k3s "$got" || rc=1
    got=$(k8s-create-release-name --variant k3s --platform linux-arm64); check-eq k3s-arm64 k3s-arm64 "$got" || rc=1
    got=$(k8s-create-release-name --variant k3s --platform linux-arm); check-eq k3s-arm k3s-armhf "$got" || rc=1
    got=$(k8s-create-release-name --variant rke2 --platform linux-amd64); check-eq rke2-amd64 rke2.linux-amd64.tar.gz "$got" || rc=1
    return $rc
}


test-release-names-reject-unsupported()
{
    local rc=0
    fail-check k3s-darwin 'linux only' k8s-create-release-name --variant k3s --platform darwin-arm64 || rc=1
    fail-check rke2-arm 'Unsupported architecture' k8s-create-release-name --variant rke2 --platform linux-arm || rc=1
    return $rc
}


test-download-urls()
{
    local rc=0 got
    got=$(k8s-create-download-url --variant k3s --version v1.2.3+k3s1 --platform linux-arm64)
    check-eq k3s-url 'https://github.com/k3s-io/k3s/releases/download/v1.2.3+k3s1/k3s-arm64' "$got" || rc=1
    got=$(k8s-create-download-url --variant kind --version v0.9.0 --platform linux-amd64)
    check-eq kind-url 'https://github.com/kubernetes-sigs/kind/releases/download/v0.9.0/kind-linux-amd64' "$got" || rc=1
    got=$(k8s-create-download-url --variant rke2 --version v1.2.3+rke2r1 --platform linux-amd64)
    check-eq rke2-url 'https://github.com/rancher/rke2/releases/download/v1.2.3+rke2r1/rke2.linux-amd64.tar.gz' "$got" || rc=1
    return $rc
}


test-gen-config-k3s-server-external-etcd()
{
    local cfg; cfg=$(k8s-gen-config --variant k3s --role server \
        --datastore-endpoint https://10.0.0.1:2379,https://10.0.0.2:2379 \
        --datastore-cafile /etc/etcd/tls/ca.crt --datastore-certfile /etc/etcd/tls/client.crt --datastore-keyfile /etc/etcd/tls/client.key \
        --token-file /etc/rancher/k3s/token --tls-san k8s.example.com --flannel-backend wireguard-native --disable traefik)
    local rc=0 want
    for want in 'datastore-endpoint: "https://10.0.0.1:2379,https://10.0.0.2:2379"' \
                'datastore-cafile: "/etc/etcd/tls/ca.crt"' \
                'datastore-certfile: "/etc/etcd/tls/client.crt"' \
                'datastore-keyfile: "/etc/etcd/tls/client.key"' \
                'token-file: "/etc/rancher/k3s/token"' \
                'flannel-backend: "wireguard-native"' \
                'write-kubeconfig-mode: "0600"' \
                '  - "traefik"' \
                '  - "k8s.example.com"'; do
        [[ $cfg == *"$want"* ]] || { printf '  FAIL (gen-config): missing line: %s\n' "$want"; rc=1; }
    done
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


test-gen-config-refuses-plain-http-datastore()
{
    local rc=0
    fail-check plain-http 'Refusing a plain http datastore' \
        k8s-gen-config --variant k3s --datastore-endpoint http://10.0.0.1:2379 || rc=1
    local cfg; cfg=$(k8s-gen-config --variant k3s --datastore-endpoint http://10.0.0.1:2379 --insecure-datastore)
    [[ $cfg == *'datastore-endpoint: "http://10.0.0.1:2379"'* ]] || { printf '  FAIL (insecure): flag did not allow http\n'; rc=1; }
    return $rc
}


test-gen-config-https-datastore-needs-ca()
{
    local rc=0
    fail-check no-ca 'needs --datastore-cafile' \
        k8s-gen-config --variant k3s --datastore-endpoint https://10.0.0.1:2379 || rc=1
    fail-check cert-without-key 'go together' \
        k8s-gen-config --variant k3s --datastore-endpoint https://10.0.0.1:2379 --datastore-cafile /ca --datastore-certfile /c || rc=1
    return $rc
}


test-gen-config-never-prints-a-token()
{
    local cfg; cfg=$(k8s-gen-config --variant k3s --role server --token-file /run/secret)
    [[ $cfg == *'token-file: "/run/secret"'* ]] || { printf '  FAIL (token): token-file line missing\n'; return 1; }
    [[ $cfg != $'token: '* && $cfg != *$'\ntoken: '* ]] || { printf '  FAIL (token): config has an inline token\n'; return 1; }
    printf '  PASS\n'
}


test-gen-config-agent-needs-server()
{
    fail-check agent-no-server 'An agent needs --server' k8s-gen-config --variant k3s --role agent
}


test-gen-config-agent-with-server()
{
    local cfg; cfg=$(k8s-gen-config --variant rke2 --role agent --server https://k8s.example.com:9345 --token-file /t)
    [[ $cfg == *'server: "https://k8s.example.com:9345"'* ]] || { printf '  FAIL (agent-server): no server line\n'; return 1; }
    [[ $cfg != *'datastore-endpoint'* ]] || { printf '  FAIL (agent-server): agent got a datastore\n'; return 1; }
    printf '  PASS\n'
}


test-gen-config-rke2-rejects-datastore()
{
    fail-check rke2-datastore 'k3s only' k8s-gen-config --variant rke2 --datastore-endpoint https://10.0.0.1:2379
}


test-gen-config-rejects-kind()
{
    fail-check kind-config 'supports k3s and rke2' k8s-gen-config --variant kind
}


test-gen-unit-file()
{
    local server; server=$(k8s-gen-unit-file --role server)
    local agent; agent=$(k8s-gen-unit-file --role agent)
    [[ $server == *'ExecStart=/usr/local/bin/k3s server'* ]] || { printf '  FAIL (unit): server ExecStart\n'; return 1; }
    [[ $agent == *'ExecStart=/usr/local/bin/k3s agent'* ]] || { printf '  FAIL (unit): agent ExecStart\n'; return 1; }
    [[ $server == *'WantedBy=multi-user.target'* ]] || { printf '  FAIL (unit): no Install section\n'; return 1; }
    printf '  PASS\n'
}


test-service-names()
{
    local rc=0 got
    got=$(k8s-get-service-name k3s server); check-eq k3s-server k3s "$got" || rc=1
    got=$(k8s-get-service-name k3s agent); check-eq k3s-agent k3s-agent "$got" || rc=1
    got=$(k8s-get-service-name rke2 server); check-eq rke2-server rke2-server "$got" || rc=1
    got=$(k8s-get-service-name rke2 agent); check-eq rke2-agent rke2-agent "$got" || rc=1
    fail-check kind-service 'no service' k8s-get-service-name kind server || rc=1
    return $rc
}


test-kubeconfig-paths()
{
    local rc=0 got
    got=$(k8s-get-kubeconfig-path --variant k3s); check-eq k3s-path /etc/rancher/k3s/k3s.yaml "$got" || rc=1
    got=$(k8s-get-kubeconfig-path --variant rke2); check-eq rke2-path /etc/rancher/rke2/rke2.yaml "$got" || rc=1
    return $rc
}


test-verify-checksum()
{
    local dir; dir=$(mktemp --directory --tmpdir k8s-test.XXXXXX) || return 1
    local rc=0
    printf 'hello' >"$dir/k3s"
    local sum; sum=$(sha256sum "$dir/k3s" | awk '{ print $1 }')

    printf '%s  k3s\n%s  other\n' "$sum" "deadbeef" >"$dir/multi.txt"
    pass-check multi-line k8s-verify-checksum "$dir/k3s" "$dir/multi.txt" || rc=1

    printf '%s\n' "$sum" >"$dir/single.txt"
    pass-check single-hash k8s-verify-checksum "$dir/k3s" "$dir/single.txt" || rc=1

    printf '%s  k3s\n' "0000" >"$dir/bad.txt"
    fail-check mismatch 'Checksum mismatch' k8s-verify-checksum "$dir/k3s" "$dir/bad.txt" || rc=1

    printf '%s  not-k3s\n%s  also-not\n' "$sum" "$sum" >"$dir/missing.txt"
    fail-check no-entry 'No checksum for k3s' k8s-verify-checksum "$dir/k3s" "$dir/missing.txt" || rc=1

    rm -rf "$dir"
    return $rc
}


test-parse-args()
{
    local -A fm=()
    local -a pa=()
    local rc=0
    k8s-parse-args fm pa --variant kind --name x -- get nodes --output wide || return 1
    check-eq variant kind "${fm[variant]}" || rc=1
    check-eq name x "${fm[name]}" || rc=1
    check-eq passthrough 'get nodes --output wide' "${pa[*]}" || rc=1
    fail-check unknown-flag 'Unknown flag: --bogus' k8s-parse-args fm pa --bogus || rc=1
    fail-check missing-value 'no value provided' k8s-parse-args fm pa --variant || rc=1
    return $rc
}


test-cluster-create-kind-is-idempotent()
{
    local -a calls=()
    local exists=1
    kind() {
        calls+=("kind $*")
        if [[ $1 == get && $2 == clusters ]]; then
            (( exists == 0 )) && printf 'dl-test\n'
            return 0
        fi
        return 0
    }
    local rc=0

    k8s-cluster-create --variant kind --name dl-test >/dev/null 2>&1 || rc=1
    [[ ${calls[*]} == *'kind create cluster --name dl-test --wait 120s --kubeconfig '* ]] || { printf '  FAIL (create): no create call: %s\n' "${calls[*]}"; rc=1; }

    calls=(); exists=0
    k8s-cluster-create --variant kind --name dl-test >/dev/null 2>&1 || rc=1
    [[ ${calls[*]} != *'create cluster'* ]] || { printf '  FAIL (idempotent): created an existing cluster\n'; rc=1; }

    unset -f kind
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


test-cluster-delete-kind()
{
    local -a calls=()
    kind() { calls+=("kind $*"); }
    k8s-cluster-delete --variant kind --name dl-test || { unset -f kind; return 1; }
    unset -f kind
    [[ ${calls[*]} == 'kind delete cluster --name dl-test --kubeconfig '* ]] || { printf '  FAIL (delete): %s\n' "${calls[*]}"; return 1; }
    printf '  PASS\n'
}


test-kubectl-always-passes-explicit-kubeconfig()
{
    local -a calls=()
    kind() { if [[ $1 == get && $2 == kubeconfig ]]; then printf 'apiVersion: v1\n'; fi; }
    kubectl() { calls+=("$*"); }
    k8s-kubectl --variant kind --name dl-test -- get nodes || { unset -f kind kubectl; return 1; }
    unset -f kind kubectl
    local call=${calls[0]}
    [[ $call == --kubeconfig\ * ]] || { printf '  FAIL (kubeconfig): no explicit --kubeconfig: %s\n' "$call"; return 1; }
    [[ $call == *'--context kind-dl-test'* ]] || { printf '  FAIL (context): no explicit kind context: %s\n' "$call"; return 1; }
    [[ $call == *'get nodes' ]] || { printf '  FAIL (args): kubectl args lost: %s\n' "$call"; return 1; }
    printf '  PASS\n'
}


test-kubectl-requires-args()
{
    fail-check no-args 'Usage: k8s-kubectl' k8s-kubectl --variant k3s
}


test-cluster-create-requires-install()
{
    local rc=0
    command -v kind >/dev/null 2>&1 && { printf '  SKIP (kind installed on this machine)\n'; return 0; }
    fail-check kind-missing 'kind is not installed' k8s-cluster-create --variant kind --name dl-test || rc=1
    return $rc
}


test-etcd-scripts-are-unchanged-without-tls()
{
    local dir; dir=$(mktemp --directory --tmpdir etcd-test.XXXXXX) || return 1
    local rc=0
    local run; run=$(etcd-gen-run-script d.example.com e1 10.0.0.1 new "$dir")
    local join; join=$(etcd-gen-join-script d.example.com 10.0.0.1 e1)
    rm -rf "$dir"
    [[ $run == *'--listen-peer-urls http://10.0.0.1:2380 \'* && $run == *'--data-dir "'* ]] || { printf '  FAIL (run): not plain http\n'; rc=1; }
    [[ $run != *cert* && $run != *https* ]] || { printf '  FAIL (run): TLS leaked into the default output\n'; rc=1; }
    [[ $join == *'--listen-peer-urls http://10.0.0.1:2380 \'* && $join == *'--data-dir /var/lib/etcd/' ]] || { printf '  FAIL (join): not plain http\n'; rc=1; }
    [[ $join != *cert* && $join != *https* ]] || { printf '  FAIL (join): TLS leaked into the default output\n'; rc=1; }
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


test-etcd-run-script-tls()
{
    local dir; dir=$(mktemp --directory --tmpdir etcd-test.XXXXXX) || return 1
    local rc=0 want
    local run; run=$(etcd-gen-run-script --tls-dir /etc/etcd/tls d.example.com e1 10.0.0.1 new "$dir")
    local noauth; noauth=$(etcd-gen-run-script --tls-dir /etc/etcd/tls --no-client-cert-auth d.example.com e1 10.0.0.1 new "$dir")
    rm -rf "$dir"
    for want in '--initial-advertise-peer-urls https://10.0.0.1:2380' \
                '--advertise-client-urls https://10.0.0.1:2379' \
                '--listen-client-urls https://10.0.0.1:2379,https://127.0.0.1:2379' \
                '--cert-file "/etc/etcd/tls/server.crt"' \
                '--key-file "/etc/etcd/tls/server.key"' \
                '--trusted-ca-file "/etc/etcd/tls/ca.crt"' \
                '--peer-cert-file "/etc/etcd/tls/server.crt"' \
                '--peer-trusted-ca-file "/etc/etcd/tls/ca.crt"' \
                '--client-cert-auth' \
                '--peer-client-cert-auth'; do
        [[ $run == *"$want"* ]] || { printf '  FAIL (tls-run): missing: %s\n' "$want"; rc=1; }
    done
    [[ $run != *http://* ]] || { printf '  FAIL (tls-run): a plain http URL is left\n'; rc=1; }
    [[ $noauth == *'--cert-file'* && $noauth != *client-cert-auth* ]] || { printf '  FAIL (tls-run): --no-client-cert-auth\n'; rc=1; }
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


test-etcd-join-script-tls()
{
    local rc=0 want
    local join; join=$(etcd-gen-join-script --tls-dir /etc/etcd/tls d.example.com 10.0.0.1 e1)
    for want in '--listen-peer-urls https://10.0.0.1:2380' '--cert-file "/etc/etcd/tls/server.crt"' '--client-cert-auth' '--data-dir /var/lib/etcd/'; do
        [[ $join == *"$want"* ]] || { printf '  FAIL (tls-join): missing: %s\n' "$want"; rc=1; }
    done
    [[ $join != *http://* ]] || { printf '  FAIL (tls-join): a plain http URL is left\n'; rc=1; }
    [[ ${join##*$'\n'} == '--data-dir /var/lib/etcd/' ]] || { printf '  FAIL (tls-join): data-dir is not the last line\n'; rc=1; }
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


test-etcd-tls-flags-are-one-command()
{
    local flags; flags=$(etcd-gen-tls-flags /t '    ' 1)
    local last=${flags##*$'\n'}
    [[ $last == '    --peer-client-cert-auth \' ]] || { printf '  FAIL (flags): last line is "%s"\n' "$last"; return 1; }
    [[ $flags != *$'\n\n'* ]] || { printf '  FAIL (flags): blank line would break the continuation\n'; return 1; }
    printf '  PASS\n'
}


test-etcd-tls-args-validation()
{
    local rc=0
    fail-check noauth-alone 'needs --tls-dir' etcd-gen-run-script --no-client-cert-auth d e 10.0.0.1 new /tmp || rc=1
    fail-check unknown 'Unknown flag: --bogus' etcd-gen-run-script --bogus d e 10.0.0.1 new /tmp || rc=1
    fail-check no-value 'no value provided' etcd-gen-run-script --tls-dir || rc=1
    return $rc
}


test-etcd-install-service-requires-certs()
{
    local dir; dir=$(mktemp --directory --tmpdir etcd-test.XXXXXX) || return 1
    local data="$dir/data"; mkdir "$data"
    fail-check missing-certs 'Non-existent path' etcd-install-service --tls-dir "$dir" d.example.com e1 10.0.0.1 "$data"
    local rc=$?
    rm -rf "$dir"
    return $rc
}


test-etcd-gen-tls-certs()
{
    command -v openssl >/dev/null 2>&1 || { printf '  SKIP (openssl not installed)\n'; return 0; }
    local dir; dir=$(mktemp --directory --tmpdir etcd-test.XXXXXX) || return 1
    local rc=0
    etcd-gen-tls-certs --dir "$dir/tls" --ip 10.1.2.3,10.1.2.4 --dns etcd.example.com --days 2 || rc=1
    if (( rc == 0 )); then
        openssl verify -CAfile "$dir/tls/ca.crt" "$dir/tls/server.crt" "$dir/tls/client.crt" >/dev/null 2>&1 || { printf '  FAIL (certs): chain does not verify\n'; rc=1; }
        local san; san=$(openssl x509 -in "$dir/tls/server.crt" -noout -ext subjectAltName)
        local want
        for want in 'IP Address:10.1.2.3' 'IP Address:10.1.2.4' 'DNS:etcd.example.com' 'IP Address:127.0.0.1'; do
            [[ $san == *"$want"* ]] || { printf '  FAIL (certs): SAN is missing %s\n' "$want"; rc=1; }
        done
        local mode; mode=$(stat --format %a "$dir/tls/server.key" "$dir/tls/ca.key" "$dir/tls/client.key" | sort -u | tr '\n' ' ')
        check-eq key-mode '600 ' "$mode" >/dev/null || { printf '  FAIL (certs): keys are mode %s\n' "$mode"; rc=1; }
        fail-check overwrite 'Refusing to overwrite' etcd-gen-tls-certs --dir "$dir/tls" --ip 10.1.2.3 >/dev/null || rc=1
    fi
    fail-check usage 'Usage: etcd-gen-tls-certs' etcd-gen-tls-certs --dir "$dir/other" >/dev/null || rc=1
    rm -rf "$dir"
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


#-------------------------------------------------------------------------------
#
# test-integration-etcd-tls()
#
# Start a real single-node etcd with the generated TLS flags and certificates
#
# Opt in by setting DAYLIGHT_TEST_ETCD_DIR to a folder holding the etcd and
# etcdctl binaries. Checks that a client with the client certificate works and
# that plain http, a missing client certificate, and a wrong CA are all refused.
# etcd listens on 127.0.0.1 only and is stopped on exit.
#
test-integration-etcd-tls()
{
    local bin=${DAYLIGHT_TEST_ETCD_DIR:-}
    if [[ -z $bin ]]; then
        printf '  SKIP (set DAYLIGHT_TEST_ETCD_DIR to a folder with etcd and etcdctl)\n'
        return 0
    fi
    [[ -x $bin/etcd && -x $bin/etcdctl ]] || { printf '  FAIL (etcd): no etcd and etcdctl in %s\n' "$bin"; return 1; }

    local dir; dir=$(mktemp --directory --tmpdir etcd-it.XXXXXX) || return 1
    local rc=0 pid=''
    local ep=https://127.0.0.1:23790
    etcd-gen-tls-certs --dir "$dir/tls" --ip 127.0.0.1 || rc=1
    if (( rc == 0 )); then
        local -a tlsArgs=()
        eval "tlsArgs=($(etcd-gen-tls-flags "$dir/tls" '' 1 | tr -d '\\'))"
        "$bin/etcd" --name t1 --data-dir "$dir/data" \
            --listen-client-urls "$ep" --advertise-client-urls "$ep" \
            --listen-peer-urls https://127.0.0.1:23800 --initial-advertise-peer-urls https://127.0.0.1:23800 \
            --initial-cluster t1=https://127.0.0.1:23800 "${tlsArgs[@]}" >"$dir/etcd.log" 2>&1 &
        pid=$!
        local i
        for i in {1..20}; do
            "$bin/etcdctl" --endpoints "$ep" --cacert "$dir/tls/ca.crt" --cert "$dir/tls/client.crt" --key "$dir/tls/client.key" \
                endpoint health >/dev/null 2>&1 && break
            sleep 0.5
        done
        local -a good=(--endpoints "$ep" --cacert "$dir/tls/ca.crt" --cert "$dir/tls/client.crt" --key "$dir/tls/client.key" --dial-timeout 3s)
        "$bin/etcdctl" "${good[@]}" put /daylight/tls ok >/dev/null 2>&1 || { printf '  FAIL (etcd): client with a certificate was refused\n'; rc=1; }
        [[ $("$bin/etcdctl" "${good[@]}" get /daylight/tls --print-value-only 2>/dev/null) == ok ]] || { printf '  FAIL (etcd): value did not round-trip\n'; rc=1; }
        timeout 20 "$bin/etcdctl" --endpoints "$ep" --cacert "$dir/tls/ca.crt" --dial-timeout 3s get /x >/dev/null 2>&1 \
            && { printf '  FAIL (etcd): a client with no certificate was accepted\n'; rc=1; }
        timeout 20 "$bin/etcdctl" --endpoints http://127.0.0.1:23790 --dial-timeout 3s get /x >/dev/null 2>&1 \
            && { printf '  FAIL (etcd): plain http was accepted\n'; rc=1; }
        openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out "$dir/other.crt" -subj /CN=other -days 1 >/dev/null 2>&1
        timeout 20 "$bin/etcdctl" --endpoints "$ep" --cacert "$dir/other.crt" --cert "$dir/tls/client.crt" --key "$dir/tls/client.key" --dial-timeout 3s get /x >/dev/null 2>&1 \
            && { printf '  FAIL (etcd): a server certificate from an unknown CA was trusted\n'; rc=1; }
    fi
    [[ -n $pid ]] && kill "$pid" 2>/dev/null
    [[ -n $pid ]] && wait "$pid" 2>/dev/null
    rm -rf "$dir"
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


#-------------------------------------------------------------------------------
#
# test-integration-kind()
#
# Create a real kind cluster, check it, and delete it
#
# Opt in with DAYLIGHT_TEST_KIND=1. Skips (and passes) without docker and kind.
# The cluster has its own name and its own kubeconfig; it never touches the
# current kubectl context. It is deleted on exit even if an assertion fails.
#
test-integration-kind()
{
    if [[ ${DAYLIGHT_TEST_KIND:-} != 1 ]]; then
        printf '  SKIP (set DAYLIGHT_TEST_KIND=1 to create a real kind cluster)\n'
        return 0
    fi
    command -v docker >/dev/null 2>&1 && command -v kind >/dev/null 2>&1 || {
        printf '  SKIP (docker and kind are required)\n'
        return 0
    }

    local name="dl-test-$$"
    local rc=0
    k8s-cluster-create --variant kind --name "$name" --timeout 180 || rc=1
    if (( rc == 0 )); then
        k8s-cluster-exists --variant kind --name "$name" || { printf '  FAIL (exists): cluster not found\n'; rc=1; }
        k8s-wait-ready --variant kind --name "$name" --timeout 60 >/dev/null || { printf '  FAIL (ready): nodes not Ready\n'; rc=1; }
    fi
    k8s-cluster-delete --variant kind --name "$name" >/dev/null 2>&1
    k8s-cluster-exists --variant kind --name "$name" && { printf '  FAIL (delete): cluster still exists\n'; rc=1; }
    (( rc == 0 )) && printf '  PASS\n'
    return $rc
}


run-tests()
{
    local tests=(
        test-variants-lists-all-three
        test-latest-version-from-redirect
        test-latest-version-fails-without-a-tag
        test-resolve-variant-defaults-to-k3s
        test-resolve-variant-honors-env
        test-resolve-variant-rejects-unknown
        test-release-names
        test-release-names-reject-unsupported
        test-download-urls
        test-gen-config-k3s-server-external-etcd
        test-gen-config-never-prints-a-token
        test-gen-config-agent-needs-server
        test-gen-config-agent-with-server
        test-gen-config-rke2-rejects-datastore
        test-gen-config-rejects-kind
        test-gen-unit-file
        test-service-names
        test-kubeconfig-paths
        test-verify-checksum
        test-parse-args
        test-cluster-create-kind-is-idempotent
        test-cluster-delete-kind
        test-kubectl-always-passes-explicit-kubeconfig
        test-kubectl-requires-args
        test-cluster-create-requires-install
        test-gen-config-refuses-plain-http-datastore
        test-gen-config-https-datastore-needs-ca
        test-etcd-scripts-are-unchanged-without-tls
        test-etcd-run-script-tls
        test-etcd-join-script-tls
        test-etcd-tls-flags-are-one-command
        test-etcd-tls-args-validation
        test-etcd-install-service-requires-certs
        test-etcd-gen-tls-certs
        test-integration-etcd-tls
        test-integration-kind
    )
    local total=0 passed=0 failed=0
    local t
    for t in "${tests[@]}"; do
        printf '%s\n' "$t"
        total=$((total + 1))
        if "$t"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    done
    printf '\n%d tests, %d passed, %d failed\n' "$total" "$passed" "$failed"
    return $failed
}


main()
{
    if (( $# == 0 )); then
        run-tests
        return
    fi
    case $1 in
        test-variants-lists-all-three)                      test-variants-lists-all-three;;
        test-latest-version-from-redirect)                  test-latest-version-from-redirect;;
        test-latest-version-fails-without-a-tag)            test-latest-version-fails-without-a-tag;;
        test-resolve-variant-defaults-to-k3s)               test-resolve-variant-defaults-to-k3s;;
        test-resolve-variant-honors-env)                    test-resolve-variant-honors-env;;
        test-resolve-variant-rejects-unknown)               test-resolve-variant-rejects-unknown;;
        test-release-names)                                 test-release-names;;
        test-release-names-reject-unsupported)              test-release-names-reject-unsupported;;
        test-download-urls)                                 test-download-urls;;
        test-gen-config-k3s-server-external-etcd)           test-gen-config-k3s-server-external-etcd;;
        test-gen-config-never-prints-a-token)               test-gen-config-never-prints-a-token;;
        test-gen-config-agent-needs-server)                 test-gen-config-agent-needs-server;;
        test-gen-config-agent-with-server)                  test-gen-config-agent-with-server;;
        test-gen-config-rke2-rejects-datastore)             test-gen-config-rke2-rejects-datastore;;
        test-gen-config-rejects-kind)                       test-gen-config-rejects-kind;;
        test-gen-unit-file)                                 test-gen-unit-file;;
        test-service-names)                                 test-service-names;;
        test-kubeconfig-paths)                              test-kubeconfig-paths;;
        test-verify-checksum)                               test-verify-checksum;;
        test-parse-args)                                    test-parse-args;;
        test-cluster-create-kind-is-idempotent)             test-cluster-create-kind-is-idempotent;;
        test-cluster-delete-kind)                           test-cluster-delete-kind;;
        test-kubectl-always-passes-explicit-kubeconfig)     test-kubectl-always-passes-explicit-kubeconfig;;
        test-kubectl-requires-args)                         test-kubectl-requires-args;;
        test-cluster-create-requires-install)               test-cluster-create-requires-install;;
        test-integration-kind)                              test-integration-kind;;
        test-gen-config-refuses-plain-http-datastore)       test-gen-config-refuses-plain-http-datastore;;
        test-gen-config-https-datastore-needs-ca)           test-gen-config-https-datastore-needs-ca;;
        test-etcd-scripts-are-unchanged-without-tls)        test-etcd-scripts-are-unchanged-without-tls;;
        test-etcd-run-script-tls)                           test-etcd-run-script-tls;;
        test-etcd-join-script-tls)                          test-etcd-join-script-tls;;
        test-etcd-tls-flags-are-one-command)                test-etcd-tls-flags-are-one-command;;
        test-etcd-tls-args-validation)                      test-etcd-tls-args-validation;;
        test-etcd-install-service-requires-certs)           test-etcd-install-service-requires-certs;;
        test-etcd-gen-tls-certs)                            test-etcd-gen-tls-certs;;
        test-integration-etcd-tls)                          test-integration-etcd-tls;;
        run-tests)                                          run-tests;;
        *) printf 'Unknown test: %s\n' "$1" >&2; return 1;;
    esac
}


if ! (return 0 2>/dev/null); then
    main "$@"
fi
