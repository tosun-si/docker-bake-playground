# docker-bake-playground

A curated collection of concrete, practical, and reusable examples for mastering Docker Bake.


## Build the images with Docker Bake locally

```bash
docker buildx bake -f vars.hcl -f docker-bake.hcl
```

## Build and publish the images with Docker Bake locally

```bash
docker buildx bake -f vars.hcl -f docker-bake.hcl docker-bake-linter.hcl --push
```

## Printing the Bake file with the --print flag shows the interpolated value in the resolved build configuration.

```bash
docker buildx bake --print -f vars.hcl -f docker-bake.hcl
```

## Docker buildx build command with attestations

```bash
docker buildx build \
    --target=image \
    --tag=bakeme:latest \
    --provenance=true \
    --sbom=true \
    --platform=linux/amd64,linux/arm64,linux/riscv64 \
    .
```

## Build the images for linter and tests

```bash
docker buildx bake -f docker-bake-lint-and-test.hcl validate
```

## Build and publish the images with Docker Bake via Cloud Build

```bash
gcloud builds submit \
    --project=$PROJECT_ID \
    --region=$LOCATION \
    --config build-and-publish-images-artifact-registry.yaml \
    --substitutions _REPO_NAME="$REPO_NAME",_IMAGE_TAG_VERSION_APP="$IMAGE_TAG_VERSION_APP",_IMAGE_TAG_VERSION_INFRA="$IMAGE_TAG_VERSION_INFRA" \
    --verbosity="debug" .
```