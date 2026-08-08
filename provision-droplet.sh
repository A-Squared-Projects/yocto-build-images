#!/bin/bash -x
#
# Digital Ocean droplet specifics, on top of provision-common.sh. Everything
# here needs systemd or a persistent /etc, so none of it can run in the
# container image.

set -euo pipefail

# Both default to empty in variables.pkr.hcl so the container build does not
# have to supply them. Empty here would write a syntactically valid fstab that
# fails to mount at boot, so fail now instead.
: "${SSTATE_CACHE_SHARE:?set -var sstate_cache_share=<ip:path> (see nfs.md)}"
: "${DOWNLOADS_SHARE:?set -var downloads_share=<ip:path> (see nfs.md)}"

# Shared build cache (sstate-cache + downloads): DO's own managed Network
# File Storage (NFS) - see nfs.md for the one-time share/access-point setup.
# One share, two access points (one per path), rather than two separately
# provisioned shares - cheaper and just as isolated, since access points
# already give each its own export path. Mount sources are baked in at
# image-build time (packer build -var sstate_cache_share=... -var
# downloads_share=...) because they're known, stable addresses once the
# share/access points exist - no different from baking in any other fixed
# piece of infrastructure addressing. Options match DO's own documented
# fstab recommendation for NFS shares (nconnect/automount/idle-timeout),
# not hand-tuned NFSv4 options guessed at independently.
mkdir -p /mnt/build-cache/sstate-cache /mnt/build-cache/downloads
cat >>/etc/fstab <<-FSTAB
	${SSTATE_CACHE_SHARE} /mnt/build-cache/sstate-cache nfs _netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=600,nconnect=8,vers=4.1 0 0
	${DOWNLOADS_SHARE} /mnt/build-cache/downloads nfs _netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=600,nconnect=8,vers=4.1 0 0
	FSTAB

# Idle droplets shut down rather than run - and get billed - forever; a
# hung or orphaned build should not silently keep costing money.
sed -e '/IdleAction=/cIdleAction=poweroff' -e '/IdleActionSec=/cIdleActionSec=5m' -i /etc/systemd/logind.conf

# We upgrade on a whole-image basis - these just cost cycles on every boot.
systemctl disable apt-daily.timer apt-daily-upgrade.timer
