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
    --config build-and-publish-images-artifact-registry-cache.yaml \
    --substitutions _REPO_NAME="$REPO_NAME",_IMAGE_TAG_VERSION_APP="$IMAGE_TAG_VERSION_APP",_IMAGE_TAG_VERSION_INFRA="$IMAGE_TAG_VERSION_INFRA" \
    --verbosity="debug" .
```

## Build, scan and publish the images with Dagger locally

Dagger provides a portable CI/CD pipeline that runs the same way locally and in the cloud.
The pipeline builds images with Docker Bake, scans them with Trivy for vulnerabilities, and only pushes if scans pass.

### Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         build-scan-push pipeline                            │
│                                                                             │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐      │
│  │                  │    │                  │    │                  │      │
│  │   1. BAKE        │───▶│   2. SCAN        │───▶│   3. PUSH        │      │
│  │                  │    │                  │    │                  │      │
│  │  Docker Buildx   │    │  Trivy           │    │  Docker Buildx   │      │
│  │  builds images   │    │  scans for       │    │  pushes images   │      │
│  │  (--load)        │    │  vulnerabilities │    │  (--push)        │      │
│  │                  │    │  (HIGH/CRITICAL) │    │                  │      │
│  └──────────────────┘    └────────┬─────────┘    └──────────────────┘      │
│                                   │                                         │
│                          ┌────────▼─────────┐                              │
│                          │  Vulnerabilities │                              │
│                          │     found?       │                              │
│                          └────────┬─────────┘                              │
│                                   │                                         │
│                    ┌──────────────┴──────────────┐                         │
│                    │                             │                         │
│                    ▼                             ▼                         │
│             ┌─────────────┐              ┌─────────────┐                   │
│             │    YES      │              │     NO      │                   │
│             │  Pipeline   │              │  Continue   │                   │
│             │   FAILS     │              │  to PUSH    │                   │
│             └─────────────┘              └─────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Prerequisites

- [Dagger CLI](https://docs.dagger.io/install) installed
- Docker running

### Go inside the Dagger folder:

```bash
cd dagger
```

### Run the full pipeline (build + scan + push) - scan passes

```bash
dagger call build-scan-push \
    --source=.. \
    --project-id=gb-poc-373711 \
    --repo-name=internal-images \
    --docker-socket=/var/run/docker.sock \
    --gcloud-config=$HOME/.config/gcloud \
    --bake-files=vars.hcl,docker-bake-scan-pass.hcl \
    --bake-targets=scan-pass \
    --images-to-scan=alpine-simple:latest
```

### Run the full pipeline (build + scan + push) - scan fails

```bash
dagger call build-scan-push \
    --source=.. \
    --project-id=gb-poc-373711 \
    --repo-name=internal-images \
    --docker-socket=/var/run/docker.sock \
    --gcloud-config=$HOME/.config/gcloud \
    --bake-files=vars.hcl,docker-bake-lint-and-test-cache.hcl \
    --bake-targets=validate \
    --images-to-scan=python-tests:latest
```

### Run with multiple Bake files and targets

```bash
dagger call build-scan-push \
    --source=.. \
    --project-id=gb-poc-373711 \
    --repo-name=internal-images \
    --docker-socket=/var/run/docker.sock \
    --gcloud-config=$HOME/.config/gcloud \
    --bake-files=vars.hcl,docker-bake-app-and-infra.hcl,docker-bake-lint-and-test-cache.hcl \
    --bake-targets=default,validate \
    --images-to-scan=app_bake:0.1.0,infra_bake:0.1.0,python-linter:latest,python-tests:latest
```

### Run only the build step (without scanning or pushing)

```bash
dagger call bake \
    --source=.. \
    --project-id=gb-poc-373711 \
    --repo-name=internal-images \
    --docker-socket=/var/run/docker.sock \
    --gcloud-config=$HOME/.config/gcloud \
    --bake-files=vars.hcl,docker-bake-lint-and-test-cache.hcl \
    --bake-targets=validate
```

### Scan a specific image with Trivy

```bash
dagger call scan \
    --image=europe-west1-docker.pkg.dev/gb-poc-373711/internal-images/python-linter:latest \
    --docker-socket=/var/run/docker.sock
```

### Pre-built base image for fast pipelines

The Dagger module uses a pre-built base image (`dagger-bake-base`) with Docker CLI, buildx, and gcloud pre-installed. This eliminates installation time and provides ~20x faster pipeline execution.

**Build and push the base image (one-time setup):**

```bash
docker buildx bake -f vars.hcl -f docker-bake-dagger-base.hcl --push dagger-base
```

### Docker Bake registry cache

Use the cache-enabled Bake file to cache build layers in the registry:

```bash
dagger call build-scan-push \
    --source=.. \
    --project-id=gb-poc-373711 \
    --repo-name=internal-images \
    --docker-socket=/var/run/docker.sock \
    --gcloud-config=$HOME/.config/gcloud \
    --bake-files=vars.hcl,docker-bake-lint-and-test-cache.hcl \
    --bake-targets=validate \
    --images-to-scan=python-linter:latest,python-tests:latest
```

The `docker-bake-lint-and-test-cache.hcl` file uses `cache-from` and `cache-to` to store and retrieve build layers from the registry:

```hcl
target "lint" {
  cache-from = ["type=registry,ref=${REPO_URL}/python-linter:cache"]
  cache-to   = ["type=registry,ref=${REPO_URL}/python-linter:cache,mode=max"]
}
```

## Build, scan and publish the images with Dagger Cloud

Dagger Cloud provides pipeline visualization, caching, and debugging capabilities.

### Setup

1. Create a [Dagger Cloud](https://dagger.cloud) account
2. Get your token from the Dagger Cloud dashboard
3. Set the environment variable:

```bash
export DAGGER_CLOUD_TOKEN=your-token-here
```

### Run with Dagger Cloud

Once `DAGGER_CLOUD_TOKEN` is set, the same commands work with traces sent to Dagger Cloud:

```bash
dagger call build-scan-push \
    --source=.. \
    --project-id=gb-poc-373711 \
    --repo-name=internal-images \
    --docker-socket=/var/run/docker.sock \
    --gcloud-config=$HOME/.config/gcloud \
    --bake-files=vars.hcl,docker-bake-lint-and-test-cache.hcl \
    --bake-targets=validate \
    --images-to-scan=python-linter:latest,python-tests:latest
```

Pipeline traces and logs will be available in your Dagger Cloud dashboard.