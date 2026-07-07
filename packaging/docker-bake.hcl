variable "DOCKER_IMAGE" {
  default = "openslide/deb"
}

variable "DOCKER_TAG_PRIMARY" {
  default = "local"
}

variable "DOCKER_PLATFORMS" {
  default = "linux/amd64,linux/arm64"
}

target "_common" {
  context    = "."
  dockerfile = "packaging/deb.Dockerfile"
  platforms  = split(",", DOCKER_PLATFORMS)
}

target "debian-trixie-export" {
  inherits = ["_common"]
  target   = "export"
  args = {
    BASE_IMAGE   = "debian:trixie-slim"
    DISTRO_LABEL = "debian-trixie"
  }
  tags = ["${DOCKER_IMAGE}:${DOCKER_TAG_PRIMARY}-debian-trixie"]
}

target "debian-trixie-smoke-test" {
  inherits = ["_common"]
  target   = "smoke-test"
  args = {
    BASE_IMAGE   = "debian:trixie-slim"
    DISTRO_LABEL = "debian-trixie"
  }
  output = ["type=cacheonly"]
}

target "ubuntu-26-04-export" {
  inherits = ["_common"]
  target   = "export"
  args = {
    BASE_IMAGE   = "ubuntu:26.04"
    DISTRO_LABEL = "ubuntu-26.04"
  }
  tags = ["${DOCKER_IMAGE}:${DOCKER_TAG_PRIMARY}-ubuntu-26-04"]
}

target "ubuntu-26-04-smoke-test" {
  inherits = ["_common"]
  target   = "smoke-test"
  args = {
    BASE_IMAGE   = "ubuntu:26.04"
    DISTRO_LABEL = "ubuntu-26.04"
  }
  output = ["type=cacheonly"]
}

group "debian-trixie" {
  targets = ["debian-trixie-export", "debian-trixie-smoke-test"]
}

group "ubuntu-26-04" {
  targets = ["ubuntu-26-04-export", "ubuntu-26-04-smoke-test"]
}

group "default" {
  targets = ["debian-trixie", "ubuntu-26-04"]
}
