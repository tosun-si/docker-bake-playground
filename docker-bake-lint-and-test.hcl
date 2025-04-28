group "validate" {
  targets = ["lint", "test"]
}

target "lint" {
  # target     = "lint"
  context    = "."
  dockerfile = "linter/Dockerfile"
  output = ["type=cacheonly"]
}

target "test" {
  # target     = "test"
  context    = "."
  dockerfile = "linter/Dockerfile"
  output = ["type=cacheonly"]
}
