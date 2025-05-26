FROM debian:11.8-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl git jq ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY . /app
WORKDIR /app

CMD ["bash"]
