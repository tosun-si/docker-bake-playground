group "validate" {
  targets = ["lint", "test"]
}

target "lint" {
  context    = "."
  dockerfile = "images/python_linter/Dockerfile"
  tags = ["${REPO_URL}/python-linter:latest"]
  cache-from = ["type=registry,ref=${REPO_URL}/python-linter:cache"]
  cache-to = ["type=registry,ref=${REPO_URL}/python-linter:cache,mode=max"]
}

target "test" {
  context    = "."
  dockerfile = "images/python_tests/Dockerfile"
  tags = ["${REPO_URL}/python-tests:latest"]
  cache-from = ["type=registry,ref=${REPO_URL}/python-tests:cache"]
  cache-to = ["type=registry,ref=${REPO_URL}/python-tests:cache,mode=max"]
}
