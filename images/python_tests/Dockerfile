FROM ghcr.io/astral-sh/uv:python3.11-alpine AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    WORKDIR=/usr/local/src/app

WORKDIR /usr/local/src/app

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked

COPY python_app $WORKDIR/python_app

FROM python:3.11-alpine

ENV WORKDIR=/usr/local/src/app
WORKDIR /usr/local/src/app

COPY --from=builder $WORKDIR $WORKDIR

ENV PATH="$WORKDIR/.venv/bin:$PATH"
ENV PYTHONPATH=$WORKDIR

ENTRYPOINT ["pytest"]
CMD ["python_app/tests", "--cov=python_app", "--cov-report=term", "--junitxml=reports/test-results.xml", "--color=yes"]
