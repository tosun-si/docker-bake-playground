# Docker Bake in Practice — Part 2: Bake in CI/CD (Cloud Build, GitHub Actions, GitLab CI, Dagger)

*The second of a two-part series. [Part 1](#) covered the fundamentals: BuildKit/Buildx/Bake, HCL targets, variables, validators, multi-stage Python builds, matrix builds, and Bake-from-Compose. Part 2 is about running the same Bake file inside a CI/CD pipeline.*

---

## The thesis

In Part 1 I argued that Bake is what you reach for when bash scripts stop scaling locally. Part 2 makes a stronger claim: **Bake is what you reach for when you want your build logic to outlive the CI/CD tool you happen to be using today.**

Here's the pattern that runs through this article: the Bake file doesn't change between CI/CD platforms. The wrapping changes — authentication, runner setup, where the cache lives — but the build definition is the same `vars.hcl` and `docker-bake-*.hcl` files you've already seen. That portability is rare in CI/CD. Most pipelines have business-critical logic encoded in YAML that only one provider understands. Bake lets you keep that logic in HCL and use the YAML for what it's actually good at: telling the platform what to run and how to authenticate.

The other thread woven through this part is **registry-based Docker cache** — the `cache-from` / `cache-to` mechanism that turns five-minute CI builds into thirty-second ones. This is the GreenOps angle I've been presenting at conferences, and it's why every CI/CD section in this article includes a cache configuration.

If you want the video version in French, you can watch the [Cloud Native Days France recording](https://youtu.be/WVWzwRLinzc). An English video walking through these articles is coming soon on my [YouTube channel](https://www.youtube.com/channel/UCPnHZ14R5oF8LQAc7f4mKNg/?sub_confirmation=1) — subscribe if you'd like to be notified. All the code in this article comes from the [`docker-bake-playground`](https://github.com/tosun-si/docker-bake-playground) repository.

*The code examples push to Google Cloud Artifact Registry, but Docker Bake is registry-agnostic — every snippet works against Docker Hub, ECR, ACR, or GHCR by changing the target tag.*

![A whale back for round two — Bake in CI/CD](diagrams/whales/whale-round-two.png)

---

## The pattern that powers everything: registry-based cache

Before we look at any specific CI/CD tool, let's nail down the one feature you'll see in every example: registry-based BuildKit cache.

In a local build, Docker keeps a cache on your laptop's filesystem. In CI, every job typically starts on a fresh runner with no cache — so every layer gets rebuilt from scratch on every commit. That's both slow (5–10 minutes for a Python image) and wasteful (compute time you're paying for, energy your data center is consuming).

The fix is to **push the cache to a registry** and **pull it back on the next build**. BuildKit supports this natively, and Bake exposes it as two target fields:

```hcl
target "lint" {
  context    = "."
  dockerfile = "images/python_linter/Dockerfile"
  tags       = ["${REPO_URL}/python-linter:latest"]
  cache-from = ["type=registry,ref=${REPO_URL}/python-linter:cache"]
  cache-to   = ["type=registry,ref=${REPO_URL}/python-linter:cache,mode=max"]
}
```

Source: [`docker-bake-lint-and-test-cache.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/docker-bake-lint-and-test-cache.hcl).

What this says:
- **`cache-from`** — at build time, try to pull a layer cache from the image `python-linter:cache` in your private registry. If BuildKit finds that the dependency layers haven't changed, it reuses them and skips rebuilds.
- **`cache-to`** — at the end of the build, push the resulting layer cache back to that same tag, so the next CI run can use it.
- **`mode=max`** — push all intermediate layers, not just the final stage. Critical for multi-stage builds, because the build stage's `uv sync` is usually the expensive step you want cached.

The cache image lives in the same Artifact Registry (or whichever private registry you're using) as your real images, on a `:cache` tag. Convention I follow: `<image-name>:cache`.

The impact in numbers, on a representative Python project:
- **Cold build (no cache):** ~4–5 minutes (Python base pull, full `uv sync`, code copy, attestations).
- **Warm build (cache hit on dependencies):** ~30–45 seconds. The `uv sync` step is a no-op, and only the code-copy layer rebuilds.

Multiply that by the number of CI runs per day, across every developer's PR, and you can see why I've been beating the GreenOps drum at conferences. Fewer compute-hours means a smaller bill *and* a smaller energy footprint, with no change to your build logic. Just two lines of HCL.

Every CI/CD section that follows uses this pattern.

---

## Cloud Build: the GCP-native path

If you're already running on Google Cloud, Cloud Build is the most direct way to ship Bake builds to Artifact Registry. It runs as a managed service, has native IAM integration, and the YAML is comparatively small.

Here's the minimal version that builds and pushes the app + infra images ([`build-and-publish-images-artifact-registry.yaml`](https://github.com/tosun-si/docker-bake-playground/blob/main/build-and-publish-images-artifact-registry.yaml)):

```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    script: |
      docker buildx create --use
      docker buildx bake -f vars.hcl -f docker-bake-app-and-infra.hcl --push
    env:
      - 'PROJECT_ID=$PROJECT_ID'
      - 'LOCATION=$LOCATION'
      - 'REPO_NAME=$_REPO_NAME'
      - 'IMAGE_TAG_VERSION_APP=$_IMAGE_TAG_VERSION_APP'
      - 'IMAGE_TAG_VERSION_INFRA=$_IMAGE_TAG_VERSION_INFRA'
```

A few things worth pointing out:

**`docker buildx create --use`.** Cloud Build's default Docker setup uses the legacy builder, which doesn't support all of BuildKit's features (multi-platform, cache export, etc.). Creating a new buildx builder with `create --use` switches to the BuildKit-backed `docker-container` driver. One line, unlocks everything.

**`script:` instead of `args:`.** Older Cloud Build examples chain commands with `args: ['-c', '...']`. The `script:` block is cleaner — it's just bash, with proper indentation. I now use it everywhere.

**Env vars come from substitutions.** `$PROJECT_ID` and `$LOCATION` are built-in Cloud Build substitutions; `$_REPO_NAME` and the version tags are user-defined substitutions passed at submission time. Bake's variables read these from the environment, so no extra glue needed.

Trigger the build:

```bash
gcloud builds submit \
  --project=$PROJECT_ID \
  --region=$LOCATION \
  --config build-and-publish-images-artifact-registry.yaml \
  --substitutions _REPO_NAME="$REPO_NAME",_IMAGE_TAG_VERSION_APP="$IMAGE_TAG_VERSION_APP",_IMAGE_TAG_VERSION_INFRA="$IMAGE_TAG_VERSION_INFRA"
```

### Adding registry cache

To turn on the registry cache, swap the Bake file for the cache-enabled one ([`build-and-publish-images-artifact-registry-cache.yaml`](https://github.com/tosun-si/docker-bake-playground/blob/main/build-and-publish-images-artifact-registry-cache.yaml)):

```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    script: |
      docker buildx create --use
      docker buildx bake -f vars.hcl -f docker-bake-lint-and-test-cache.hcl validate --push
    env:
      - 'PROJECT_ID=$PROJECT_ID'
      - 'LOCATION=$LOCATION'
      - 'REPO_NAME=$_REPO_NAME'
      - 'IMAGE_TAG_VERSION_APP=$_IMAGE_TAG_VERSION_APP'
      - 'IMAGE_TAG_VERSION_INFRA=$_IMAGE_TAG_VERSION_INFRA'
```

Notice that the YAML barely changed. The cache definitions live in the HCL file, not the pipeline file. Swap the HCL, get caching. Cloud Build doesn't need to know anything about it — the cache layers transit through Artifact Registry, which Cloud Build already has push access to.

This is the architectural win: **the CI YAML stays dumb, and the build logic stays in Bake.**

---

## GitHub Actions: native Buildx integration

GitHub Actions has the slickest Bake integration of the four platforms in this article, thanks to two official Docker-maintained actions: [`docker/setup-buildx-action`](https://github.com/docker/setup-buildx-action) and [`docker/bake-action`](https://github.com/docker/bake-action).

Here's the workflow that builds and pushes to Artifact Registry, with GitHub Actions cache enabled ([`.github/workflows/build-with-docker-bake.yaml`](https://github.com/tosun-si/docker-bake-playground/blob/main/.github/workflows/build-with-docker-bake.yaml)):

```yaml
name: Build Docker with Bake

env:
  PROJECT_ID: gb-poc-373711
  LOCATION: europe-west1
  REPO_NAME: internal-images
  IMAGE_TAG_VERSION_APP: '0.1.0'
  IMAGE_TAG_VERSION_INFRA: '0.1.0'
  WORKLOAD_IDENTITY_PROVIDER: 'projects/.../providers/gb-github-actions-ci-cd-provider'
  SA_CI_CD_EMAIL: 'sa-docker-bake@gb-poc-373711.iam.gserviceaccount.com'

on:
  push:

jobs:
  bake:
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write'
    steps:
      - uses: actions/checkout@v3

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: '${{ env.WORKLOAD_IDENTITY_PROVIDER }}'
          service_account: '${{ env.SA_CI_CD_EMAIL }}'

      - name: Configure Docker to use gcloud as a credential helper
        run: gcloud auth configure-docker ${{ env.LOCATION }}-docker.pkg.dev

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push images with Docker Bake
        uses: docker/bake-action@v6
        with:
          files: vars.hcl,docker-bake-app-and-infra.hcl
          targets: default
          push: true
          set: |
            *.cache-from=type=gha
            *.cache-to=type=gha,mode=max
```

Four things to highlight:

**Workload Identity Federation, not JSON keys.** The `permissions: id-token: write` block plus `google-github-actions/auth@v2` gives the workflow a short-lived GCP token in exchange for the GitHub OIDC token. No long-lived service account key in repo secrets, no key rotation. If you take one thing from this section, take this — it's free, it's safer, and it works.

**`docker/bake-action@v6` reads the Bake file directly.** No manual `docker buildx bake` invocation. You point it at the files, name the targets, and it runs them. The action handles the buildx instance, the push flag, and the cache wiring.

**GitHub Actions cache backend (`type=gha`).** GitHub gives every repository a free cache scope, accessible via a special cache backend. The `set: *.cache-from=type=gha` line tells Bake to pull from it; `*.cache-to=type=gha,mode=max` tells it to push to it. The `*.` prefix applies to every target in the Bake file — you don't need to enumerate them.

**The `set:` mechanism is powerful.** It's a key/value override applied at runtime, so you can change tags, cache backends, platforms, or any other target field without editing the HCL. The companion workflow [`build-with-docker-bake-override-params.yaml`](https://github.com/tosun-si/docker-bake-playground/blob/main/.github/workflows/build-with-docker-bake-override-params.yaml) demonstrates this by rewriting tags at runtime:

```yaml
set: |
  test.tags=${{ env.LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPO_NAME }}/test_override:${{ env.IMAGE_TAG_VERSION_APP }}
  lint.tags=${{ env.LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPO_NAME }}/lint_override:${{ env.IMAGE_TAG_VERSION_INFRA }}
  *.cache-from=type=gha
  *.cache-to=type=gha,mode=max
```

Use this for per-environment tag rewriting, per-branch cache scopes, or temporary one-off overrides — without forking your HCL.

### Cache backend choice

In Cloud Build I used `type=registry`. In GitHub Actions I'm using `type=gha`. Why the difference?

- **`type=gha`** is free, has automatic scoping per branch, and requires zero infrastructure. The downside is that it only works inside GitHub Actions runners.
- **`type=registry`** works anywhere, scales as large as your registry, and is shared across CI providers — but you pay for storage and you have to manage the cache image lifecycle.

If you're 100% on GitHub Actions, use `type=gha`. If you have a mixed CI estate or want one cache shared across multiple environments, use `type=registry` everywhere. The Bake file changes by one word.

---

## GitLab CI: Docker-in-Docker with a manual buildx install

GitLab CI doesn't ship a first-party Buildx action, and the default Docker images on most runners don't include the buildx plugin. So the wrapping is a little chunkier here ([`/.gitlab-ci.yml`](https://github.com/tosun-si/docker-bake-playground/blob/main/.gitlab-ci.yml)):

```yaml
image: docker:28.1.1

services:
  - name: docker:dind
    command: ["--registry-mirror=https://mirror.gcr.io"]
    alias: docker

variables:
  DOCKER_TLS_CERTDIR: ""
  PROJECT_ID: gb-poc-373711
  LOCATION: europe-west1
  REPO_NAME: internal-images
  IMAGE_TAG_VERSION_APP: "0.1.0"
  IMAGE_TAG_VERSION_INFRA: "0.1.0"

before_script:
  - apk add --no-cache curl bash
  - mkdir -p /usr/libexec/docker/cli-plugins
  - curl -sSL https://github.com/docker/buildx/releases/download/v0.23.0/buildx-v0.23.0.linux-amd64 \
      -o /usr/libexec/docker/cli-plugins/docker-buildx
  - chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
  - docker buildx version
  - docker buildx create --use
  - docker login -u _json_key --password-stdin https://$LOCATION-docker.pkg.dev < "$GOOGLE_APPLICATION_CREDENTIALS"

build:
  stage: build
  script:
    - |
      docker buildx bake \
        -f vars.hcl \
        -f docker-bake-lint-and-test-cache.hcl \
        validate \
        --push
```

Three things to note:

**Docker-in-Docker is required.** GitLab runners by default use a thin Docker client that talks to a separate daemon. The `services:` block spins up a `docker:dind` container that this job's commands target. The `--registry-mirror=https://mirror.gcr.io` flag is a small optimization that uses Google's public mirror for image pulls instead of Docker Hub directly — meaningfully faster, especially when Hub is rate-limiting.

**Manually installing buildx.** The `before_script:` downloads the buildx binary, drops it into `/usr/libexec/docker/cli-plugins`, and runs `docker buildx create --use` to switch to a BuildKit-backed builder. This boilerplate is annoying but it's a one-time cost per pipeline file.

**Auth via JSON key.** The `docker login` line uses `_json_key` as the username and reads the service account key from `$GOOGLE_APPLICATION_CREDENTIALS`. This is less elegant than GitHub's Workload Identity Federation, but GitLab now supports OIDC against GCP too — for production setups I'd recommend the OIDC path so you can retire the long-lived key.

Once the wrapping is in place, the actual build command is identical to every other platform: `docker buildx bake -f vars.hcl -f docker-bake-lint-and-test-cache.hcl validate --push`. The same HCL files. The same cache configuration in `docker-bake-lint-and-test-cache.hcl` pushes layers to Artifact Registry, where they'll be reused by every subsequent GitLab run *and* every Cloud Build run *and* every developer who builds locally with the cache flags enabled.

That's the cross-platform cache benefit — Artifact Registry is the shared substrate.

---

## Dagger: pipelines as code, with Python

The first three platforms in this article share a common shape: a YAML file that describes a pipeline, parsed by the CI provider. **Dagger is fundamentally different.**

In Dagger, your pipeline *is* code — Python, Go, TypeScript, or others — running inside a containerized engine. You write functions that compose containers, mount directories, run commands, and return results. The engine runs the same way on your laptop and inside any CI runner. There's no YAML schema to learn, no provider-specific actions, and crucially: **the same pipeline runs locally and in CI, byte-for-byte.**

For a Bake-driven workflow, Dagger lets you express something the YAML-based tools can't easily do: a real **build → security-scan → push** pipeline, where the push only happens if the scan passes, and the whole thing is testable as Python code.

### The pipeline shape

Here's the high-level workflow:

```
+----------------+    +---------------+    +----------------+
|                |    |               |    |                |
|  1. BAKE       |--->|  2. SCAN      |--->|  3. PUSH       |
|                |    |               |    |                |
|  Docker Buildx |    |  Trivy scans  |    |  Docker Buildx |
|  builds images |    |  for HIGH /   |    |  pushes images |
|  (--load)      |    |  CRITICAL CVE |    |  (--push)      |
|                |    |               |    |                |
+----------------+    +-------+-------+    +----------------+
                              |
                              v
                      Vulnerabilities?
                       /            \
                      yes            no
                       |              |
                  FAIL the      continue
                  pipeline      to push
```

The pipeline is implemented as a Dagger module in [`dagger/src/docker_bake/main.py`](https://github.com/tosun-si/docker-bake-playground/blob/main/dagger/src/docker_bake/main.py). It exposes three functions, callable from the CLI: `bake()`, `scan()`, and `build_scan_push()`.

### The bake function

```python
@function
async def bake(
    self,
    source: dagger.Directory,
    project_id: str,
    repo_name: str,
    docker_socket: dagger.Socket,
    gcloud_config: dagger.Directory,
    bake_files: list[str],
    bake_targets: list[str],
    location: str = "europe-west1",
    image_tag: str = "latest",
    push: bool = False,
) -> str:
    push_flag = "--push" if push else "--load"

    bake_cmd = ["docker", "buildx", "bake"]
    for f in bake_files:
        bake_cmd.extend(["-f", f])
    bake_cmd.append(push_flag)
    bake_cmd.extend(bake_targets)

    base_image = f"{location}-docker.pkg.dev/{project_id}/{repo_name}/dagger-bake-base:latest"

    return await (
        dag.container()
        .from_(base_image)
        .with_unix_socket("/var/run/docker.sock", docker_socket)
        .with_mounted_directory("/root/.config/gcloud", gcloud_config)
        .with_mounted_directory("/workspace", source)
        .with_workdir("/workspace")
        .with_env_variable("PROJECT_ID", project_id)
        .with_env_variable("REPO_NAME", repo_name)
        .with_env_variable("LOCATION", location)
        .with_exec(["gcloud", "auth", "configure-docker", f"{location}-docker.pkg.dev", "--quiet"])
        .with_exec(bake_cmd)
        .stdout()
    )
```

A few notes:

**`dag.container().from_(...)`** starts from a pre-built base image that has Docker CLI, buildx, and gcloud already installed. The base image itself is built with Bake — there's a [`docker-bake-dagger-base.hcl`](https://github.com/tosun-si/docker-bake-playground/blob/main/docker-bake-dagger-base.hcl) target for it. The pre-built base is the difference between a 10-second pipeline startup and a 3-minute one (installing gcloud from scratch on every run is the bottleneck).

**`with_unix_socket("/var/run/docker.sock", docker_socket)`** is the key piece. We mount the host's Docker socket *into* the Dagger container so that the `docker buildx bake` command running inside Dagger talks to the host's Docker daemon. This sounds odd — why use Dagger if the build runs on the host's Docker? — but it's the right tradeoff: Dagger orchestrates the pipeline (auth, env, fan-out, scan), and BuildKit handles the heavy lifting. You get Dagger's portability *and* full BuildKit features (multi-platform, attestations, cache).

**`with_mounted_directory("/root/.config/gcloud", gcloud_config)`** passes the local gcloud ADC config into the container. Locally this is `$HOME/.config/gcloud`. In CI it's whatever auth config you've set up. Either way, the pipeline code doesn't change — only the input changes.

### The scan function

```python
@function
async def scan(
    self,
    image: str,
    docker_socket: dagger.Socket,
    severity: str = "HIGH,CRITICAL",
) -> str:
    return await (
        dag.container()
        .from_("ghcr.io/aquasecurity/trivy:0.58.0")
        .with_unix_socket("/var/run/docker.sock", docker_socket)
        .with_exec([
            "image",
            "--severity", severity,
            "--exit-code", "1",
            "--no-progress",
            image
        ])
        .stdout()
    )
```

Trivy is pulled directly as a container — no install step. `--exit-code 1` makes Trivy fail the step if it finds any vulnerability at or above the configured severity (HIGH or CRITICAL by default). Dagger surfaces that failure as a Python exception (`dagger.ExecError`), which the orchestrator function catches.

> **Note on Trivy version.** The snippet above pins `ghcr.io/aquasecurity/trivy:0.58.0`. That release is from late 2024 — fine for a demo, but before you ship this pattern to production I'd bump it to the latest stable. Pin to a recent minor (e.g. `0.6x.y`), never use `:latest`. The detection logic and secret/misconfig rules improve constantly, so a stale scanner means missed CVE classes.

### The orchestrator

The `build_scan_push()` function ties the two together: build all images with `--load` (into the local Docker daemon), scan them, and only call `bake()` a second time with `--push=true` if every scan came back clean.

```python
@function
async def build_scan_push(self, ...) -> str:
    # STEP 1: build with --load
    await self.bake(..., push=False)

    # STEP 2: scan each image
    scan_passed = True
    for image in full_image_refs:
        try:
            await self.scan(image=image, ...)
        except dagger.ExecError:
            scan_passed = False

    if not scan_passed:
        return "PIPELINE FAILED: vulnerabilities found, images NOT pushed."

    # STEP 3: push if clean
    await self.bake(..., push=True)
    return "PIPELINE SUCCEEDED."
```

That's the whole shape. It's Python you can read top-to-bottom, with no provider-specific glue.

### Running it

From the `dagger/` directory:

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

The same command runs in CI. No special CI configuration, no provider-specific YAML — the CI just installs Dagger and runs the same command. **This is the portability claim made literal:** the build logic is in HCL (Bake), the pipeline logic is in Python (Dagger), and the CI provider's only job is to invoke `dagger call`.

### Dagger Cloud for observability

If you set `DAGGER_CLOUD_TOKEN`, every pipeline run streams traces to Dagger Cloud, where you get a visual DAG, per-step timings, and full logs — without instrumenting anything. It's the closest thing to "OpenTelemetry for CI pipelines" I've used. For an in-the-room debugging session at a conference, it's a fantastic demo.

---

![A whale in a green ocean — GreenOps](diagrams/whales/whale-greenops.png)

## The GreenOps thread, in numbers

I've been giving versions of this talk for a few years now, and the GreenOps angle is the part that lands hardest with audiences. Here's why.

For a representative Python multi-stage build on a clean CI runner:

| Scenario | Build time | Compute cost | Relative |
|---|---|---|---|
| No cache, every CI run | ~5 min | full | 100% |
| Registry cache, warm | ~30–45 s | one layer | ~10% |
| Registry cache, dependency hit but code changed | ~1 min | code layer | ~20% |

For a team running 50 PR builds and 10 main builds a day, that's the difference between 5 compute-hours and 30 compute-minutes daily — and a corresponding reduction in energy use at the data center.

The Bake side of the equation is tiny: two lines per target.

```hcl
cache-from = ["type=registry,ref=${REPO_URL}/python-linter:cache"]
cache-to   = ["type=registry,ref=${REPO_URL}/python-linter:cache,mode=max"]
```

The CI/CD side either gets a free GitHub Actions cache backend (`type=gha`), or routes through your existing Artifact Registry. No new infrastructure, no new tools. Just declarative cache, expressed where it belongs — alongside the build definition.

If you're a platform team trying to bring CI compute spending down, this is the lowest-hanging fruit I know.

---

## Wrapping up

Let's tie the two parts together.

**Part 1** showed why Bake exists: bash scripts don't scale, aren't parallel, aren't portable across OSes, and turn variable plumbing into a Stack Overflow exercise. Bake replaces them with declarative HCL — targets, groups, variables with validators, inheritance, matrices.

**Part 2** showed what happens when you take that HCL and ship it through real CI/CD pipelines:

- **Cloud Build** runs Bake against Artifact Registry with a few lines of YAML. The cache configuration lives in the HCL, not the YAML.
- **GitHub Actions** offers the most polished integration via `docker/bake-action`, with a free per-repo cache backend (`type=gha`) and clean OIDC auth to GCP via Workload Identity Federation.
- **GitLab CI** needs a manual buildx install over DinD, but the build command itself is unchanged.
- **Dagger** raises the abstraction level: the pipeline becomes Python code that runs identically on your laptop and in CI, with a real build → Trivy scan → push gate.

And running through all four: **registry-based cache** turns slow CI into fast CI, with two lines of HCL per target and no infrastructure changes.

The deeper point — and the one I keep coming back to in conference talks — is that **your build definition shouldn't be a hostage to your CI provider.** The pipeline glue around it (auth, runners, secrets, triggers) is always going to be provider-specific — there's no escaping that, and I don't want to pretend otherwise. But the *build logic itself* — the HCL targets, the cache wiring, the matrix expansion, the multi-platform setup, the attestation flags — is the part that takes years to get right, and it's the part you don't want to rewrite every time you switch CI tools or onboard a new platform. Bake keeps that logic in one declarative layer, separate from the YAML. That's a small superpower that compounds over years.

### Talks and resources

- Talk recording (French) — [Docker Bake at Cloud Native Days France](https://youtu.be/WVWzwRLinzc)
- English video version (coming soon) — [my YouTube channel](https://www.youtube.com/channel/UCPnHZ14R5oF8LQAc7f4mKNg/?sub_confirmation=1)
- Talk venues — DevLille, DevFest Toulouse, DevFest Lyon, Devoxx Morocco, Cloud Native Days France
- Companion repository — [`docker-bake-playground`](https://github.com/tosun-si/docker-bake-playground)
- Official Bake documentation — [docs.docker.com/build/bake](https://docs.docker.com/build/bake/)
- Dagger documentation — [docs.dagger.io](https://docs.dagger.io)
- Trivy — [aquasecurity.github.io/trivy](https://aquasecurity.github.io/trivy)

If Part 1 made you want to throw away your bash scripts, I hope Part 2 made you want to throw away half of your CI YAML too. That's the whole game: less glue, more declarative, runs everywhere.

---

*If you enjoyed this article, follow me for more content on Docker, AI agents, Google Cloud, Software, Devops, Tech and data engineering:*

- [YouTube](https://www.youtube.com/channel/UCPnHZ14R5oF8LQAc7f4mKNg/?sub_confirmation=1)
- LinkedIn — *add link*
- Medium — *add link*
