group "dagger-base" {
  targets = ["dagger-bake-base"]
}

target "dagger-bake-base" {
  context    = "."
  dockerfile = "images/dagger-bake-base/Dockerfile"
  tags       = ["${REPO_URL}/dagger-bake-base:latest"]
  cache-from = ["type=registry,ref=${REPO_URL}/dagger-bake-base:cache"]
  cache-to   = ["type=registry,ref=${REPO_URL}/dagger-bake-base:cache,mode=max"]
}
