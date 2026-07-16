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

## My preferred version

Step-by-step, each line independently verifiable:

```bash
# Create the keyrings directory if it doesn't exist
sudo mkdir -p /etc/apt/keyrings
# Ensure permissions allow traversal (world r-x) regardless of prior state
sudo chmod 755 /etc/apt/keyrings

# Download the GPG keyring directly to its destination
sudo curl -fsSL -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  https://cli.github.com/packages/githubcli-archive-keyring.gpg
# Owner can write, world can read
sudo chmod 644 /etc/apt/keyrings/githubcli-archive-keyring.gpg

# Add the apt source list entry
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo dd of=/etc/apt/sources.list.d/github-cli.list

# Update and install
sudo apt update && sudo apt install gh -y
```
