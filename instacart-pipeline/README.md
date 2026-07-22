# instacart-pipeline

Instacart (Kaggle) → BigQuery data pipeline, on Kubernetes.

Self-contained repo: this folder contains all the code (Python load script +
dbt project) and its own `Dockerfile` — no dependency on the rest of the
repo to build or deploy.

## What it does

A single container, run on demand via a `CronJob`:
1. `ingestion/load_to_bigquery.py` — loads the raw CSVs (GCS) into BigQuery,
   `raw_instacart` dataset, no transformation.
2. `dbt test --select source:raw_instacart` — integrity tests on the raw
   tables (uniqueness, not_null, foreign keys, accepted values). If a test
   fails, the pipeline stops there (`set -euo pipefail` in
   `run_pipeline.sh`).
3. `dbt run --select product_performance` — builds the
   `gold_instacart.product_performance` datamart (product popularity /
   reorder rate).

See `dbt/models/sources.yml` and `dbt/models/gold_instacart/` for the
details.

This README covers 3 ways to run the pipeline, from fastest to most
realistic:

| # | Where | Why |
| - | -- | -------- |
| 1 | Locally with `uv`, no Kubernetes | Validate the business logic (load + dbt tests + datamart) as fast as possible. |
| 2 | On a local Kubernetes (Docker Desktop) | Validate the Docker image and the `CronJob` as-is, without depending on an external registry. |
| 3 | On the cohort's remote cluster (namespace `hemrick`) | Real, scheduled deployment (`schedule` on the `CronJob`). |

## Prerequisites

- A GCP service-account key with access to the source bucket, to
  `raw_instacart` (read/write) and `gold_instacart` (write), plus
  `roles/bigquery.jobUser` on the project.
- Push access to `us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline`
  (Artifact Registry repo, already created for the earlier Cloud Run
  deployment) — needed from section 2 onward. Run `gcloud auth configure-docker
  us-central1-docker.pkg.dev` locally if not already done.
- `kubectl`, `docker`, `uv` installed locally.
- The GCP SA in use must have `roles/artifactregistry.reader` on this repo —
  see section 3 for how the remote cluster gets access.

## 1. Test locally (no cluster)

```sh
uv sync

# Create .env (never committed) and point it at your GCP key
cp .env.example .env
# edit .env: GCP_SERVICE_ACCOUNT_LOAD_AND_DBT=/path/to/your-key.json
# (an absolute path is recommended if the key lives outside the repo —
# configuration.py resolves a relative path against instacart-pipeline/,
# not your cwd)

# dbt_utils is required by the sources.yml tests (unique_combination_of_columns):
uv run dbt deps --project-dir dbt

uv run python ingestion/load_to_bigquery.py
```

Unlike the Python script, `dbt` doesn't read `.env` (the `python-dotenv`
loading only happens in `ingestion/configuration.py`). Export the variable
before the `dbt` commands:

```sh
export GCP_SERVICE_ACCOUNT_LOAD_AND_DBT=/path/to/your-key.json

uv run dbt test --project-dir dbt --profiles-dir dbt --select "source:raw_instacart"
uv run dbt run --project-dir dbt --profiles-dir dbt --select product_performance
```

If everything passes, the business logic is validated — check in BigQuery
that `gold_instacart.product_performance` exists and has rows (sorted by
`times_ordered` descending, popular products like bananas should be at the
top).

## 2. Test on a local Kubernetes (Docker Desktop)

Goal: validate that the Docker image and the `CronJob` work as-is, without
touching the remote registry — Docker Desktop shares the same Docker engine
as your terminal, so an image built locally is directly usable by its
Kubernetes, no push needed.

```sh
# Switch to the local cluster
kubectl config use-context docker-desktop

# Local namespace (same name as on the remote cluster, for consistency)
kubectl create namespace hemrick --dry-run=client -o yaml | kubectl apply -f -

# Native build (no --platform, no --push), tag different from ":latest" so
# Kubernetes uses imagePullPolicy: IfNotPresent (the default behavior) and
# never tries to reach a registry
docker build -t us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:local-test .

# GCP Secret in this local namespace
kubectl create secret generic instacart-gcp-credentials \
  --from-file=service-account.json=/path/to/your-key.json -n hemrick

kubectl -n hemrick apply -f k8s/cronjob.yaml

# Manual job using the local image instead of the :latest tag
kubectl -n hemrick create job --from=cronjob/instacart-pipeline instacart-pipeline-local-test \
  --dry-run=client -o yaml \
  | sed 's|us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:latest|us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:local-test|' \
  | kubectl apply -f -

kubectl -n hemrick get pods -w
kubectl -n hemrick logs job/instacart-pipeline-local-test -f
```

Observable in Lens/FreeLens by selecting the `docker-desktop` context,
namespace `hemrick`, Workloads → Jobs/Pods.

> The `CronJob` references `imagePullSecrets: [gar-pull-secret]` (see
> section 3), which may not exist in this local namespace — doesn't matter
> here: this field is only consulted if a network pull is actually
> attempted, and the image is already cached locally (`IfNotPresent`).

Cleanup (no automatic deletion — see note in section 3):

```sh
kubectl -n hemrick delete job instacart-pipeline-local-test
```

## 3. Deploy on the remote cluster (cohort, namespace `hemrick`)

### 3.1 Connect to the right cluster

```sh
export KUBECONFIG=/Users/emerictrossat/code/credentials/k8s-bootcamp-guittonco-2026-06-kubeconfig.yaml
kubectl config current-context   # should point to the cohort cluster
kubectl get ns | grep hemrick    # your namespace already exists
```

### 3.2 Build + push the image (amd64)

The cluster runs `amd64` — build with `buildx` even from an Apple Silicon
Mac. Same Artifact Registry repo as the earlier Cloud Run deployment:

```sh
gcloud auth login                                          # once, and again if the token expires (see Troubleshooting)
gcloud auth configure-docker us-central1-docker.pkg.dev     # once

docker buildx build --platform linux/amd64 \
  -t us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:latest \
  --push .
```

### 3.3 Give the cluster access to the image (Artifact Registry)

**One-time setup**, done once per GCP project/service account — not on
every deploy: the SA used to pull must have `roles/artifactregistry.reader`
on the repo, otherwise the pull fails with `ImagePullBackOff` and a `403
Forbidden` (even if the Secret below is correct):

```sh
gcloud artifacts repositories add-iam-policy-binding instacart-pipeline \
  --location=us-central1 --project=analytics-with-emeric \
  --member="serviceAccount:bigquery-load-dbt@analytics-with-emeric.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

The remote Node has no GCP identity by default — it also needs a dedicated
Kubernetes Secret to authenticate against Artifact Registry:

```sh
kubectl create secret docker-registry gar-pull-secret \
  --docker-server=us-central1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat /Users/emerictrossat/code/credentials/analytics-with-emeric-e0d8e4a4e0fe.json)" \
  --docker-email=your-email@example.com \
  -n hemrick
```

If this Secret already exists in `hemrick` (created for `nao/`, same
registry), no need to recreate it — `k8s/cronjob.yaml` references the same
`gar-pull-secret` via `imagePullSecrets`.

### 3.4 Create the Secret with the GCP service-account key

**Never commit the key.** Create the Secret directly from the local file:

```sh
kubectl create secret generic instacart-gcp-credentials \
  --from-file=service-account.json=/Users/emerictrossat/code/credentials/analytics-with-emeric-e0d8e4a4e0fe.json \
  -n hemrick
```

### 3.5 Deploy the CronJob

This command doesn't run anything immediately — it registers the `CronJob`
object on the cluster. From then on, Kubernetes **automatically** triggers
a `Job` every day at 6am UTC (`schedule` set in `k8s/cronjob.yaml`), with no
action needed on your part:

```sh
kubectl -n hemrick apply -f k8s/cronjob.yaml
```

### 3.6 Test without waiting for the schedule

```sh
kubectl -n hemrick create job --from=cronjob/instacart-pipeline instacart-pipeline-manual-1
```

Watch the pod separately — `kubectl get jobs,pods -w` (two resource types
+ `--watch`) fails on some kubectl versions with `you may only specify a
single resource type`:

```sh
kubectl -n hemrick get pods -l job-name=instacart-pipeline-manual-1 -w
```

Then, once the pod is `Running` (Ctrl+C to exit the `-w` above):

```sh
kubectl -n hemrick logs job/instacart-pipeline-manual-1 -f
```

If the job already exists (second attempt): `kubectl -n hemrick delete job
instacart-pipeline-manual-1` before rerunning `create job`.

### 3.7 Cleanup

The `CronJob` deliberately has no `ttlSecondsAfterFinished` (test project,
we'd rather keep Jobs visible in Lens than have them disappear
automatically after 10 min). So every Job — manual or scheduled — must be
deleted by hand once reviewed:

```sh
kubectl -n hemrick delete job instacart-pipeline-manual-1
```

### Troubleshooting

- **`docker buildx build --push` fails with `error getting credentials`**:
  the gcloud token expired / needs a reauth. `docker-credential-gcloud`
  fails silently in non-interactive mode — rerun `gcloud auth login`
  (browser flow), then rerun the build.
- **`ImagePullBackOff` with `403 Forbidden` / `failed to fetch oauth token`**
  (`kubectl describe pod ...`): the `gar-pull-secret` Secret exists but the
  SA doesn't have `roles/artifactregistry.reader` on the repo — rerun the
  `gcloud artifacts repositories add-iam-policy-binding` command from §3.3
  (one-time setup, only needed again if the SA changes).
- **The Job fails partway through**: `run_pipeline.sh` uses
  `set -euo pipefail`, so the logs (`kubectl -n hemrick logs job/...`) stop
  right at the step that broke (CSV load, dbt tests, or datamart build).
- **Pod stuck in `Pending`**: `kubectl -n hemrick describe pod <pod>` to
  see the error (missing Secret mount, insufficient resources, etc.).
