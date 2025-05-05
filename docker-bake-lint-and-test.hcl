group "validate" {
  targets = ["lint", "test"]
}

target "lint" {
  context    = "."
  dockerfile = "images/python_linter/Dockerfile"
  tags = ["${REPO_URL}/python-linter:latest"]
}

target "test" {
  context    = "."
  dockerfile = "images/python_tests/Dockerfile"
  tags = ["${REPO_URL}/python-tests:latest"]
}
