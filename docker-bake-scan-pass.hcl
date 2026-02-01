group "scan-pass" {
  targets = ["alpine-simple"]
}

target "alpine-simple" {
  context    = "."
  dockerfile = "images/alpine-simple/Dockerfile"
  tags       = ["${REPO_URL}/alpine-simple:latest"]
}
