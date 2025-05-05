target "default" {
  matrix = {
    mode = ["release", "debug"]
  }
  args = {
    BUILD_TAGS = mode
  }
  tags = [
      mode == "release" ? "bakeme:latest" : "bakeme:dev"
  ]
  name   = "image-${mode}"
  target = "image"
}
