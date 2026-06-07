# Bienvenue — Setup d'accueil

> Written in English to match the repo. Say the word and I'll ship a French
> version for participants.

Welcome to the cohort. Do these steps **in order before the first live
session** — budget ~30 minutes. Anything that fights you goes straight into
the Slack channel; setup snags are exactly what it's for.

## Access — get these first

| What | Link | Done |
|---|---|---|
| Slack channel (Q&A + support) | _<invite link>_ | ☐ |
| GitHub Classroom assignment (your fork) | _<classroom link>_ | ☐ |
| Payment (€149, Qonto) | _<payment link>_ | ☐ |
| Live session slots (2 × 30 min, Google Meet) | _<calendar link>_ | ☐ |

_(Fill the links in before sending.)_

## Then set up your environment

1. **Accept the GitHub Classroom assignment** → you get your own private fork
   of `k8s-kata`.
2. **Install the tools** — follow [`SETUP.md`](SETUP.md) §1 (uv, kubectl, helm,
   helmfile).
3. **Get a cluster** — [`SETUP.md`](SETUP.md) §2 (local Docker Desktop / kind /
   k3d is simplest).
4. **Connect a visual IDE** — [`SETUP.md`](SETUP.md) §3 (FreeLens recommended).
5. **Replace `<your-username>`** in the three files flagged in the repo README
   (your fork's gitSync repo and the two app images).

## You're ready when

```sh
kubectl get nodes        # a Ready node
helmfile sync            # Postgres + Airflow come up in the 'data' namespace
kubectl -n data get pods # pods moving to Running
```

…and you can see those Pods in FreeLens/Lens.

## Before the first session, think about your project

It's a free project — pick something **you** want to run on Kubernetes (a dlt
pipeline, a SQLMesh project, a Marimo app, a service…). Open a PR with the
proposal template and Louis will confirm scope. Two or three lines is enough.
