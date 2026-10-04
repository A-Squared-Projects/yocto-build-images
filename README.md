# yocto-build-images

Packer templates for Yocto/OpenEmbedded build-host images. One template, two
outputs, same host dependencies:

| Build | Output | For |
|---|---|---|
| `droplet` | Digital Ocean snapshot | ephemeral one-shot build droplets |
| `container` | OCI image | building locally, in Docker/podman or Apple `container` |

`provision-common.sh` is everything both share. `provision-droplet.sh` is the
part that needs systemd, cloud-init or a persistent `/etc` — NFS mounts,
idle-poweroff, apt timers — and therefore cannot run in a container.

## Naming

Nothing in this template is project-specific except what things are called.
`name_prefix` (default `yocto`) is the single knob: it names the DO snapshot,
its tag, and the container repository, so `-var name_prefix=foo` produces
`foo-build` throughout. It must match the name the NFS share was created with
(see [`nfs.md`](nfs.md)).

`list-images.sh` and `cleanup-images.sh` take the same value from `IMAGE_TAG`,
defaulting to `yocto-build`:

```sh
IMAGE_TAG=foo-build ./list-images.sh
```

## Prerequisites

**Both** — `packer`.

**`droplet`** — the `digitalocean` plugin (`~> 1`); `DIGITALOCEAN_API_TOKEN` in
the environment (the plugin reads it directly, nothing here hardcodes a token);
and a DO Network File Storage share with `sstate-cache`/`downloads` access
points already created (see [`nfs.md`](nfs.md)). Their mount sources have no
default — `provision-droplet.sh` fails rather than write an fstab that cannot
mount.

**`container`** — the `docker` plugin (`~> 1`) and a working `docker` CLI.
Packer's docker builder shells out to `docker`, so **Apple's `container` cannot
build this image** — it consumes the result. On macOS, build with Docker
Desktop or podman, then load the image into `container`.

## Key commands

| Task | Command |
|---|---|
| Build the droplet snapshot | `packer build -only='droplet.*' -var sstate_cache_share=<ip:path> -var downloads_share=<ip:path> .` |
| Build the container image | `packer build -only='container.*' .` |
| Build both | `packer build -var sstate_cache_share=<ip:path> -var downloads_share=<ip:path> .` |
| List snapshots from this template | `./list-images.sh` |
| Delete all but the newest snapshot | `./cleanup-images.sh` |

## Using the container image

The container has no NFS mount — bind-mount the shared cache from the host
instead, and keep `DL_DIR`/`SSTATE_DIR` pointing at it:

```sh
docker run --rm -it \
    -v "$PWD:/work" -v "$HOME/downloads:/mnt/build-cache/downloads" \
    -v "$HOME/sstate-cache:/mnt/build-cache/sstate-cache" \
    yocto-build:latest
```

**Target sstate is architecture-independent; `-native`/`-cross` is not.** An
arm64 host (Apple silicon) and the x86-64 droplets can share the target half of
the cache — that is what hash equivalence (`BB_SIGNATURE_HANDLER =
OEEquivHash`) exists for: differing native inputs that produce equivalent output
resolve to the same unihash, so downstream target tasks stay reusable. What
genuinely cannot be shared is the `-native`/`-cross` sstate itself — the cross
toolchain and native tools are built *for* the build machine, so each
architecture rebuilds its own.

The catch is that cross-host reuse needs a **shared hash-equivalence server**.
A stock build runs a per-build unix socket (`BB_HASHSERVE =
unix://…/build/hashserve.sock`) with no `BB_HASHSERVE_UPSTREAM`, so equivalence
learned in one build is invisible to every other — including between two builds
on the same machine. Check both before concluding that a mirror is not working:
without a shared server you get exact-hash hits only, and none of the
equivalence-mediated ones.

So: building `linux/amd64` under emulation is not required to share target
sstate, and buys nothing the equivalence server would not. Keep the container
native to its host; the cost of an arm64 host is rebuilding the cross toolchain
once, not the whole target.

`container_base` is deliberately the same Ubuntu major release as the droplet's
`ubuntu-24-04-x64`. A different base means a different host toolchain and so a
different `-native`/`-cross` half; the target half still shares under hash
equivalence, but keeping them aligned is what gets you exact-hash hits without
depending on it.

## Apple container

Packer builds the image in Docker; load it into `container` from there:

```sh
docker save yocto-build:latest -o /tmp/yocto-build.tar
container image load -i /tmp/yocto-build.tar
```

What `container` does differently, measured with `container` 1.5.0 on
macOS 27 (M4):

- **Put the caches on named volumes, never on a macOS directory.** A
  `container volume` is an ext4 filesystem on a virtio block device, with a
  sparse image file behind it on the Mac (512 GiB by default). A macOS
  directory mounted with `-v` arrives over virtiofs: case-insensitive on a
  stock APFS volume, `chown` silently ignored, and GNU tar cannot even unpack
  a kernel tarball onto it (its symlink placeholders come back `EACCES`).
- **Volumes are made without an ext4 journal.** Add one before first use,
  from the Mac (Homebrew `e2fsprogs`), while no container holds it:
  `tune2fs -j ~/Library/Application\ Support/com.apple.container/volumes/<name>/volume.img`.
  Growing one is also offline only: `truncate -s`, `e2fsck -f`, `resize2fs`
  on the same file. `fstrim` inside a container gives freed space back to the
  Mac.
- **A volume can be attached to only one container at a time**, read-only
  included (`The storage device attachment is invalid`): each container is
  its own VM, and ext4 is not a cluster filesystem. So one container owns the
  caches, builds run inside it with `container exec`, and anything else - a
  Lima VM on the same Mac, say - mounts them over NFS from it. That is the
  cache-host role below.
- **`-p` port publishing did not work**: the forwarder accepts, then resets.
  A container's own address (192.168.65.x) is reachable from the Mac and
  from Lima, but it changes on every restart. A socat forwarder on the Mac
  that reads the current address per connection stands in.
- **`--cpus N` gives the VM N+1 vCPUs** with the cgroup capped at N, so set
  `BB_NUMBER_THREADS` and `PARALLEL_MAKE` rather than letting bitbake size
  itself from `nproc`.
- **Match `builder` to the other side.** Lima's user has the Mac's uid
  (501) and gid 1000: build with `-var build_uid=501 -var build_gid=1000`
  so files crossing between the two keep their owner.

### The cache-host role

The container image carries nfs-ganesha (userspace NFSv4; the guest kernel
has no nfsd) and an entry point that serves whichever of
`/mnt/build-cache/downloads` (read-write) and `/mnt/build-cache/sstate-cache`
(read-only) are mounted. Mount only `downloads` for a standalone downloads
service; mount both for a build host that also serves its sstate:

```sh
container run -d --name cache-host -u root --cap-add ALL \
    -v downloads:/mnt/build-cache/downloads \
    -v sstate-cache:/mnt/build-cache/sstate-cache \
    yocto-build:latest /usr/local/sbin/cache-host
container exec -u builder cache-host ...        # builds run in here
```

A client mounts with its own kernel's NFS client:

```sh
sudo mount -t nfs4 -o vers=4.2,proto=tcp,hard <address>:/downloads <mnt>
```

Over such a mount fcntl locks, hardlinks, symlinks, case and owners all
behave, and DL_DIR costs a client seconds per build: reading 5.9 GB of
tarballs ran at ~430 MB/s, and decompression and git dominate either way.
Use the read-only sstate export as a `file://` `SSTATE_MIRRORS` entry and
see yocto-build-tools' `sstate-symlinks-to-hardlinks.py --cross-device copy`
before the host prunes.

## Getting a build going inside the image

The image carries host dependencies and nothing else — no layers, no
configuration. `bitbake-setup` covers that, and upstream ships a default
registry, so the worked example needs nothing project-specific:

```sh
uvx bitbake-setup list                                # what the registry offers
uvx bitbake-setup init poky-master poky machine/qemux86-64
source poky-master*/build/init-build-env
bitbake core-image-minimal
```

`poky-master` is upstream's own configuration
([`default-registry/configurations/poky-master.conf.json`](https://git.openembedded.org/bitbake/tree/default-registry/configurations/poky-master.conf.json)).
It also offers `poky-with-sstate` — the same thing pointed at the public sstate
mirror, which is usually what you want on a throwaway builder that has no local
cache to hit.

The setup directory name reflects the choices made, so the glob above is
deliberate. See the
[BitBake environment-setup manual](https://docs.yoctoproject.org/bitbake/dev/bitbake-user-manual/bitbake-user-manual-environment-setup.html)
for the full set of options and how to pass them non-interactively.

Your own configuration is the same command with a path or URL in place of the
registry id — see `-L/--use-local-source` there for pointing a layer at a local
checkout rather than cloning it.

## What's deliberately different from a typical CI-runner image

This produces a base image for **one-shot, externally-orchestrated builds**
(create droplet → build → push → destroy), not a long-lived, self-registering
CI runner fleet — so it deliberately omits a few things that pattern usually
needs:

- No CI-system registration step (GitLab/GitHub runner tokens etc.) baked into
  the image or its cloud-init — whatever triggers a build supplies its own
  orchestration.
- No credentials of any kind baked into either image — repo access tokens,
  signing/encryption keys and object-store credentials are all injected at run
  time, never written to disk here.
- No launch-template equivalent to maintain: DO has no persistent "launch
  template" resource the way EC2 does, so there is no separate "point the
  template at the new image" step — the droplet-create step looks up the newest
  image tagged `<name_prefix>-build` directly (see `list-images.sh`).

## Package list

`provision-common.sh`'s Yocto host-dependency list mirrors oe-core's own
documented essential-package set as of writing — verify against the current
release's system-requirements page, it changes between Yocto versions.

## Licence

MIT — see [`LICENSE`](LICENSE).
