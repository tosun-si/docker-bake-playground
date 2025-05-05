group "default" {
  targets = ["app", "infra"]
}

target "_common" {
  context = "."
  platforms = ["linux/amd64", "linux/arm64"],
  attest = [
    "type=provenance,mode=max",
    "type=sbom"
  ]
}

target "app" {
  inherits = ["_common"]
  dockerfile = "app/Dockerfile"
  tags = ["${REPO_URL}/app_bake:${IMAGE_TAG_VERSION_APP}"]
}

target "infra" {
  inherits = ["_common"]
  dockerfile = "infra/Dockerfile"
  tags = ["${REPO_URL}/infra_bake:${IMAGE_TAG_VERSION_INFRA}"]
}