"""
Dagger module for Docker Bake with security scanning.

This module orchestrates:
1. Building images with Docker Bake
2. Scanning images with Trivy for vulnerabilities
3. Pushing images only if scans pass
"""

import dagger
from dagger import dag, function, object_type


@object_type
class DockerBake:
    """Docker Bake pipeline with security scanning."""

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
        """
        Build images using Docker Bake.

        Args:
            source: Source directory containing Bake files and Dockerfiles
            project_id: GCP project ID
            repo_name: Artifact Registry repository name
            docker_socket: Docker socket for accessing Docker daemon
            gcloud_config: Gcloud config directory (~/.config/gcloud) for ADC auth
            bake_files: List of Bake HCL files to use (e.g. ["vars.hcl", "docker-bake-lint-and-test.hcl"])
            bake_targets: List of Bake targets to build (e.g. ["default", "validate"])
            location: GCP region (default: europe-west1)
            image_tag: Image tag version (default: latest)
            push: Whether to push images to registry

        Returns:
            Build output from Docker Bake
        """
        push_flag = "--push" if push else "--load"

        # Build the bake command with all files and targets
        bake_cmd = ["docker", "buildx", "bake"]
        for f in bake_files:
            bake_cmd.extend(["-f", f])
        bake_cmd.append(push_flag)
        bake_cmd.extend(bake_targets)

        # Use pre-built base image with Docker + buildx + gcloud
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
            .with_env_variable("IMAGE_TAG_VERSION_APP", image_tag)
            .with_env_variable("IMAGE_TAG_VERSION_INFRA", image_tag)
            .with_exec(["gcloud", "auth", "configure-docker", f"{location}-docker.pkg.dev", "--quiet"])
            .with_exec(bake_cmd)
            .stdout()
        )

    @function
    async def scan(
        self,
        image: str,
        docker_socket: dagger.Socket,
        severity: str = "HIGH,CRITICAL",
    ) -> str:
        """
        Scan a Docker image with Trivy for vulnerabilities.

        Args:
            image: Full image reference to scan
            docker_socket: Docker socket for accessing local images
            severity: Comma-separated severity levels to check (default: HIGH,CRITICAL)

        Returns:
            Trivy scan report
        """
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

    @function
    async def build_scan_push(
        self,
        source: dagger.Directory,
        project_id: str,
        repo_name: str,
        docker_socket: dagger.Socket,
        gcloud_config: dagger.Directory,
        bake_files: list[str],
        bake_targets: list[str],
        images_to_scan: list[str],
        location: str = "europe-west1",
        severity: str = "HIGH,CRITICAL",
    ) -> str:
        """
        Full pipeline: build images with Bake, scan with Trivy, push if clean.

        Args:
            source: Source directory containing Bake files and Dockerfiles
            project_id: GCP project ID
            repo_name: Artifact Registry repository name
            docker_socket: Docker socket for accessing Docker daemon
            gcloud_config: Gcloud config directory (~/.config/gcloud) for ADC auth
            bake_files: List of Bake HCL files to use (e.g. ["vars.hcl", "docker-bake-lint-and-test.hcl"])
            bake_targets: List of Bake targets to build (e.g. ["default", "validate"])
            images_to_scan: List of image names to scan with Trivy (e.g. ["python-linter:latest", "python-tests:latest"])
            location: GCP region (default: europe-west1)
            severity: Vulnerability severity threshold (default: HIGH,CRITICAL)

        Returns:
            Pipeline execution summary
        """
        repo_url = f"{location}-docker.pkg.dev/{project_id}/{repo_name}"

        full_image_refs = [f"{repo_url}/{img}" for img in images_to_scan]

        results = []
        results.append("=== STEP 1: Building images with Docker Bake ===")

        build_output = await self.bake(
            source=source,
            project_id=project_id,
            repo_name=repo_name,
            docker_socket=docker_socket,
            gcloud_config=gcloud_config,
            bake_files=bake_files,
            bake_targets=bake_targets,
            location=location,
            push=False,
        )
        results.append(build_output)
        results.append("Build completed successfully.\n")

        results.append("=== STEP 2: Scanning images with Trivy ===")

        scan_passed = True
        for image in full_image_refs:
            results.append(f"\nScanning {image}...")
            try:
                scan_output = await self.scan(
                    image=image,
                    docker_socket=docker_socket,
                    severity=severity,
                )
                results.append(scan_output)
                results.append(f"Scan passed for {image}")
            except dagger.ExecError as e:
                results.append(f"Vulnerabilities found in {image}!")
                results.append(str(e))
                scan_passed = False

        if not scan_passed:
            results.append("\n=== PIPELINE FAILED ===")
            results.append("Security scan found vulnerabilities. Images NOT pushed.")
            return "\n".join(results)

        results.append("\n=== STEP 3: Pushing images to registry ===")

        push_output = await self.bake(
            source=source,
            project_id=project_id,
            repo_name=repo_name,
            docker_socket=docker_socket,
            gcloud_config=gcloud_config,
            bake_files=bake_files,
            bake_targets=bake_targets,
            location=location,
            push=True,
        )
        results.append(push_output)

        results.append("\n=== PIPELINE SUCCEEDED ===")
        results.append("All images built, scanned, and pushed successfully.")

        return "\n".join(results)
