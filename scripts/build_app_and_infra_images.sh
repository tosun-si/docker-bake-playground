#!/usr/bin/env bash

set -e
set -o pipefail
set -u

docker build \
  --platform linux/amd64,linux/arm64 \
  --file app/Dockerfile \
  --tag "${REPO_URL}/app_bake:${IMAGE_TAG_VERSION_APP}" \
  --provenance=true \
  --sbom=true \
  --push \
  .

docker build \
  --platform linux/amd64,linux/arm64 \
  --file infra/Dockerfile \
  --tag "${REPO_URL}/infra_bake:${IMAGE_TAG_VERSION_INFRA}" \
  --provenance=true \
  --sbom=true \
  --push \
  .
