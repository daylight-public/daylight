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

Point k3s at the cluster's etcd with `--datastore-endpoint`. Use TLS endpoints
and keep the join token in a file, not on the command line:

```bash
sudo daylight.sh k8s-cluster-create --variant k3s \
    --datastore-endpoint https://10.0.0.1:2379,https://10.0.0.2:2379,https://10.0.0.3:2379 \
    --token-file /etc/rancher/k3s/token \
    --flannel-backend wireguard-native \
    --tls-san k8s.example.com
```

Kubernetes Secrets are stored in that etcd. daylight's own etcd scripts are
plain HTTP today, so enable TLS on etcd before pointing a cluster at it.

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
```

The k3s and rke2 paths are covered by unit tests only. They have not been run
against a real host.
