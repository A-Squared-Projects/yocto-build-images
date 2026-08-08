# NFS share setup (one-time)

DO has a real managed NFS product - Network File Storage (`doctl nfs`) -
comparable to AWS EFS: fully managed, POSIX-compliant, multi-attach
across droplets, VPC-scoped. This is a one-time setup step, done once
before the Packer image can be built (its mount sources are baked into
`/etc/fstab` at build time - see `build-tools.sh`), not part of the
per-build pipeline.

**Region constraint:** as of writing, Network File Storage is only
available in `atl1`, `nyc2`, `ams3` - check current availability before
picking one. The build droplets' region and the share's VPC have to
match, since a share only connects to VPCs in its own region.

## Create the share and its access points

```sh
doctl nfs create --name <name_prefix>-cache --region ams3 \
    --size <N> --vpc-ids <vpc-id> --performance-tier standard
```

`--performance-tier standard` is the cost-effective general-purpose
tier; `high-performance` exists for throughput-heavy workloads (AI/ML
training etc.) and is unlikely to be worth it here. Size in GiB - big
enough for a full sstate-cache plus a downloads mirror; grow later with
`doctl nfs resize` rather than guessing high up front.

One share, two access points - each access point gets its own isolated
export path within the same billed share, rather than provisioning two
separate shares:

```sh
doctl nfs access-point create --name sstate-cache --path /sstate-cache \
    --share-id <share-id> --vpc-id <vpc-id>
doctl nfs access-point create --name downloads --path /downloads \
    --share-id <share-id> --vpc-id <vpc-id>
```

## Get the mount sources

```sh
doctl nfs access-point list --share-id <share-id>
```

Each access point's mount source is `<share-ip>:<path>` (e.g.
`10.128.0.2:/sstate-cache`) - these are exactly what
`variables.pkr.hcl`'s `sstate_cache_share`/`downloads_share` expect:

```sh
packer build -var sstate_cache_share=10.128.0.2:/sstate-cache \
    -var downloads_share=10.128.0.2:/downloads .
```

## Mounting manually (debugging only - the image already does this)

```sh
sudo apt install nfs-common   # already in build-tools.sh
sudo mount -t nfs -o nconnect=8 <share-ip>:<path> /mnt/example
```
