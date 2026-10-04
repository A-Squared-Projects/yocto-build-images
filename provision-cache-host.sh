#!/bin/bash -x
#
# The cache-host role, container image only: nfs-ganesha and its entry point.
# See "Apple container" in README.md for why a container serves its own
# volumes over NFS.

set -euo pipefail

DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-ganesha nfs-ganesha-vfs
DEBIAN_FRONTEND=noninteractive apt-get -y clean
rm -rf /var/lib/apt/lists/*

# cache-host writes /etc/ganesha/ganesha.conf itself at start, exporting
# whichever caches are mounted.
install -m 755 /tmp/cache-host.sh /usr/local/sbin/cache-host
rm -f /tmp/cache-host.sh

# ganesha needs its pid directory, and finds an exported filesystem through
# /etc/mtab, which a container rootfs does not have.
mkdir -p /var/run/ganesha /var/lib/nfs/ganesha
ln -sf /proc/self/mounts /etc/mtab
