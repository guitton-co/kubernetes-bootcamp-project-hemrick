# k8s-kata — Kubernetes Bootcamp Lab

Your hands-on lab for the cohort. By the end you'll have a real project of your
own — a data pipeline, an app, a model endpoint — running on Kubernetes and
living on your GitHub.

This isn't a CKAD grind. We cover the ~20% of Kubernetes that does ~80% of the
daily work for data and application engineers, and we look at it **visually**
(see [`docs/lens.md`](docs/lens.md)) rather than memorising `kubectl` flags.

## Who this is for

- **Data / analytics engineers** moving a pipeline (dlt, dbt, SQLMesh, Airflow,
  DuckDB…) off your laptop and onto a cluster.
- **Full-stack engineers** who want to deploy, expose, and debug a service
  without becoming a cluster admin.

## What you'll walk away knowing

- The core objects: Pods, Deployments, Services, ConfigMaps, Secrets, PVCs.
- How to take something that runs locally under Docker and orchestrate it on K8s.
- How to read a cluster visually and debug a broken workload fast.
- A finished project on your own GitHub, ready to show.

## How the lab works

1. **Accept the assignment** → you get your own fork of this repo.
2. **Set up your environment** → follow [`SETUP.md`](SETUP.md) (do this before
   the first live session).
3. **Pitch your project** → open a Pull Request using the template and describe
   in 2–3 lines what you want to run on Kubernetes. Louis confirms scope.
4. **Learn from the two worked examples** (below), then build your own thing.
5. **Demo + feedback** → show it running; tell us what to clarify or automate.

Questions between sessions go in the dedicated Slack channel.

## The two worked examples

| Example                                              | For whom           | What it teaches                                                                            |
| ---------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------ |
| [`examples/data-pipeline/`](examples/data-pipeline/) | data / analytics   | Run Airflow on K8s, backed by a Postgres **you deployed**, with DAGs synced from your repo |
| [`examples/web-service/`](examples/web-service/)     | full-stack         | Containerise a FastAPI app and expose it with a Deployment, Service, and Ingress           |
| [`examples/nextjs-app/`](examples/nextjs-app/)       | full-stack (JS/TS) | Containerise a Next.js app (standalone build) and expose it on the cluster                 |

Both are starting points to copy and bend toward your own project — not the
project itself.

## This student's project(s)

Two independent things run in the `hemrick` namespace — not to be confused
with the worked examples above. They share the same GCP project
(`analytics-with-emeric`) and the same service-account credential, but are
otherwise fully separate deployment workflows (different registry, different
Kubernetes workload type).

| Project                                       | What                                                                                          | Workload type                        | Registry               | Docs                          |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------- | ------------------------- | -------------------------------- |
| [`instacart-pipeline/`](instacart-pipeline/) | Instacart (Kaggle) → BigQuery ingestion, dbt source tests, `gold_instacart.product_performance` datamart | Scheduled `CronJob` (run to completion) | GCP Artifact Registry    | [`instacart-pipeline/README.md`](instacart-pipeline/README.md) |
| [`nao/`](nao/)                               | AI data-analyst chat agent ([getnao.io](https://getnao.io)) over `gold_instacart`, auth/session data in Cloud SQL Postgres | Long-running `Deployment` + `Service`   | GCP Artifact Registry    | [`nao/README.md`](nao/README.md) |

## Quickstart (data stack)

With a cluster running and tools installed (see [`SETUP.md`](SETUP.md)):

```sh
# Deploy Postgres + Airflow declaratively
helmfile sync

# Watch it come up (or just open Lens / FreeLens)
kubectl -n data get pods -w
```

The Postgres chart in [`apps/postgres/`](apps/postgres/) is written from scratch
on purpose — open `templates/` and read every object it creates. Airflow uses
the official community chart, because some things you shouldn't write yourself.

## Definition of done

- [ ] Your project runs in the cluster (Pods healthy, no crash loops).
- [ ] It's reachable or observable (a Service, an Ingress, logs, or a UI).
- [ ] Your repo explains how to deploy it (a short README section is enough).
- [ ] You can demo it live and walk through it in Lens.

## Repo layout

```
.
├── README.md                  # you are here
├── SETUP.md                   # environment + cluster setup
├── helmfile.yaml              # one-command install of the data stack
├── apps/postgres/             # a Postgres Helm chart you can fully read
├── examples/
│   ├── data-pipeline/         # Airflow + your DAGs
│   ├── web-service/           # FastAPI + Deployment/Service/Ingress
│   └── nextjs-app/            # Next.js (standalone) + Deployment/Service/Ingress
├── instacart-pipeline/        # this student's project — CronJob, GHCR
├── nao/                       # this student's project — Deployment/Service, GCP Artifact Registry
└── docs/lens.md               # the visual debugging cheatsheet
```
