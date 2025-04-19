group "validate" {
  targets = ["lint", "test"]
}

target "lint" {
  target = "lint"
  output = ["type=cacheonly"]
}

target "test" {
  target = "test"
  output = ["type=cacheonly"]
}
