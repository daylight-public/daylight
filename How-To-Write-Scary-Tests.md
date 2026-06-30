# How To Write Scary Tests

## The problem

Most developers don't stress about their code failing on a user's machine.
They stress about CI failing. Their code works locally — they ran it, they saw
it — and then a CI runner in a different time zone hits a different kernel
with a different package version and everything breaks. The fix cycle is
push → wait → fail → guess → repeat.

What if you could run the same tests locally that CI runs? Not unit tests
that mock away every dependency, but tests that actually start services,
bind ports, write files, and integrate with real third-party packages?

Nobody does this because it's scary. A test that writes to `/var/www/html/`
in production could wipe your dev environment. A test that binds port 80
conflicts with your local nginx. A test that installs a package via apt
litters your system with dependencies you don't want.

So developers delegate the scary stuff to CI and stress about why their
code works on their machine but not in the cloud.

This document describes how to write those scary tests safely.

## The insight

Linux namespaces solve the problem completely. A namespace-sandboxed
process sees its own filesystem, its own network, its own process tree.
It can write to `/var/www/html/`, bind port 80, install packages, delete
`/etc/` — none of it touches the real system.

The sandbox isn't a test harness. It's the calling context. The test never
calls the function directly — it calls it through a namespace boundary.

## The pattern

Every namespace-isolated test follows the same recipe:

```
detect-bwrap → build sandbox → run real function → inspect results
```

### 1. Detect bwrap

```bash
detect-bwrap()
{
    command -v bwrap >/dev/null 2>&1 || return 1
    if bwrap --ro-bind / / --tmpfs /tmp -- bash -c 'true' >/dev/null 2>&1; then
        printf 'bwrap'
    elif sudo -n bwrap --ro-bind / / --tmpfs /tmp -- bash -c 'true' >/dev/null 2>&1; then
        printf 'sudo bwrap'
    else
        return 1
    fi
}
```

If bwrap isn't available, the test skips with a clear message. The host
filesystem is never at risk.

### 2. Build the sandbox

Bind the real root filesystem (read-only), overlay tmpfs on writable paths:

```bash
bwrap_cmd=$(detect-bwrap) || skip
cmd="$bwrap_cmd --ro-bind / /"
cmd="$cmd --tmpfs /var/www/html"     # generated content goes here
cmd="$cmd --tmpfs /run"              # pid files, sockets
cmd="$cmd --tmpfs /var/log/nginx"    # logs
cmd="$cmd --dev /dev"
cmd="$cmd bash -c '...'"
```

The `--ro-bind / /` gives the sandbox access to every file on the system
(read-only). The `--tmpfs` overlays make specific paths writable. Anything
written to those overlays vanishes when the sandbox exits.

### 3. Run the real function

Inside the sandbox, source daylight.sh and call functions by name.
No env vars, no test-mode flags, no parameter overrides:

```bash
source /opt/bin/daylight.sh
nginx-init
```

The function writes to `/var/www/html/index.nginx-debian.html` because
that's what it always does. It curls `http://localhost/` because that's
what it always does. It has no idea it's being tested.

### 4. Inspect the results

Check exit codes, check file existence, grep output — all from within
the sandbox or via a side channel:

```bash
source /opt/bin/daylight.sh
nginx-init && echo OK
```

## Concrete example: nginx-init

```bash
bwrap --unshare-net --ro-bind / / \
  --tmpfs /run \
  --tmpfs /var/www/html \
  --tmpfs /var/log/nginx \
  --tmpfs /var/cache \
  --dev /dev \
  bash -c "
    ip link set lo up
    source /opt/bin/daylight.sh
    nginx
    nginx-init
  "
```

Network namespace (`--unshare-net`) gives the sandbox its own `lo`
interface. nginx binds port 80 inside the sandbox — no conflict with
a host nginx on port 80. The curl inside `nginx-init` hits the sandbox's
port 80, not the host's.

## Why not Podman?

Podman (and Docker) solve a similar problem with a heavier abstraction:
images, registries, container storage, rootless mode quirks. They bring
a packaging model — you need an image that contains your code, its
dependencies, and the system tools it needs. This is the right model for
deployment but heavy for testing.

Bubblewrap maps the host filesystem directly. No image to build, no
registry push, no `apt-get install` inside a containerfile. The test
environment is the host environment, because it is the host environment
— just with write protection on the parts you care about.

Both tools use the same kernel primitives (namespaces). Podman is a
container runtime. Bubblewrap is a namespace sandbox. They overlap, but
they're not the same thing.

## Why not just CI?

CI is where you find out your tests fail. The goal is to find out earlier.

A namespace-isolated test runs anywhere bwrap is installed — your laptop,
a colleague's workstation, a bare-metal dev server, CI. When it works
locally, it works in CI. When it fails, you debug it locally with the
same tools you use for everything else: `echo`, `strace`, `bash -x`.

CI becomes a confirmation step, not a discovery step.

## Risks

### The developer runs the test outside the sandbox

The test has a detection gate — if bwrap isn't available, it prints
`SKIP` and exits 0. There is no "run without sandbox" mode. To hose your
filesystem, you'd need to explicitly remove the gate, which is the same
class of mistake as running `rm -rf /` in the wrong directory.

### The sandbox doesn't match production

True — no abstraction perfectly mirrors production. The namespaced
filesystem may have different performance characteristics (tmpfs vs disk),
different network behavior (loopback only), and different process
visibility. These differences matter for performance tests but are
negligible for correctness tests.

### The developer needs to understand namespaces

Yes. That's the point.

## A note on the "scary" framing

The word "scary" is intentional. These tests are not unit tests. They
start real services, write to real paths (inside the sandbox), and
exercise real integration points. They test things that most developers
are afraid to test locally.

A test suite where nothing is scary — where every dependency is mocked,
every file path is configurable, every side effect is disabled — tells
you very little about whether your code works in production.

A test suite where the scary things are tested — where nginx actually
serves pages, where generated files actually exist at their real paths,
where systemd actually starts services — tells you what you need to know.
