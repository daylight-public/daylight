dir=/var/lib/etcd/

sudo rm -r "$dir" 2>/dev/null
sudo mkdir -p "$dir"
sudo chown -R ubuntu:ubuntu "$dir"
