FROM python:3.11-slim AS builder

RUN pip install uv

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN mkdir -p /app/python_packages && uv pip install -r pyproject.toml --target=/app/python_packages

FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /app/python_packages /app/python_packages

ENV PATH="/app/python_packages/bin:$PATH" \
    PYTHONPATH="/app/python_packages:$PYTHONPATH"

COPY python_app/ ./python_app

ENTRYPOINT ["pytest"]
CMD ["python_app/tests","--cov=python","--cov-report=term","--junitxml=reports/test-results.xml","--color=yes"]

