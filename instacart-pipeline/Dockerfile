FROM python:3.13-slim-bookworm

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

COPY ingestion ./ingestion
COPY dbt ./dbt
COPY run_pipeline.sh ./run_pipeline.sh
RUN chmod +x run_pipeline.sh

RUN uv sync --frozen --no-dev

ENV PATH="/app/.venv/bin:$PATH"

RUN dbt deps --project-dir dbt

ENTRYPOINT ["./run_pipeline.sh"]
