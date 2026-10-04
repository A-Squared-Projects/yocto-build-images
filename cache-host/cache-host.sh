#!/bin/sh
# The cache-host role: run as root, as the container's command, with the build
# caches as volumes under /mnt/build-cache. It serves whichever are mounted:
#
#   downloads      read-write  DL_DIR: a client's fetch lands in the one copy
#   sstate-cache   read-only   for clients' file:// SSTATE_MIRRORS; only this
#                              container's own builds write it
#
# A downloads-only service:
#   container run -d --name downloads -u root --cap-add ALL \
#       -v downloads:/mnt/build-cache/downloads \
#       <name_prefix>-build:latest /usr/local/sbin/cache-host
#
# A build host that also serves its sstate: mount both, and run builds in it
# with `container exec -u builder`. A `container` volume can be attached to
# only one container at a time, so whatever owns a cache is what serves it.
# See "Apple container" in README.md.
set -eu

CONF=/etc/ganesha/ganesha.conf

# Anything given as arguments runs first, as root - a project's own setup.
[ $# -eq 0 ] || "$@"

cat > "$CONF" <<'EOF'
# Written by cache-host at start. NFSv4 only: one TCP port, no rpcbind, no
# NLM; bitbake's fcntl locks on DL_DIR go through NFSv4's own locking.
NFS_CORE_PARAM {
	Protocols = 4;
	NFS_Port = 2049;
	Enable_NLM = false;
	Enable_RQUOTA = false;
}
NFSV4 {
	# No 90s grace period after a restart: there is no lock state worth
	# reclaiming across one, and clients would otherwise stall.
	Graceless = true;
	# Owners as numbers, not user@domain names, which come back as nobody
	# whenever the two ends' id mapping disagrees.
	Only_Numeric_Owners = true;
}
LOG {
	Default_Log_Level = WARN;
}
EOF

id=0
for cache in downloads sstate-cache; do
	dir=/mnt/build-cache/$cache
	mountpoint -q "$dir" || continue
	chown builder:builder "$dir"
	access=RW; [ "$cache" = sstate-cache ] && access=RO
	id=$((id + 1))
	cat >> "$CONF" <<-EOF
	EXPORT {
		Export_Id = $id;
		Path = $dir;
		Pseudo = /$cache;
		FSAL { Name = VFS; }
		Access_Type = $access;
		# bitbake never runs as root.
		Squash = Root_Squash;
		SecType = sys;
		Protocols = 4;
		Transports = TCP;
	}
	EOF
	echo "cache-host: exporting /$cache ($access)"
done
[ "$id" -gt 0 ] || { echo "cache-host: nothing mounted under /mnt/build-cache" >&2; exit 1; }

exec /usr/bin/ganesha.nfsd -F -L STDERR -f "$CONF"
