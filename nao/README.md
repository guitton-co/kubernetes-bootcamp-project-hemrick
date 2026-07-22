# nao

Data-analyst chat agent ([getnao.io](https://getnao.io)), deployed on the
cohort's Kubernetes cluster (namespace `hemrick`).

This folder contains **no application code**: the vendor image
`getnao/nao:latest` ships the runtime, `nao/` only provides the project
context (config, prompts, table docs) copied into it by the `Dockerfile`.

## What it does

A `Deployment` with 2 containers per pod (unlike `../instacart-pipeline`'s
`CronJob`, `nao` is a long-running HTTP service):

1. **`nao-chat`** — the chat itself, port `5005`. Queries BigQuery
   (`analytics-with-emeric.gold_instacart`, same project and same
   service-account key as `instacart-pipeline`) and stores its auth/session
   data (`better-auth`) in Postgres.
2. **`cloud-sql-proxy`** — sidecar that exposes the Cloud SQL instance
   (`analytics-with-emeric:us-central1:nao-db`) on `localhost:5432` inside
   the pod; `nao-chat` connects to it via `DB_URI`.

Also exists as a Cloud Run deployment (`service.yaml`, `db_start.sh`,
`db_stop.sh`) — this README covers the Kubernetes path only.

## Consistency with `instacart-pipeline` — and differences

Same deployment approach as `../instacart-pipeline` for everything that's
shareable: image pushed to **GCP Artifact Registry** (not GHCR), same
service account (`bigquery-load-dbt@analytics-with-emeric.iam.gserviceaccount.com`),
same pull Secret (`gar-pull-secret`, same registry → one Secret for both
projects), same IAM model (`roles/artifactregistry.reader` per repo). See
`../instacart-pipeline/README.md` for the details of that shared
foundation.

What differs, and why:

| | `instacart-pipeline` | `nao` | Why |
| - | - | - | - |
| K8s object type | `CronJob` | `Deployment` + `Service` (+ optional `Ingress`) | `nao` serves HTTP continuously (chat), `instacart-pipeline` runs then stops — different K8s semantics. |
| Containers per pod | 1 | 2 (`nao-chat` + `cloud-sql-proxy` sidecar) | `nao` needs a live connection to Postgres (`better-auth` session/auth data); the pipeline has no runtime database dependency. |
| K8s Secrets | `instacart-gcp-credentials` (GCP key) only | `instacart-gcp-credentials` (reused) **+** `nao-secrets` (`OPENAI_API_KEY`, `BETTER_AUTH_SECRET`, `DB_URI`) | `nao` has its own app credentials (LLM, auth) that the pipeline doesn't need. |
| Image build | one `Dockerfile`, one config | `--build-arg NAO_CONFIG_FILE=nao_config.k8s.yaml` (see §1) | `nao` also runs on Cloud Run with a different config (ADC, no mounted key file) — two image variants are needed so building for K8s doesn't break Cloud Run. `instacart-pipeline` has no such constraint: its Cloud Run version already mounted the key the same way as on K8s. |
| External dependency to start manually | None | Cloud SQL instance `nao-db` (`./db_start.sh` / `./db_stop.sh`) | Cost control: the same start/stop logic as on Cloud Run is kept to avoid paying for Cloud SQL compute continuously. |
| Exposure | None (the output lands in BigQuery) | `Service` (ClusterIP) + `port-forward`, optional `Ingress` | A `CronJob` has nothing to expose; `nao` needs to be reachable from a browser. |

## Prerequisites

- A GCP service-account key with access to `gold_instacart` (read) and the
  project (`roles/bigquery.jobUser`), plus `roles/cloudsql.client` for the
  proxy — same key as `instacart-pipeline`.
- That same SA needs `roles/artifactregistry.reader` on the `nao` AR repo —
  **confirmed necessary**: the repo's IAM policy was empty by default (no
  read access inherited from the Cloud Run flow), see §2.
- `kubectl`, `docker`, `gcloud` installed locally; push access to
  `us-central1-docker.pkg.dev/analytics-with-emeric/nao` (`gcloud auth
  login` then `gcloud auth configure-docker us-central1-docker.pkg.dev`,
  once — already done if you followed `instacart-pipeline/README.md` §3.2).
- The Cloud SQL instance `nao-db` must be running (`./db_start.sh`) before
  deploying or scaling the Deployment — the `cloud-sql-proxy` sidecar can't
  connect otherwise.

## 1. Build + push the image (amd64)

Different config from the Cloud Run variant: no ADC on the DO cluster, so
`nao_config.k8s.yaml` (with `credentials_path`) replaces
`nao_config.prod.yaml` at build time, via the `Dockerfile`'s `ARG`. Distinct
tag (`k8s-latest`) so it doesn't overwrite the `latest` tag used by Cloud
Run.

```sh
gcloud auth login                                          # once, and again if the token expires (see Troubleshooting)
gcloud auth configure-docker us-central1-docker.pkg.dev     # once

docker buildx build --platform linux/amd64 \
  --build-arg NAO_CONFIG_FILE=nao_config.k8s.yaml \
  -t us-central1-docker.pkg.dev/analytics-with-emeric/nao/nao-chat:k8s-latest \
  --push .
```

The base image (`getnao/nao:latest`) is large (~1.2GB) — the first push to
a given registry/tag can take a while (up to 20-30 min on a slow or
unstable connection, e.g. shared café wifi). If the connection drops
mid-push, rerun the exact same command: layers already fully uploaded are
detected via their digest and skipped, only the interrupted layer (and
anything not yet started) gets re-uploaded — not a full restart from zero.
Prefer a stable connection for this step when possible.

## 2. Give the cluster access to Artifact Registry

**One-time setup**: the SA used to pull must have
`roles/artifactregistry.reader` on the `nao` repo, otherwise the pull fails
with `ImagePullBackOff` / `403 Forbidden` even with the Secret below:

```sh
gcloud artifacts repositories add-iam-policy-binding nao \
  --location=us-central1 --project=analytics-with-emeric \
  --member="serviceAccount:bigquery-load-dbt@analytics-with-emeric.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

The remote Node has no GCP identity by default — it also needs a dedicated
Kubernetes Secret to authenticate (if `gar-pull-secret` already exists in
`hemrick`, created for `instacart-pipeline`, no need to recreate it — same
registry; `kubectl create secret` will just error with `already exists`,
which is fine, skip to the next step):

```sh
kubectl create secret docker-registry gar-pull-secret \
  --docker-server=us-central1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat /Users/emerictrossat/code/credentials/analytics-with-emeric-e0d8e4a4e0fe.json)" \
  --docker-email=etrossat@gmail.com \
  -n hemrick
```

`k8s/deployment.yaml` already references this Secret via
`imagePullSecrets`.

## 3. Reuse the existing GCP Secret

`nao` reuses the same service-account key as `instacart-pipeline` (already
mounted in `hemrick` as `instacart-gcp-credentials` — see
`../instacart-pipeline/README.md` §3.4). Nothing to recreate if this Secret
already exists in the namespace.

## 4. Create nao's own secrets

```sh
kubectl create secret generic nao-secrets \
  --from-literal=OPENAI_API_KEY=<value> \
  --from-literal=BETTER_AUTH_SECRET=<value> \
  --from-literal=DB_URI='postgresql://<user>:<pass>@localhost:5432/<db>' \
  -n hemrick
```

`DB_URI` points at `localhost:5432`: `nao-chat` talks to the
`cloud-sql-proxy` sidecar in the same pod, never directly to Cloud SQL.


## 5. Start Cloud SQL and deploy

Only `deployment.yaml` and `service.yaml` are needed to reach nao via
`port-forward` (see §6):

```sh
./db_start.sh   # waits for RUNNABLE before continuing

kubectl -n hemrick apply -f k8s/deployment.yaml -f k8s/service.yaml
kubectl -n hemrick get pods -w
kubectl -n hemrick logs deploy/nao -c nao-chat
kubectl -n hemrick logs deploy/nao -c cloud-sql-proxy
```

`k8s/ingress.yaml` is optional and, as of this writing, **inert on the
cohort cluster** — no Ingress controller is installed there
(`kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx` returns
nothing), so applying it creates the object but nothing serves it. Only
apply it once a controller is confirmed present; `port-forward` is the
reliable access path in the meantime.

## 6. Access it

```sh
kubectl -n hemrick port-forward svc/nao 8080:80
# http://localhost:8080
```

`KUBECONFIG` is per-shell: a new terminal doesn't inherit the `export
KUBECONFIG=...` from another one, and `kubectl` silently falls back to
`~/.kube/config` (likely `docker-desktop`) — if you get `services "nao"
not found`, re-export `KUBECONFIG` in that terminal first (see
`../instacart-pipeline/README.md` §3.1).

`BETTER_AUTH_URL` in `k8s/deployment.yaml` must match the URL actually used
to reach nao (better-auth ties its cookies/redirects to this URL) —
`http://localhost:8080` matches the port-forward above; if an Ingress with
a stable hostname is set up instead (once a controller exists on the
cluster), update this value and redeploy.

## 7. Cleanup

```sh
./db_stop.sh   # stops Cloud SQL compute billing
```

The Deployment/Service can stay in place (no significant compute cost at
rest on the shared cluster) — only `nao-db` costs while it's running.

### Troubleshooting

- **`docker buildx build --push` fails with `error getting credentials`**:
  the gcloud token expired / needs a reauth. Rerun `gcloud auth login`
  (browser flow), then rerun the build.
- **`ImagePullBackOff` with `403 Forbidden` / `failed to fetch oauth token`**
  (`kubectl describe pod ...`): the `gar-pull-secret` Secret exists but the
  SA doesn't have `roles/artifactregistry.reader` on the repo — rerun the
  `gcloud artifacts repositories add-iam-policy-binding` command above
  (one-time setup, only needed again if the SA changes).
- **`cloud-sql-proxy` in `CrashLoopBackOff` / connection errors**: check
  that `nao-db` is `RUNNABLE` (`./db_start.sh`) and that the SA has
  `roles/cloudsql.client`.
- **`nao-chat` doesn't respond to BigQuery queries**: check that the image
  was built with `--build-arg NAO_CONFIG_FILE=nao_config.k8s.yaml`
  (otherwise `nao_config.prod.yaml` is used by default, with no
  `credentials_path`, and BigQuery auth fails for lack of ADC).
- **`kubectl port-forward` fails with `services "nao" not found`**: wrong
  `kubectl` context in this terminal — re-export `KUBECONFIG` (see §6).
