# Bienvenue — Setup d'accueil

> Written in English to match the repo. Say the word and I'll ship a French
> version for participants.

Welcome to the cohort. Do these steps **in order before the first live
session** — budget ~30 minutes. Anything that fights you goes straight into
the Slack channel; setup snags are exactly what it's for.

## Access — get these first

| What                                               | Link                                                       | Done |
| -------------------------------------------------- | ---------------------------------------------------------- | ---- |
| Slack channel (Q&A + support)                      | https://guittonco-bootcamps.slack.com/archives/C0BCZE98QBU | ☐    |
| GitHub Classroom assignment (your fork)            | https://classroom.github.com/a/0VXJ7CKH                    | ☐    |
| Payment (€149, Qonto)                              | _<payment link>_                                           | ☐    |
| Live session slots (2 × 30 min, Google Meet)       | _<calendar link>_                                          | ☐    |
| Shared cluster kubeconfig (attached to this email) | `k8s-bootcamp-guittonco-2026-06-kubeconfig.yaml`           | ☐    |
| Session recordings (Google Drive)                  | _<drive folder URL>_                                       | —    |

_(Fill the links in before sending.)_

## Then set up your environment

1. **Accept the GitHub Classroom assignment** → you get your own fork of
   `kubernetes-bootcamp`. **Set it to public** (your fork must be public or
   Airflow's gitSync will refuse to pull your DAGs).
2. **Install the tools** — follow [`SETUP.md`](SETUP.md) §1 (uv, kubectl, helm,
   helmfile, Docker).
3. **Connect to the shared cohort cluster** — you do _not_ need a local
   Kubernetes. Louis is sharing a managed cluster on Digital Ocean:
   ```sh
   # Save the attached kubeconfig somewhere safe, then:
   export KUBECONFIG=/path/to/k8s-bootcamp-guittonco-2026-06-kubeconfig.yaml
   kubectl get nodes        # should show 3 Ready nodes
   ```
   **Namespace rule (important):** the cluster is shared with the rest of the
   cohort. You have **one pre-created namespace** = your GitHub handle
   (lowercased). All your workloads go there. Don't create other namespaces
   and don't touch anyone else's — see Session 1.
4. **Connect a visual IDE** — [`SETUP.md`](SETUP.md) §3 (FreeLens recommended).
   Point it at the same kubeconfig.
5. **You do NOT run `helmfile sync` locally.** Airflow + Postgres are
   already deployed on the shared cluster in the `data` namespace. Verify
   with `kubectl -n data get pods` — you should see them Running. You
   consume the shared instance; you do not redeploy it.

## You're ready when

```sh
kubectl get nodes                          # 4 nodes Ready on the shared cluster
kubectl get ns | grep <your-github-handle> # your namespace (lowercased handle)
kubectl -n data get pods                   # airflow-* + postgres pods Running
```

…and you can see the cluster in FreeLens/Lens.

## Before the first session, think about your project

It's a free project — pick something **you** want to run on Kubernetes (a dlt
pipeline, a SQLMesh project, a Marimo app, a service, a bot…). See
[`docs/project-ideas.md`](docs/project-ideas.md) for 5 seed projects if nothing
springs to mind. Open a PR with the proposal template and Louis will confirm
scope. Two or three lines is enough. **Due Mon 6 Jul.**

## How support works (async)

- **Slack `#help` is the only channel.** No synchronous office hours.
- **SLA: 24h, M–F.** Often same-day, not promised.
- Louis can `gh classroom clone` your project and inspect your namespace on
  the shared cluster directly — most triage doesn't need a call.
- Use `@here` only when you're truly blocked. Otherwise just post in the
  channel — others will hit the same things and benefit from the thread.
- Sessions are recorded (Google Drive folder linked above). Catch up async if
  you miss one.
