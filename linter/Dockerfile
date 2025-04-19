ARG GO_VERSION="1.23"
ARG GOLANGCI_LINT_VERSION="1.61"

FROM golangci/golangci-lint:v${GOLANGCI_LINT_VERSION}-alpine AS lint
RUN --mount=target=.,rw \
    golangci-lint run \
