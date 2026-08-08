#!/bin/bash
#
# List custom images from this template, newest first. DO has no separate
# "launch template" resource to query or update, which is a simplification
# rather than a gap: the droplet-create step looks up the newest tagged image
# directly, so this and cleanup-images.sh are the only image lifecycle tooling
# needed. Verify column names against your installed
# doctl version's --help - not guaranteed identical across releases.

set -euo pipefail

doctl compute image list-user --tag-name "${IMAGE_TAG:-yocto-build}" \
    --format ID,Name,CreatedAt --no-header | sort -k3
