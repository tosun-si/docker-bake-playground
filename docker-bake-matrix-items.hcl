target "app" {
  name = "app-${item.tgt}-${replace(item.version, ".", "-")}"
  matrix = {
    item = [
      {
        tgt     = "lint"
        version = "1.0"
        ctx     = "."
        dockerf = "images/python_linter/Dockerfile"
        tag     = "${REPO_URL}/python-linter-matrix:latest"
      },
      {
        tgt     = "test"
        version = "2.0"
        ctx     = "."
        dockerf = "images/python_tests/Dockerfile"
        tag     = "${REPO_URL}/python-tests-matrix:latest"
      }
    ]
  }
  context    = item.ctx
  dockerfile = item.dockerf
  tags = [item.tag]
}
