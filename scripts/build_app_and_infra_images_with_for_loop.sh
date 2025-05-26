#!/usr/bin/env bash

set -e
set -o pipefail
set -u

if [[ -z "${REPO_URL:-}" ]]; then
  echo "❌ ERROR: REPO_URL environment variable is not set or empty."
  exit 1
fi

declare -A paths=(
  [app]="app/Dockerfile"
  [infra]="infra/Dockerfile"
)

for service in "${!paths[@]}"; do
  upper_service="${service^^}"
  tag_var="IMAGE_TAG_VERSION_${upper_service}"
  tag_version="${!tag_var:-}"

  if [[ -z "$tag_version" ]]; then
    echo "❌ ERROR: Environment variable $tag_var is not set or empty."
    exit 1
  fi

  echo "🔧 Building $service with tag ${tag_version}"

  docker build \
    --platform linux/amd64,linux/arm64 \
    --file "${paths[$service]}" \
    --tag "${REPO_URL}/${service}_bake:${tag_version}" \
    --provenance=true \
    --sbom=true \
    --push \
    .
done
