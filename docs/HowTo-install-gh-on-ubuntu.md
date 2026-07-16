# Installing the GitHub CLI on Ubuntu

## Why the official packages?

Debian/Ubuntu packages lag behind, and sometimes the community-distributed
`gh` CLI has bugs. As of November 2025, GitHub CLI maintainers strongly
recommend the official Debian packages, especially since the 2.45.x / 2.46.x
versions in the Ubuntu repos are broken due to deprecated GitHub APIs.

## Official installation instructions

The official instructions are at
[https://github.com/cli/cli/blob/trunk/docs/install_linux.md](https://github.com/cli/cli/blob/trunk/docs/install_linux.md).

The official one-liner for Debian/Ubuntu is:

```bash
(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y
```

## What I don't like about the official instructions

- Downloads to a temp file (`mktemp`) then copies with `tee` — extra step
- Uses `wget` (requires installing it if missing) instead of `curl` (already present)
- `mkdir -p -m 755` only applies the mode on creation, not if the folder already exists
- Mixes `mode change` syntax (`go+r`) with numeric (`755`) — inconsistent
- All-on-one-line subshell chain is hard to read and debug
- Uses short form flags (`-o`, `-y`, `-p`) when long form (`--output`, `--yes`, `--parents`) is clearer in scripts
- Chains `apt update` and `apt install` on one line with `&&` — if `apt update` fails, `apt install` is skipped, which is fine, but they're logically separate steps

## My preferred version

Step-by-step, each line independently verifiable:

```bash
# Variables
keyName=githubcli-archive-keyring.gpg
keyPath=/etc/apt/keyrings/$keyName
keyUrl=https://cli.github.com/packages/$keyName
arch=$(dpkg --print-architecture)

# Create the keyrings directory if it doesn't exist
sudo mkdir --parents /etc/apt/keyrings
# Ensure permissions allow traversal (world r-x) regardless of prior state
sudo chmod 755 /etc/apt/keyrings

# Download the GPG keyring directly to its destination
sudo curl --fail --silent --show-error --location \
  --output "$keyPath" "$keyUrl"
# Owner can write, world can read
sudo chmod 644 "$keyPath"

# Create the sources directory if it doesn't exist (same reasoning as keyrings)
sudo mkdir --parents /etc/apt/sources.list.d
sudo chmod 755 /etc/apt/sources.list.d

# Add the apt source list entry
echo "deb [arch=$arch signed-by=$keyPath] https://cli.github.com/packages stable main" \
  | sudo dd of=/etc/apt/sources.list.d/github-cli.list

# Update package lists
sudo apt update

# Install
sudo apt install gh --yes
```

### Bonus - how to update a apt repo GPG
While working on this I got an expired signature warning while doing an `apt update`

```
🔆 sudo apt update 2>&1 | grep -i zabbly

Get:5 https://pkgs.zabbly.com/incus/stable noble InRelease [8951 B]
Err:5 https://pkgs.zabbly.com/incus/stable noble InRelease
  The following signatures were invalid: EXPKEYSIG 82CC8797C838DCFD Zabbly Kernel Builds <info@zabbly.com>
W: An error occurred during the signature verification. The repository is not updated and the previous index files will be used. GPG error: https://pkgs.zabbly.com/incus/stable noble InRelease: The following signatures were invalid: EXPKEYSIG 82CC8797C838DCFD Zabbly Kernel Builds <info@zabbly.com>
W: Failed to fetch https://pkgs.zabbly.com/incus/stable/dists/noble/InRelease  The following signatures were invalid: EXPKEYSIG 82CC8797C838DCFD Zabbly Kernel Builds <info@zabbly.com>
```

Here's how do update the key
```
🔆 sudo curl \
	--fail \
	--location \
	--show-error \
	--silent \
	--output /etc/apt/keyrings/zabbly.asc \
	https://pkgs.zabbly.com/key.asc
```
