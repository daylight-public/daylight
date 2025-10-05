No VPS providers are quite the same. There are a few quirks to getting any new VPS in good shape for a nice standard initialization.

### Nice Standard Initialization

Cloud init has been rerun with a standard cloud-init config, and a few other manual steps if needed
     - Either make root account password-free, or change the password to something better and save it offline
     - Upload public key
     - Add a rayray system user
     - Install daylight.sh
     - Install fresh-daylight service
     - Create a btrfs partition
     - Setup zabbly incus packages
     - Install incus, using the new package
     - Add rayray to incus-admin