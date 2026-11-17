## HowTo - Create a Kubernetes cluster

`daylight.sh` can create a Kubernetes cluster with one of three variants. Pick
one with `--variant`, or set `DAYLIGHT_K8S_VARIANT`. The default is `k3s`.

| Variant | What it is | Runs on | Use it for |
|---|---|---|---|
| `kind` | Kubernetes in Docker | any machine with Docker | throwaway test clusters |
| `k3s` | single-binary Kubernetes under systemd | a Linux host (root) | small real clusters, ARM, external etcd |
| `rke2` | Rancher's hardened Kubernetes under systemd | a Linux host (root) | clusters that should match an RKE2 target |

### Install and create

```bash
# kind: a cluster in Docker (needs docker and kind)
sudo daylight.sh k8s-install --variant kind
daylight.sh k8s-cluster-create --variant kind --name test

# k3s: install the binary, then create a server on this host
sudo daylight.sh k8s-install --variant k3s
sudo daylight.sh k8s-cluster-create --variant k3s --tls-san k8s.example.com
```

`k8s-install` downloads the release and checks it against the checksum file the
project publishes. It stops if the checksum is missing or wrong.

`k8s-cluster-create` is safe to re-run: an existing cluster is left alone.

### Look at it

```bash
daylight.sh k8s-list-nodes --variant kind --name test
daylight.sh k8s-kubectl --variant kind --name test -- get pods --all-namespaces
```

`k8s-kubectl` always passes an explicit kubeconfig (and, for kind, an explicit
context). It never uses your current context, so it cannot reach another
cluster by accident. kind clusters are created without touching `~/.kube/config`.

### Use an existing etcd (k3s)

Kubernetes Secrets are stored in the datastore, so k3s will not use a plain
`http://` etcd (`--insecure-datastore` overrides that, and is not recommended).
Turn on TLS for etcd first.

**1. Make the certificates** (on a trusted machine). This creates a CA, a
server certificate that works for clients and peers, and a client certificate
for k3s. The server certificate is valid for every `--ip` and `--dns` given,
plus `127.0.0.1` and `localhost`.

```bash
daylight.sh etcd-gen-tls-certs --dir ./etcd-tls \
    --ip 10.0.0.1,10.0.0.2,10.0.0.3 --dns etcd.example.com
```

Keys are mode 600 and nothing is overwritten. Copy `ca.crt`, `server.crt` and
`server.key` to each etcd host, and keep `ca.key` off the servers. A server key
needs a certificate for that host's address, so make one set per host if the
hosts use different addresses.

**2. Run etcd with TLS.** `--tls-dir` switches the generated etcd scripts to
https and requires client certificates (add `--no-client-cert-auth` to keep
TLS without client certificates). Without `--tls-dir` the output is unchanged.

```bash
sudo daylight.sh etcd-install-service --tls-dir /etc/etcd/tls \
    disc.example.com etcd1 10.0.0.1 /var/lib/etcd
```

`etcd-gen-run-script` and `etcd-gen-join-script` take the same flag. With
https peers, etcd's DNS discovery looks for `_etcd-server-ssl._tcp` SRV
records instead of `_etcd-server._tcp`. Anything that talks to etcd, including
`etcdctl` and dylt, then needs the client certificate too.

**3. Point k3s at it,** with the client certificate, and keep the join token in
a file, not on the command line:

```bash
sudo daylight.sh k8s-cluster-create --variant k3s \
    --datastore-endpoint https://10.0.0.1:2379,https://10.0.0.2:2379,https://10.0.0.3:2379 \
    --datastore-cafile /etc/etcd/tls/ca.crt \
    --datastore-certfile /etc/etcd/tls/client.crt \
    --datastore-keyfile /etc/etcd/tls/client.key \
    --token-file /etc/rancher/k3s/token \
    --flannel-backend wireguard-native \
    --tls-san k8s.example.com
```

### Join an agent

```bash
sudo daylight.sh k8s-cluster-create --variant k3s --role agent \
    --server https://k8s.example.com:6443 --token-file /etc/rancher/k3s/token
```

For rke2 the server URL uses port 9345.

### Delete

```bash
daylight.sh k8s-cluster-delete --variant kind --name test
sudo daylight.sh k8s-cluster-delete --variant k3s            # stop and disable
sudo daylight.sh k8s-cluster-delete --variant k3s --purge    # also delete data (asks first)
```

### Tests

```bash
bash tools/test-145-k8s-variants.sh                        # unit tests, no network
DAYLIGHT_TEST_KIND=1 bash tools/test-145-k8s-variants.sh   # also creates and deletes a real kind cluster
DAYLIGHT_TEST_ETCD_DIR=/path/to/etcd-dir bash tools/test-145-k8s-variants.sh   # also runs a real TLS etcd
```

`DAYLIGHT_TEST_ETCD_DIR` is a folder holding the `etcd` and `etcdctl`
binaries. The test starts a single-node etcd on 127.0.0.1 with the generated
certificates and checks that a client certificate works and that plain http,
a missing client certificate, and a wrong CA are refused.

The k3s and rke2 install and service paths are covered by unit tests only.
They have not been run against a real host.
