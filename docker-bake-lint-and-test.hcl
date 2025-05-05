group "validate" {
  targets = ["lint", "test"]
}

target "lint" {
  context    = "."
  dockerfile = "images/python_linter/Dockerfile"
  tags = ["python-linter:latest"]
}

target "test" {
  context    = "."
  dockerfile = "images/python_tests/Dockerfile"
  tags = ["python-tests:latest"]
}
