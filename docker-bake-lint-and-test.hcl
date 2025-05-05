group "validate" {
  targets = ["lint", "test"]
}

target "lint" {
  contexts = {
    baseapp = "target:python_packages"
  }
  dockerfile = "images/python_linter/Dockerfile"
  tags = ["python-linter:latest"]
}

target "test" {
  context    = "."
  dockerfile = "images/python_tests/Dockerfile"
  tags = ["python-tests:latest"]
}
