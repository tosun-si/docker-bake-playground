# Docker Bake in Practice — Part 1: From Bash Scripts to Declarative Builds

*The first of a two-part series. Part 1 covers the fundamentals: what Bake is, why it exists, and the features that make it worth adopting. Part 2 will cover CI/CD integrations — Cloud Build, GitHub Actions, GitLab CI, and Dagger.*

---

## Why this article exists

For the past two years I've been giving a talk about Docker Bake at conferences across France and Morocco — **DevLille**, **DevFest Toulouse**, **DevFest Lyon**, **Devoxx Morocco**, and **Cloud Native Days France**. Every time I deliver it, the same thing happens: people come up afterwards and say *"I had no idea Bake could do that"* or *"I've been writing 200-line bash scripts to do exactly this."*

If you want the video version in French, you can watch the [Cloud Native Days France recording](https://youtu.be/WVWzwRLinzc). An English video walking through these articles is coming soon on my [YouTube channel](https://www.youtube.com/channel/UCPnHZ14R5oF8LQAc7f4mKNg/?sub_confirmation=1) — subscribe if you'd like to be notified. If you prefer to read at your own pace, with copy-pasteable snippets, this article is for you.

All the code in this article comes from my companion repository: [`docker-bake-playground`](https://github.com/tosun-si/docker-bake-playground). Each section links to the relevant file so you can run the examples yourself.

*The code examples push to Google Cloud Artifact Registry, but Docker Bake is registry-agnostic — every snippet works against Docker Hub, ECR, ACR, or GHCR by changing the target tag.*

---

## The foundation: BuildKit, Buildx, and Bake

Before we touch a single HCL file, let's clear up the layering. These three names get thrown around as if they were interchangeable, but they sit on top of each other.

```
+----------------------------------------------------+
|  Bake                (declarative orchestration)   |
|  docker buildx bake -f file.hcl                    |
+----------------------------------------------------+
|  Buildx              (CLI plugin / frontend)       |
|  docker buildx build ...                           |
+----------------------------------------------------+
|  BuildKit            (build engine / backend)      |
|  parallel stages, cache mounts, multi-platform     |
+----------------------------------------------------+
```

**BuildKit** is the modern Docker build engine. It replaced the legacy builder a few years ago and is now the default in Docker Engine 23+. BuildKit is the piece doing the actual work: it parses your Dockerfile, builds stages in parallel where it can, manages the cache, handles multi-platform builds, mount caches, secrets, SSH forwarding, and so on.

**Buildx** is a Docker CLI plugin that exposes BuildKit's features through a friendlier interface. When you type `docker buildx build ...`, you're using Buildx as the frontend and BuildKit as the engine. Buildx also manages *builders* — named BuildKit instances you can swap between (local, remote, container-driven).

**Bake** is a subcommand of Buildx: `docker buildx bake`. It takes one or more declarative files (HCL, JSON, or a Compose file) and orchestrates many builds at once. Think of it as `docker-compose` but for *building* instead of *running*. You define your images once, in one place, and Bake builds them all — in parallel, with shared variables, inheritance, matrices, and groups.

That's the whole stack. You won't lose anything by treating BuildKit as "the engine," Buildx as "the CLI," and Bake as "the orchestrator."

A practical note on what you actually have installed: if you've installed **Docker Desktop** in the last few years, Buildx ships by default — and Buildx bundles BuildKit, so the engine comes with it. Bake is a subcommand of Buildx (`docker buildx bake`), which means the moment you have Buildx, you have Bake too. On Linux with Docker Engine 23+, Buildx is bundled as a CLI plugin out of the box as well. There's nothing extra to install — unless your Docker is unusually old, you can run every example in this article today.

![A whale diving in, ready to build](diagrams/whales/whale-diving-in.png)

---

## The traditional approach: bash scripts

To appreciate why Bake exists, let's start with the pain. Imagine you have two images to build and push: an `app` and an `infra`. Multi-platform (amd64 + arm64), with provenance and SBOM attestations. Here's the straightforward bash version:

```bash
#!/usr/bin/env bash
set -euo pipefail

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
```

This works. But notice four things:

1. **It's sequential.** The `infra` build doesn't start until the `app` build finishes — even though they're completely independent. Parallelizing in bash means wrestling with `&`, `wait`, and `trap` to propagate exit codes correctly. Most teams don't bother, and ship a pipeline that's slower than it needs to be.
2. **It duplicates everything.** The platform list, the attestation flags, the `--push` — copy-pasted across every image.
3. **It scales linearly.** Five images? Five blocks. Ten images? Ten blocks.
4. **It's not portable across operating systems.** This is the silent killer in teams that mix Linux, macOS, and Windows laptops. The bash script above looks innocent, but the moment you refactor it into anything non-trivial you start relying on features that don't exist everywhere — and you end up maintaining a different version of the script per OS.

The natural reflex is to refactor into a loop:

```bash
declare -A paths=(
  [app]="app/Dockerfile"
  [infra]="infra/Dockerfile"
)

for service in "${!paths[@]}"; do
  upper_service="${service^^}"
  tag_var="IMAGE_TAG_VERSION_${upper_service}"
  tag_version="${!tag_var:-}"

  docker build \
    --platform linux/amd64,linux/arm64 \
    --file "${paths[$service]}" \
    --tag "${REPO_URL}/${service}_bake:${tag_version}" \
    --provenance=true \
    --sbom=true \
    --push \
    .
done
```

We've removed duplication, but at a cost: this script now uses associative arrays, indirect variable expansion (`${!tag_var}`), and bash string manipulation (`${service^^}`). Anyone who hasn't written bash in six months will need a few minutes and an LLM or Stack Overflow tab to read this. And it's *still* sequential.

The OS-portability problem gets worse here too. `declare -A` (associative arrays) and `${service^^}` (uppercase expansion) require **bash 4 or newer**. macOS still ships **bash 3.2** by default — Apple froze it years ago over the GPL v3 licensing change — so this exact script silently fails on a fresh Mac unless the developer has manually installed a newer bash via Homebrew. Windows developers need WSL or Git Bash. Linux users are fine. The end result is the dreaded "works on my machine" problem, and it lives in a script that's supposed to be the *standard* way to build images.

This is the moment Bake earns its place.

![A whale carrying a Bake file — relief incoming](diagrams/whales/whale-bake-arrives.png)

---

## Enter Bake: same images, declaratively

Here's the same two builds expressed as a Bake file ([`docker-bake-app-and-infra.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/docker-bake-app-and-infra.hcl)):

```hcl
group "default" {
  targets = ["app", "infra"]
}

target "app" {
  context    = "."
  dockerfile = "images/app/Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REPO_URL}/app_bake:${IMAGE_TAG_VERSION_APP}"]
  attest = [
    "type=provenance,mode=max",
    "type=sbom"
  ]
}

target "infra" {
  context    = "."
  dockerfile = "images/infra/Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = ["${REPO_URL}/infra_bake:${IMAGE_TAG_VERSION_INFRA}"]
  attest = [
    "type=provenance,mode=max",
    "type=sbom"
  ]
}
```

To build both images:

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl
```

To build and push:

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --push
```

Four things to notice:

- **The intent is obvious.** Anyone who reads HCL or Terraform feels at home immediately. No `${!var}` tricks, no array juggling.
- **Parallel by default.** Bake schedules the `app` and `infra` builds concurrently, and BuildKit shares cache layers between them. No `&`, no `wait`, no exit-code plumbing — parallelism is the default behavior, not a feature you opt into. Every target declared in an HCL file is fair game for parallel scheduling. Bash, by contrast, runs a `for` loop sequentially unless you go out of your way to fan it out.
- **One file, every OS.** The same `.hcl` file produces the same builds on Linux, macOS, and Windows — Docker Desktop and Docker Engine normalize the invocation. No bash-version constraints, no per-OS scripts, no Homebrew gymnastics. New team members can clone the repo and `docker buildx bake` regardless of what laptop they're on. This is the standardization point that bash scripts will never give you, no matter how clean you write them.
- **The `group "default"` block** tells Bake what to build when you don't pass a target. You can have multiple groups for different purposes (release builds, dev builds, validation, etc.).

You can also inspect the resolved configuration before building anything:

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --print
```

This prints the fully-interpolated JSON. Invaluable when something behaves unexpectedly.

And if you just want to validate the file — check the HCL syntax, the target definitions, and that referenced variables resolve — without building anything, there's `--check`:

```bash
docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --check
```

I run this in pre-commit hooks and as the first step of every CI pipeline. It catches typos, missing variables, and broken `inherits` references in under a second, before any expensive build kicks off.

---

## Variables and validators

You probably noticed `${REPO_URL}` and `${IMAGE_TAG_VERSION_APP}` in the file above. Those come from a separate file, [`vars.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/vars.hcl), which I always pass first:

```hcl
variable "PROJECT_ID" {
  validation {
    condition     = PROJECT_ID != ""
    error_message = "The variable 'PROJECT_ID' must not be empty."
  }
}

variable "LOCATION" {
  default = "europe-west1"
}

variable "REPO_NAME" {
  validation {
    condition     = REPO_NAME != ""
    error_message = "The variable 'REPO_NAME' must not be empty."
  }
}

variable "IMAGE_TAG_VERSION_APP" {
  validation {
    condition     = IMAGE_TAG_VERSION_APP != ""
    error_message = "The variable 'IMAGE_TAG_VERSION_APP' must not be empty."
  }
}

variable "REPO_URL" {
  default = "${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
}
```

Two things make this worth highlighting:

**Defaults and composition.** `LOCATION` defaults to `europe-west1`. `REPO_URL` is composed from three other variables, so I never type the full Artifact Registry URL anywhere else.

**Validators.** Bake supports `validation` blocks on variables. If `PROJECT_ID` is missing or empty at build time, the build fails immediately with a clear message — *before* a single layer gets built. This is the kind of thing that, in bash, becomes a forest of `if [[ -z "${X:-}" ]]; then echo "..." && exit 1` blocks at the top of every script. Here, it's declarative and lives next to the variable definition.

Variables are populated from the environment, so the usage pattern is just:

```bash
export PROJECT_ID="my-gcp-project"
export REPO_NAME="internal-images"
export IMAGE_TAG_VERSION_APP="0.1.0"
export IMAGE_TAG_VERSION_INFRA="0.1.0"

docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl
```

---

## Inheritance: the `_common` pattern

Look back at the `app` and `infra` targets. They share `context`, `platforms`, and `attest`. Bake supports inheritance, so you can factor that out ([`docker-bake-inheritance.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/docker-bake-inheritance.hcl)):

```hcl
group "default" {
  targets = ["app", "infra"]
}

target "_common" {
  context   = "."
  platforms = ["linux/amd64", "linux/arm64"]
  attest = [
    "type=provenance,mode=max",
    "type=sbom"
  ]
}

target "app" {
  inherits   = ["_common"]
  dockerfile = "images/app/Dockerfile"
  tags       = ["${REPO_URL}/app_bake:${IMAGE_TAG_VERSION_APP}"]
}

target "infra" {
  inherits   = ["_common"]
  dockerfile = "images/infra/Dockerfile"
  tags       = ["${REPO_URL}/infra_bake:${IMAGE_TAG_VERSION_INFRA}"]
}
```

By convention I prefix the inherited target with an underscore (`_common`) to signal "this is a base, don't build it directly." Bake doesn't enforce this — it's just a hint to readers.

---

## A real-world example: Python lint and test images with `uv`

Enough abstract examples. Here's something concrete: a Python application I want to lint with Ruff and test with pytest, both run inside Docker so the CI environment matches local exactly.

I use [`uv`](https://github.com/astral-sh/uv) as the Python package manager because it's an order of magnitude faster than pip or Poetry. The lint image looks like this ([`images/python_linter/Dockerfile`](https://github.com/tosun-si/docker-bake-playground/blob/main/images/python_linter/Dockerfile)):

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.11-alpine AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    WORKDIR=/usr/local/src/app

WORKDIR $WORKDIR

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked

COPY python_app $WORKDIR/python_app

FROM python:3.11-alpine

ENV WORKDIR=/usr/local/src/app
WORKDIR $WORKDIR

COPY --from=builder $WORKDIR $WORKDIR

ENV PATH="$WORKDIR/.venv/bin:$PATH"

ENTRYPOINT ["ruff"]
CMD ["check", "python_app", "--exclude", "tests", "--output-format=concise", "--color=always"]
```

Two patterns worth highlighting:

**Multi-stage build.** The `builder` stage uses the `ghcr.io/astral-sh/uv` image, which already ships with `uv` installed. It resolves dependencies and creates a `.venv`. The final stage is plain `python:3.11-alpine` — no `uv` binary, no build tools, just the runtime and the venv. The result is a smaller, cleaner runtime image.

**`--mount=type=cache` for uv.** The line `RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked` is a BuildKit feature: it gives the `uv sync` step a persistent cache directory that survives across builds. The first build downloads every wheel; every subsequent build reuses them. On a typical project this drops dependency-install time from ~30s to under 2s. It's the single biggest speedup you can add to a Python Dockerfile.

**Layer order matters.** Look closely at the order of operations in the builder stage: we `COPY pyproject.toml uv.lock` *first*, run `uv sync` *second*, and only *then* `COPY python_app`. This is not cosmetic — it's the single most important rule for keeping Docker's layer cache useful. Docker invalidates a layer (and every layer after it) the moment any of its inputs change. If we copied the whole source tree before `uv sync`, every change to a Python file — even a one-character typo fix — would invalidate the dependency-install layer and trigger a full reinstall of every package. By copying *only* the dependency manifest first, the expensive `uv sync` layer stays cached as long as `pyproject.toml` and `uv.lock` are untouched. Code changes only invalidate the cheap final `COPY`. This rule is surprisingly easy to get wrong, and getting it wrong is what turns a 30-second incremental build into a 4-minute one.

The Bake file that ties the lint and test images together is small ([`docker-bake-lint-and-test.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/docker-bake-lint-and-test.hcl)):

```hcl
group "validate" {
  targets = ["lint", "test"]
}

target "lint" {
  context    = "."
  dockerfile = "images/python_linter/Dockerfile"
  tags       = ["${REPO_URL}/python-linter:latest"]
}

target "test" {
  context    = "."
  dockerfile = "images/python_tests/Dockerfile"
  tags       = ["${REPO_URL}/python-tests:latest"]
}
```

Note the group name is `validate`, not `default`. You build it explicitly:

```bash
docker buildx bake -f vars.hcl -f docker-bake-lint-and-test.hcl validate
```

---

## Composing multiple Bake files in one command

In a real project you don't have one Bake file — you have several, each grouped by purpose: app images, infra images, lint/test, scanning, base images. Bake lets you pass any number of `-f` flags and any number of targets:

```bash
docker buildx bake \
  -f vars.hcl \
  -f docker-bake-app-and-infra.hcl \
  -f docker-bake-lint-and-test.hcl \
  default validate
```

This one command builds **four images** — app, infra, lint, test — **all in parallel**. BuildKit deduplicates shared layers across them, so the Python base layer (for example) is fetched once.

Note the trailing `default validate`: when composing multiple Bake files, you have to name the groups (or individual targets) to build — `default` from the app/infra file, `validate` from the lint/test file. Without them, Bake only runs the `default` group and the lint/test images stay unbuilt.

Compare that to the bash version, where parallelizing four `docker build` calls means wrestling with `&`, `wait`, and `trap` to propagate exit codes correctly. With Bake, parallelism is free and correct by default.

---

## Bake from a remote GitHub repository

This one surprises a lot of people: Bake can pull configuration directly from a remote Git repository. No `git clone` needed.

```bash
docker buildx bake \
  -f bake.hcl \
  "https://github.com/crazy-max/buildx.git#remote-with-local" \
  --print
```

The URL acts as both the build context *and* the source of the Bake file. The `#remote-with-local` part is a Git ref (branch, tag, or commit).

Even better, you can **combine a remote Bake file with a local one** using the `cwd://` prefix:

```bash
docker buildx bake \
  -f bake.hcl \
  -f cwd://local.hcl \
  "https://github.com/crazy-max/buildx.git#remote-with-local" \
  --print
```

The remote file provides the shared definitions; your local file overrides values for your environment. This is a clean pattern for sharing reusable Bake configurations across teams without making everyone vendor the same HCL into every repo.

---

## Matrix: building variants of the same image

Here's a use case that comes up constantly in real projects — and the canonical example is the [official PostgreSQL image on Docker Hub](https://hub.docker.com/_/postgres), which ships the same database across multiple base-image variants (Alpine, Bullseye, Bookworm) and multiple Postgres versions for each. That's exactly the pattern I want to demonstrate: you have one application and you need to ship it as many images — different OS bases, different versions per OS. Alpine for size-conscious users, Bullseye and Bookworm for compatibility with glibc-dependent libraries.

A quick guard rail before we go further: **this pattern applies when you're shipping something downstream consumers will pick a base for** — a database, a runtime, a developer tool, a library. Postgres, Python, Node, Ruby, MySQL — every major official image does this. If you're shipping a business application, you typically pick one base and stay there. Don't take the example below and fan your billing service out across five Alpine and Debian variants; you'll just multiply your image count, your scan surface, and your registry bill for no benefit. The point of matrix-variants is to serve multiple downstream audiences from one source, not to spray the same app across every base image you can think of.

In bash, that's a nested loop ([`scripts/build_matrix_variants.sh`](https://github.com/tosun-si/docker-bake-playground/blob/main/scripts/build_matrix_variants.sh)):

```bash
variants=("alpine" "bullseye" "bookworm")
declare -A versions
versions[alpine]="3.17 3.21"
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
```

It works. It's also six images built strictly one after another, and the syntax is hard to read and maintain. Every image you add — and every bit of conditional logic on top — makes it worse.

Here's the same thing in Bake ([`docker-bake-matrix-variants.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/docker-bake-matrix-variants.hcl)):

```hcl
group "default" {
  targets = ["alpine_apps", "bullseye_apps", "bookworm_apps"]
}

target "_common" {
  context = "."
}

target "alpine_apps" {
  inherits = ["_common"]
  name     = "app-${variant}-${replace(version, ".", "-")}"
  matrix = {
    variant = ["alpine"]
    version = ["3.17", "3.21"]
  }
  dockerfile = "images/app-matrix/${variant}-${replace(version, ".", "-")}/Dockerfile"
  tags       = ["myapp:${variant}-${version}"]
}

target "bullseye_apps" {
  inherits = ["_common"]
  name     = "app-${variant}-${replace(version, ".", "-")}"
  matrix = {
    variant = ["bullseye"]
    version = ["11.7", "11.8"]
  }
  dockerfile = "images/app-matrix/${variant}-${replace(version, ".", "-")}/Dockerfile"
  tags       = ["myapp:${variant}-${version}"]
}

target "bookworm_apps" {
  inherits = ["_common"]
  name     = "app-${variant}-${replace(version, ".", "-")}"
  matrix = {
    variant = ["bookworm"]
    version = ["12.2", "12.5"]
  }
  dockerfile = "images/app-matrix/${variant}-${replace(version, ".", "-")}/Dockerfile"
  tags       = ["myapp:${variant}-${version}"]
}
```

Each `matrix` block expands into one target per combination of values. With `variant = ["alpine"]` and `version = ["3.17", "3.21"]`, Bake produces two targets: `app-alpine-3-17` and `app-alpine-3-21`. The `name` template controls the generated names, and `${variant}` and `${version}` are available everywhere in the target.

Run it:

```bash
docker buildx bake -f vars.hcl -f docker-bake-matrix-variants.hcl
```

**All six images build in parallel.** No nested loops, no exit-code propagation, no string substitution gymnastics.

---

## Matrix with a list of items

The matrix above uses cartesian-product expansion (every variant × every version). Sometimes you want something different: a flat list of heterogeneous items, each with their own properties. Bake supports that too ([`docker-bake-matrix-items.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/docker-bake-matrix-items.hcl)):

```hcl
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
  tags       = [item.tag]
}
```

Each entry in the `item` list is an object with its own fields. Inside the target, you reference them as `item.tgt`, `item.dockerf`, etc. This pattern is great when each image has its own Dockerfile path, its own tag, and its own context — but you want to define them all in one place rather than write a target per image.

Run it:

```bash
docker buildx bake -f vars.hcl -f docker-bake-matrix-items.hcl app
```

---

## Bake from a Compose file: one source of truth

Most projects already have a `compose.yaml` that describes how services run together. Bake can read that file directly and use it as build input ([`compose_bake_example.yaml`](https://github.com/tosun-si/docker-bake-playground/blob/main/compose_bake_example.yaml)):

```yaml
services:
  app:
    image: app-bake-example:latest
    build:
      context: .
      dockerfile: images/app/Dockerfile
      args:
        PROJECT_ID: gb-poc-373711
        LOCATION: europe-west1
        REPO_NAME: internal-images
        IMAGE_TAG_VERSION_APP: 0.1.0
      x-bake:
        tags:
          - ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/app_bake:${IMAGE_TAG_VERSION_APP}
        platforms:
          - linux/amd64
          - linux/arm64

  infra:
    image: infra-bake-example:latest
    build:
      dockerfile: images/infra/Dockerfile
      x-bake:
        tags:
          - ${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/infra_bake:${IMAGE_TAG_VERSION_INFRA}
        platforms:
          - linux/amd64
          - linux/arm64
```

The `build` section is standard Compose. The `x-bake` extension is what Bake reads to enrich the build with multi-platform targets, tags, attestations, and other Bake-specific fields that Compose doesn't natively understand.

Build everything with:

```bash
docker buildx bake -f compose_bake_example.yaml
```

Run the same services with:

```bash
docker compose -f compose_bake_example.yaml up
```

**Same file, both lifecycles.** Build configuration and runtime configuration live in one place. For projects where the dev loop is "build, then run, then build again," this is a meaningful ergonomic win.

---

## Wrapping up Part 1

We've covered a lot of ground:

- The **BuildKit / Buildx / Bake** stack and what each layer does.
- The pain of **bash scripts** for multi-image builds, and the two big things Bake gives you that bash never will: **parallel builds by default** (no `&`/`wait` gymnastics) and **a single file that works identically on Linux, macOS, and Windows**.
- **HCL targets**, **groups**, **variables with validators**, and **inheritance**.
- A real **Python multi-stage build** with `uv` and `--mount=type=cache`.
- Composing **multiple Bake files** in a single command.
- Pulling Bake files from a **remote Git repository** and combining them with local overrides.
- **Matrix builds** — both cartesian-product (variants × versions) and item lists.
- Using a **Compose file** as Bake input for a single source of truth.

If you've been writing bash scripts to coordinate `docker build` calls, you now have everything you need to throw them away.

![A whale waving — see you in Part 2](diagrams/whales/whale-see-you-part-2.png)

### Coming in Part 2

Part 2 will focus on **Bake in CI/CD**, which is where the parallelism, declarative configuration, and registry-cache features compound:

- **Google Cloud Build** — running Bake with registry cache against Artifact Registry.
- **GitHub Actions** — using the native Buildx action with GitHub Actions cache.
- **GitLab CI** — pipeline stages with Bake on GitLab.com runners.
- **Dagger** — a portable, programmable pipeline (with the Python SDK) that runs the same way locally and in the cloud. Build → Trivy scan → push, with the whole pipeline expressed as code.
- The **GreenOps** angle: how registry-based Docker cache cuts CI compute time and energy, and how to wire it up correctly across all four tools.

### Talks and resources

- Talk recording (French) — [Docker Bake at Cloud Native Days France](https://youtu.be/WVWzwRLinzc)
- English video version (coming soon) — [my YouTube channel](https://www.youtube.com/channel/UCPnHZ14R5oF8LQAc7f4mKNg/?sub_confirmation=1)
- Talk venues — DevLille, DevFest Toulouse, DevFest Lyon, Devoxx Morocco, Cloud Native Days France
- Companion repository — [`docker-bake-playground`](https://github.com/tosun-si/docker-bake-playground)
- Official Bake documentation — [docs.docker.com/build/bake](https://docs.docker.com/build/bake/)

If you have feedback, questions, or a use case you'd like to see covered in Part 2, reach out on LinkedIn or open an issue on the repo.

---

*If you enjoyed this article, follow me for more content on Docker, AI agents, Google Cloud, Software, Devops, Tech and data engineering:*

- [YouTube](https://www.youtube.com/channel/UCPnHZ14R5oF8LQAc7f4mKNg/?sub_confirmation=1)
- LinkedIn — *add link*
- Medium — *add link*
