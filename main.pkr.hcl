packer {
  required_plugins {
    digitalocean = {
      source  = "github.com/digitalocean/digitalocean"
      version = "~> 1"
    }
    docker = {
      source  = "github.com/hashicorp/docker"
      version = "~> 1"
    }
  }
}

locals {
  # "timestamp" template function replacement
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")

  image_name = "${var.name_prefix}-build"
  repository = var.container_repository != "" ? var.container_repository : local.image_name
}

# api_token is intentionally not set here - the plugin reads
# DIGITALOCEAN_API_TOKEN from the environment. Nothing in this template
# hardcodes a token or profile.
source "digitalocean" "build-image" {
  image         = "ubuntu-24-04-x64"
  region        = var.region
  size          = var.droplet_size
  ssh_username  = "root"
  snapshot_name = "${local.image_name}-${local.timestamp}"
  tags          = [local.image_name]
}

# Same host dependencies, as an OCI image - for building locally instead of
# on a droplet. Runs the common provisioning only; everything in
# provision-droplet.sh needs systemd or a persistent /etc.
source "docker" "build-image" {
  image  = var.container_base
  commit = true
  changes = [
    "USER builder",
    "WORKDIR /home/builder",
    "ENV LANG en_US.UTF-8",
  ]
}

build {
  name    = "droplet"
  sources = ["source.digitalocean.build-image"]

  # Must precede any apt work: cloud-init is still holding the apt lock on a
  # freshly created droplet, and apt-get would race it.
  provisioner "shell" {
    inline = ["cloud-init status --wait"]
  }

  provisioner "shell" {
    environment_vars = [
      "PROVISION_TARGET=droplet",
      "BUILD_UID=${var.build_uid}",
      "BUILD_GID=${var.build_gid}",
    ]
    script           = "provision-common.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "SSTATE_CACHE_SHARE=${var.sstate_cache_share}",
      "DOWNLOADS_SHARE=${var.downloads_share}",
    ]
    script = "provision-droplet.sh"
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}

build {
  name    = "container"
  sources = ["source.docker.build-image"]

  provisioner "shell" {
    environment_vars = [
      "PROVISION_TARGET=container",
      "BUILD_UID=${var.build_uid}",
      "BUILD_GID=${var.build_gid}",
    ]
    script = "provision-common.sh"
  }

  # The cache-host role: see "Apple container" in README.md.
  provisioner "file" {
    sources     = ["cache-host/cache-host.sh"]
    destination = "/tmp/"
  }
  provisioner "shell" {
    script = "provision-cache-host.sh"
  }

  post-processor "docker-tag" {
    repository = local.repository
    tags       = [local.timestamp, "latest"]
  }
}
