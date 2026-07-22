# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this repo is

`k8s-kata` — a Kubernetes bootcamp lab repo (student fork, GitHub handle
`hemrick`). It ships two worked examples (`examples/data-pipeline` for
data/analytics, `examples/web-service` + `examples/nextjs-app` for full-stack)
plus a from-scratch Postgres Helm chart (`apps/postgres/`) meant to be read
end to end. Students build their own project on top and deploy it to a
**shared cohort cluster** on Digital Ocean.

Key facts about the shared cluster (see `WELCOME.md`, `SETUP.md`):
- No local cluster needed — `export KUBECONFIG=<the cohort kubeconfig>`.
- One pre-created namespace per student = GitHub handle lowercased. This
  student's namespace is **`hemrick`**. Never create other namespaces or
  touch anyone else's.
- Airflow + Postgres are already deployed cluster-wide in the `data`
  namespace by the instructor. Students **consume** it, they don't run
  `helmfile sync` themselves.
- Cluster nodes run `amd64`. Any image built on Apple Silicon must use
  `docker buildx build --platform linux/amd64 ... --push`, or it fails with
  `exec format error`.

Repo layout at top level: `README.md` (course overview), `WELCOME.md`
(onboarding checklist), `SETUP.md` (tool + cluster setup), `docs/` (visual
debugging cheatsheet, project ideas), `examples/` (instructor-provided
examples, not to be confused with the student's own project), and
**`instacart-pipeline/`** — this student's actual project (see below).

## `instacart-pipeline/` — this student's project

Instacart (Kaggle) → BigQuery data pipeline, deployed as a Kubernetes
`CronJob` in the `hemrick` namespace. Fully self-contained: its own
`Dockerfile`, own `pyproject.toml`/`uv.lock`, no dependency on the rest of
the repo to build or deploy. Docs and code comments are in French.

### Pipeline steps (`run_pipeline.sh`, run in one container per Job)

1. `ingestion/load_to_bigquery.py` — loads raw CSVs from GCS straight into
   BigQuery (`raw_instacart` dataset), no transformation. Per-table schema
   and source path come from `ingestion/tables/*.yaml` (one YAML per table:
   `aisles`, `departments`, `products`, `orders`, `order_products_prior`,
   `order_products_train`). Loads run independently per table — one table
   failing is logged and doesn't stop the others, but the script still exits
   non-zero overall if any table failed.
2. `dbt test --select source:raw_instacart` — integrity tests on the raw
   tables (uniqueness, not_null, FK relationships, accepted values — see
   `dbt/models/sources.yml`). `run_pipeline.sh` uses `set -euo pipefail`, so a
   failed test here stops the pipeline before step 3 runs.
3. `dbt run --select product_performance` — builds the
   `gold_instacart.product_performance` datamart (product popularity +
   reorder rate, see `dbt/models/gold_instacart/product_performance.sql`).
   No price/revenue data exists in the source, so popularity and reorder
   rate are the only business metrics available.

### Configuration

- `ingestion/configuration.py` is the single source of truth: BigQuery
  project (`analytics-with-emeric`), location (`US`), tables dir, and the
  service-account key path — read from env var
  `GCP_SERVICE_ACCOUNT_LOAD_AND_DBT` (loaded via `.env` locally, or injected
  as a literal path in the cluster).
- `dbt/profiles.yml` is the dbt profile (BigQuery target); `dbt_project.yml`
  and `packages.yml` (`dbt_utils`, for the `unique_combination_of_columns`
  test) round out the dbt project.
- Locally: copy `.env.example` → `.env` and point
  `GCP_SERVICE_ACCOUNT_LOAD_AND_DBT` at a real key file. **Never commit** a
  service-account key — `.gitignore` already blocks `.env` and
  `*service-account*.json`.

### Deploying / operating (namespace `hemrick`)

```sh
# 1. Build + push (amd64 required — cluster nodes are amd64). Same GCP
# Artifact Registry repo used by the earlier Cloud Run deployment.
gcloud auth configure-docker us-central1-docker.pkg.dev   # once
docker buildx build --platform linux/amd64 \
  -t us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:latest \
  --push .

# 2. Pull secret so the cluster (no native GCP identity) can pull from
# Artifact Registry — skip if gar-pull-secret already exists in hemrick
# (shared with the nao/ deployment, same registry host)
kubectl create secret docker-registry gar-pull-secret \
  --docker-server=us-central1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat /path/to/key.json)" \
  --docker-email=you@example.com -n hemrick

# 3. Secret with the GCP key (never commit the key itself)
kubectl create secret generic instacart-gcp-credentials \
  --from-file=service-account.json=/path/to/key.json -n hemrick

# 4. Deploy the CronJob
kubectl -n hemrick apply -f k8s/cronjob.yaml

# 4. Trigger a run without waiting for the schedule
kubectl -n hemrick create job --from=cronjob/instacart-pipeline instacart-pipeline-manual-1
kubectl -n hemrick get jobs,pods -w
kubectl -n hemrick logs job/instacart-pipeline-manual-1
```

`k8s/cronjob.yaml`: schedule `0 6 * * *` (UTC), `concurrencyPolicy: Forbid`,
`backoffLimit: 1`, `activeDeadlineSeconds: 1800`, `ttlSecondsAfterFinished:
600`. GCP credentials are mounted from the `instacart-gcp-credentials` Secret
at `/secrets/gcp/service-account.json`; requests/limits are 100m/256Mi →
500m/512Mi.

### Local dev (outside the cluster)

```sh
uv sync
cp .env.example .env   # then edit GCP_SERVICE_ACCOUNT_LOAD_AND_DBT
uv run python ingestion/load_to_bigquery.py
uv run dbt test --project-dir dbt --profiles-dir dbt --select "source:raw_instacart"
uv run dbt run --project-dir dbt --profiles-dir dbt --select product_performance
```

### Gotchas specific to this project

- GCP service-account key needs: read access to the source GCS bucket
  (`gs://instacard-data-emeric/...`), read/write on `raw_instacart`,
  write on `gold_instacart`, and `roles/bigquery.jobUser` on the project.
- Push access to `us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline`
  (GCP Artifact Registry) is required for the image build/push step, and the
  service account used for `gar-pull-secret` needs `roles/artifactregistry.reader`
  on that repo.
- The dbt tests in step 2 are a hard gate — if they fail, `gold_instacart`
  simply doesn't get (re)built for that run.
