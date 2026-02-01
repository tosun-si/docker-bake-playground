# Docker Bake Playground - Project Context

## Overview

A curated collection of practical examples for mastering Docker Bake, with CI/CD integrations for Cloud Build, GitHub Actions, GitLab CI, and Dagger.

This project is used for conference talks and will be featured in blog articles and YouTube videos.

## Key Concepts Demonstrated

### Python Lint & Test Images
- Uses **uv** as package manager
- Shows how to install Python with uv and Docker
- Demonstrates **Docker cache** optimization with `--mount=type=cache`
- Uses **multi-stage builds** for smaller final images

### App & Infra Images
- First demonstrates the traditional approach with `docker buildx` CLI
- Then shows the same with Bake's more elegant and modern HCL syntax
- **Bake advantage**: Executes all images in parallel automatically

### Matrix Variants
- Example building Docker images with different versions of **Alpine and Bullseye**
- Bake makes it easy and efficient (parallel execution)
- Comparison with bash/CLI approach shows:
  - CLI syntax is not readable
  - CLI is not efficient (images built sequentially by default)
  - Bake syntax is clean and parallel by default

### Matrix with List of Items
- Configure a list of images (list of items)
- Apply a for loop via the matrix
- Build multiple images from a single target definition

### Shared Variables & Validators
- Shows how to use validators in Bake for shared variables
- Ensures required variables are set before building

### Bake from Compose
- Build and runtime configuration in the same place
- Use existing `compose.yaml` as Bake input

### CI/CD Integrations
| Tool | Key Feature |
|------|-------------|
| **GitHub Actions** | Native integration |
| **GitLab CI** | Pipeline stages |
| **Cloud Build** | GCP native |
| **Dagger** | Portable (depends only on Docker), based on programming languages (SDKs as code) |

### Docker Cache in CI/CD (GreenOps)
- Uses `cache-from` and `cache-to` in Bake files
- Registry-based cache between CI/CD pipeline runs
- Optimizes pipelines for **GreenOps** practices (reduce compute, faster builds)
- Topic presented at several conferences

## Project Structure

```
docker-bake-playground/
├── images/                          # Dockerfile directories
│   ├── alpine-simple/               # Simple Alpine image (passes Trivy scan)
│   ├── dagger-bake-base/            # Base image for Dagger pipelines
│   ├── python_app/                  # Python application
│   ├── python_infra/                # Python infrastructure
│   ├── python_linter/               # Ruff linter image
│   └── python_tests/                # Pytest image
├── dagger/                          # Dagger module
│   ├── dagger.json                  # Module config (sdk: python, source: src)
│   └── src/
│       ├── pyproject.toml           # Python package config
│       └── docker_bake/
│           ├── __init__.py          # Exports DockerBake class
│           └── main.py              # Main logic (bake, scan, build_scan_push)
├── .github/workflows/               # GitHub Actions
├── .gitlab-ci.yml                   # GitLab CI
├── vars.hcl                         # Shared variables (REPO_URL)
├── docker-bake-*.hcl                # Various Bake configurations
└── compose_*.yaml                   # Docker Compose files
```

## Key Bake Files

| File | Purpose |
|------|---------|
| `vars.hcl` | Shared variables (always include first) |
| `docker-bake-app-and-infra.hcl` | App and infra images |
| `docker-bake-lint-and-test.hcl` | Linter and test images |
| `docker-bake-lint-and-test-cache.hcl` | Same with registry cache |
| `docker-bake-scan-pass.hcl` | Alpine image that passes Trivy scan |
| `docker-bake-dagger-base.hcl` | Base image for Dagger pipelines |
| `docker-bake-inheritence.hcl` | Inheritance examples |
| `docker-bake-matrix-variants.hcl` | Matrix variant examples |

## Dagger Module

### Functions

| Function | Description |
|----------|-------------|
| `bake()` | Build images with Docker Bake |
| `scan()` | Scan image with Trivy for vulnerabilities |
| `build_scan_push()` | Full pipeline: build → scan → push (if clean) |

### Key Parameters

- `--source`: Source directory (use `..` from dagger folder)
- `--project-id`: GCP project ID (e.g., `gb-poc-373711`)
- `--repo-name`: Artifact Registry repo (e.g., `internal-images`)
- `--docker-socket`: Docker socket path (`/var/run/docker.sock`)
- `--gcloud-config`: Gcloud config dir (`$HOME/.config/gcloud`)
- `--bake-files`: Comma-separated list of HCL files
- `--bake-targets`: Comma-separated list of targets
- `--images-to-scan`: Comma-separated list of images to scan

### Pre-built Base Image

The Dagger module uses `dagger-bake-base` image with Docker CLI, buildx, and gcloud pre-installed for ~20x faster execution.

Build the base image (one-time):
```bash
docker buildx bake -f vars.hcl -f docker-bake-dagger-base.hcl --push dagger-base
```

### Running Dagger Commands

Always run from the `dagger/` directory:
```bash
cd dagger
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

## GCP Configuration

- **Location**: `europe-west1`
- **Project ID**: `gb-poc-373711`
- **Registry**: `europe-west1-docker.pkg.dev/gb-poc-373711/internal-images`
- **Authentication**: Uses gcloud ADC via mounted config directory

## Docker Bake Commands

```bash
# Build locally
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl

# Build and push
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --push

# Print resolved config
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --print

# Multiple files and targets
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl -f docker-bake-lint-and-test.hcl default validate
```

## Environment Variables

Set in `vars.hcl` or as env vars:
- `PROJECT_ID`: GCP project
- `LOCATION`: GCP region (default: europe-west1)
- `REPO_NAME`: Artifact Registry repository name
- `IMAGE_TAG_VERSION_APP`: App image tag
- `IMAGE_TAG_VERSION_INFRA`: Infra image tag

## Trivy Scanning

- Default severity: `HIGH,CRITICAL`
- Exit code 1 on vulnerabilities found
- `alpine-simple:latest` passes scan (use for demos)
- `python-linter:latest`, `python-tests:latest` fail scan (Python base has CVEs)

## Dagger Cloud

Set `DAGGER_CLOUD_TOKEN` to enable tracing:
```bash
export DAGGER_CLOUD_TOKEN=your-token-here
```

## Code Style

- Python: Uses Ruff for linting
- HCL: Docker Bake format with variables
- Module structure: `main.py` for logic, `__init__.py` for exports

## Common Tasks

### Add a new Bake target
1. Create Dockerfile in `images/<name>/`
2. Add target in appropriate `docker-bake-*.hcl` file
3. Add to group if needed

### Modify Dagger pipeline
1. Edit `dagger/src/docker_bake/main.py`
2. Test with `dagger call <function> ...`

### Update base image
1. Modify `images/dagger-bake-base/Dockerfile`
2. Rebuild: `docker buildx bake -f vars.hcl -f docker-bake-dagger-base.hcl --push dagger-base`
