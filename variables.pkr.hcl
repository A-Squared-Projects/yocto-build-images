variable "name_prefix" {
  type        = string
  default     = "yocto"
  description = "Prefix for everything this template names - the DO snapshot, its tag, and the container repository. Nothing else in this template is project-specific, so this is the one knob that makes it yours: `-var name_prefix=rithum` produces rithum-build images. Must match what the NFS share was created with (see nfs.md) and what list-images.sh/cleanup-images.sh look up."
}

variable "region" {
  type        = string
  default     = "ams3"
  description = "DO Network File Storage (see nfs.md) is only available in a subset of regions as of writing (atl1, nyc2, ams3) - the build droplet's region has to be one of those, since the NFS share and its VPC are region-scoped. Check current availability before changing this."
}

variable "sstate_cache_share" {
  type        = string
  default     = ""
  description = "Mount source for the sstate-cache NFS access point, in the form `<share-ip>:<path>` as shown by `doctl nfs access-point get` (see nfs.md). Required for the `droplet` build - provision-droplet.sh fails if it is empty. Defaulted to empty only so `-only=container.*` does not have to supply it."
}

variable "downloads_share" {
  type        = string
  default     = ""
  description = "Mount source for the downloads NFS access point, same format as sstate_cache_share. Same requirement and same reason for the empty default."
}

variable "droplet_size" {
  type        = string
  default     = "s-1vcpu-2gb"
  description = "Size for the BUILD-TIME droplet packer provisions on - not the size used for actual Yocto builds later, which is chosen at droplet-create time against whatever image this produces. Check `doctl compute size list` for what's currently offered before relying on this default."
}

variable "container_base" {
  type        = string
  default     = "ubuntu:24.04"
  description = "Base image for the `container` build. Kept the same major release as the droplet's ubuntu-24-04-x64 so both images carry the same host toolchain - a different base is a different set of host dependencies."
}

variable "container_repository" {
  type        = string
  default     = ""
  description = "Repository name for the image the `container` build commits, tagged with a build timestamp and `latest`. Empty derives `<name_prefix>-build`; set it explicitly to a registry path (e.g. `registry.example.com/foo-build`) if the image needs pushing rather than staying local."
}

variable "build_uid" {
  type        = string
  default     = ""
  description = "uid for the `builder` user. Empty makes it a system user, as before. Set it to the uid of whoever else touches the caches - on a Mac, the Lima user, which is the Mac's own uid (501) - so files moving between the image and that host keep their owner."
}

variable "build_gid" {
  type        = string
  default     = ""
  description = "gid for the `builder` user's group, with build_uid. Lima's user has the Mac's uid but gid 1000 - the same gid ubuntu:24.04's own `ubuntu` user holds, which is removed to free it."
}
