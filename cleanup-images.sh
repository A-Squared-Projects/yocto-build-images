#!/bin/bash
#
# Delete every image from this template except the newest. DO bills for
# snapshot storage same as it does for droplets, and nothing here needs
# more than one generation kept around once a newer one has been built
# and used for at least one successful run.

set -euo pipefail

mapfile -t IDS < <(doctl compute image list-user --tag-name "${IMAGE_TAG:-yocto-build}" \
    --format ID,CreatedAt --no-header | sort -k2 -r | tail -n +2 | cut -f1)

if [ "${#IDS[@]}" -eq 0 ]; then
	echo "Nothing to clean up."
	exit 0
fi

for id in "${IDS[@]}"; do
	doctl compute image delete "${id}" --force
done
