#!/bin/bash -x
#
# Host dependencies for a Yocto build, shared by every image this template
# produces - the Digital Ocean snapshot and the OCI container image alike.
#
# Nothing here may assume systemd, cloud-init, or a writable /etc/fstab: a
# container has none of them. Anything that does belongs in
# provision-droplet.sh.
#
# No repo credentials, ENCRYPT_AES_KEY/IV, or Spaces keys belong in this
# script or anywhere on the resulting image - those are injected at run time.

set -euo pipefail

BUILD_USER="builder"

# Mirrors oe-core's own documented essential-package set as of writing -
# verify against the current release's system-requirements page, it
# changes between Yocto versions.
YOCTO="\
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
    debianutils iputils-ping python3-git python3-jinja2 python3-venv \
"
LOCAL="\
    rclone \
    jq \
"

# nfs-common is only useful where the shared cache is an NFS mount, which is
# the droplet case; a container gets its cache bind-mounted from the host.
[ "${PROVISION_TARGET:-droplet}" = "droplet" ] && LOCAL="${LOCAL} nfs-common"

useradd --system --shell /bin/bash --create-home "${BUILD_USER}"

DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge unattended-upgrades snapd || true
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y ${YOCTO} ${LOCAL}

# bitbake refuses to run under a shell whose locale cannot represent UTF-8,
# and the stock container image ships no locale at all. Harmless on the
# droplet, which already has one.
DEBIAN_FRONTEND=noninteractive apt-get install -y locales
locale-gen en_US.UTF-8

DEBIAN_FRONTEND=noninteractive apt-get -y clean
rm -rf /var/lib/apt/lists/* /var/lib/update-manager /var/log/unattended-upgrades /var/lib/update-notifier
