FROM base AS build
ARG TARGETOS TARGETARCH BUILD_TAGS
ENV GOOS=$TARGETOS
ENV GOARCH=$TARGETARCH
RUN --mount=target=. \
    --mount=type=cache,target=/go/pkg/mod \
    go build -tags="${BUILD_TAGS}" -o "/usr/bin/bakeme" .

