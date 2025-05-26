#!/usr/bin/env bash

set -e
set -o pipefail
set -u

variants=("alpine" "bullseye" "bookworm")
declare -A versions
versions[alpine]="3.17 3.21 3.22"
versions[bullseye]="11.7 11.8"
versions[bookworm]="12.2 12.5"

for variant in "${variants[@]}"; do
  for version in ${versions[$variant]}; do
    dir="images/app-matrix/${variant}-${version//./-}"
    tag="myapp:${variant}-${version}"

    docker buildx build \
      --file "$dir/Dockerfile" \
      --tag "$tag" \
      --platform "linux/amd64" \
      --push \
      "$dir"
  done
done
