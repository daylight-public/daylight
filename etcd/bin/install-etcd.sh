# Get etcd version
VER=$(curl -L -s https://api.github.com/repos/etcd-io/etcd/releases/latest | jq -r .tag_name)

# Create download URL
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
DOWNLOAD_URL=${GITHUB_URL}/${VER}/etcd-${VER}-linux-amd64.tar.gz

# Curl the tarball
curl -L -s "$DOWNLOAD_URL" --output-dir /tmp --remote-name

# Untar the tarball; that's all it takes to install
sudo mkdir -p /opt/etcd/
sudo chown -R ubuntu:ubuntu /opt/etcd/
tar -zxf /tmp/etcd-${VER}-linux-amd64.tar.gz -C /opt/etcd/ --strip-components=1

# Create etcd data dir + make ubuntu owner
sudo mkdir -p /var/lib/etcd
sudo chown -R ubuntu:ubuntu /var/lib/etcd
