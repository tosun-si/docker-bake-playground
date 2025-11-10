# docker-bake-playground

A curated collection of concrete, practical, and reusable examples for mastering Docker Bake.


## Build the images with Docker Bake locally

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl
```

## Build and publish the images with Docker Bake locally

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --push
```

## Printing the Bake file with the --print flag shows the interpolated value in the resolved build configuration.

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --print
```

## Build the images for linter and tests

```bash
docker buildx bake -f vars.hcl -f docker-bake-lint-and-test.hcl validate
```

## Run linter and tests with Compose

```bash
docker compose -f compose_lint_and_test.yaml up
```

## Build the multiples Bake files locally

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl -f docker-bake-lint-and-test.hcl default validate
```

## Print multiple Bake files

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl -f docker-bake-lint-and-test.hcl default validate --print
```

## Build Bake file with inheritance

```bash
docker buildx bake -f vars.hcl -f docker-bake-inheritence.hcl
```

## Build Bake file with matrix variants

```bash
docker buildx bake -f vars.hcl -f docker-bake-matrix-variants.hcl
```

## Build Bake file with matrix items

```bash
docker buildx bake -f vars.hcl -f docker-bake-matrix-items.hcl app
```

## Build Bake file from Compose file

```bash
docker buildx bake -f compose_bake_example.yaml
```

## Run app and infra Composer file

```bash
docker compose -f compose_bake_example.yaml up
```

## Build bake file from a GitHub repo

```bash
docker buildx bake -f bake.hcl "https://github.com/crazy-max/buildx.git#remote-with-local" --print
```

## Build bake file from combining a local file with a remote file from a GitHub repo

```bash
docker buildx bake -f bake.hcl -f cwd://local.hcl "https://github.com/crazy-max/buildx.git#remote-with-local" --print
```

## Docker buildx build command with attestations

```bash
docker build \
    --target=image \
    --tag=bakeme:latest \
    --provenance=true \
    --sbom=true \
    --platform=linux/amd64,linux/arm64,linux/riscv64 \
    .
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