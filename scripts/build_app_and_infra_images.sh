#!/usr/bin/env bash

set -e
set -o pipefail
set -u

if [[ -z "${REPO_URL:-}" ]]; then
  echo "❌ ERROR: REPO_URL environment variable is not set or empty."
  exit 1
fi

if [[ -z "$IMAGE_TAG_VERSION_APP" ]]; then
  echo "❌ ERROR: IMAGE_TAG_VERSION_APP environment variable is not set or empty."
  exit 1
fi

if [[ -z "$IMAGE_TAG_VERSION_INFRA" ]]; then
  echo "❌ ERROR: IMAGE_TAG_VERSION_INFRA environment variable is not set or empty."
  exit 1
fi

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
