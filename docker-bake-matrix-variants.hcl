group "default" {
  targets = [
    "alpine_apps",
    "bullseye_apps",
    "bookworm_apps"
  ]
}

target "_common" {
  context = "."
}

target "alpine_apps" {
  inherits = ["_common"]
  name = "app-${variant}-${replace(version, ".", "-")}"
  matrix = {
    variant = ["alpine"]
    version = ["3.17", "3.21", "3.22"]
  }
  dockerfile = "images/app-matrix/${variant}-${replace(version, ".", "-")}/Dockerfile"
  tags = ["myapp:${variant}-${version}"]
}

target "bullseye_apps" {
  inherits = ["_common"]
  name = "app-${variant}-${replace(version, ".", "-")}"
  matrix = {
    variant = ["bullseye"]
    version = ["11.7", "11.8"]
  }
  dockerfile = "images/app-matrix/${variant}-${replace(version, ".", "-")}/Dockerfile"
  tags = ["myapp:${variant}-${version}"]
}

target "bookworm_apps" {
  inherits = ["_common"]
  name = "app-${variant}-${replace(version, ".", "-")}"
  matrix = {
    variant = ["bookworm"]
    version = ["12.2", "12.5"]
  }
  dockerfile = "images/app-matrix/${variant}-${replace(version, ".", "-")}/Dockerfile"
  tags = ["myapp:${variant}-${version}"]
}
