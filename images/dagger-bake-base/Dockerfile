FROM docker:latest

# Install dependencies for gcloud CLI
RUN apk add --no-cache \
    python3 \
    bash \
    curl \
    libc6-compat

# Install gcloud CLI
RUN curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/opt

ENV PATH="/opt/google-cloud-sdk/bin:$PATH"

# Verify installations
RUN docker --version && gcloud --version

WORKDIR /workspace
