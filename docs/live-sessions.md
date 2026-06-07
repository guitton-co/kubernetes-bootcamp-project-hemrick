# Live Sessions — 2 × 30 min (Google Meet)

Your running order, time-boxed into two sessions and wired to the repo so every
concept has a live demo. You know the material — this is scaffolding, not a
script. Demo in Lens/FreeLens (see [`lens.md`](lens.md)); change things in Git.

Teaching order:
**Nodes → Workloads (Deployments → Pods → CronJobs) → Config (ConfigMaps →
Secrets) → Network (Service → Ingress) → Helm → Custom Resources (Strimzi).**

---

## Session 1 — The object model: run & inspect (30 min)

Goal: by the end they can read a cluster and explain what's running and why.

| Min | Topic | Live demo (repo) | Visual angle in Lens |
|---|---|---|---|
| 0–3 | **Nodes** | `kubectl get nodes`; open Nodes view | capacity, allocatable, what schedules where |
| 3–8 | **Workloads: Deployment** | `helmfile sync` (or just `helm install postgres ./apps/postgres`) | Deployment → ReplicaSet → Pod chain; `scale` and watch |
| 8–13 | **Pods** | open the postgres / nextjs pod | logs, exec/shell, Events tab = the "why" |
| 13–18 | **CronJobs** | quick inline demo (below) | scheduled Job → Pod → Completed |
| 18–24 | **Config: ConfigMap → Secret** | `postgres-credentials` Secret + `envFrom` in the Deployment | how config reaches a container; why Secrets ≠ encryption |
| 24–30 | **Recap + Q&A** | — | "you can now read any cluster" |

CronJob one-liner (no repo file needed):
```sh
kubectl create cronjob hello --image=busybox --schedule="*/1 * * * *" -- echo hi
kubectl get cronjob,jobs,pods
```

Anchor: the `apps/postgres` chart is readable end-to-end — use it to show that a
Deployment, a Secret, a PVC and a Service are just YAML you can open.

---

## Session 2 — Expose, package, extend (30 min)

Goal: by the end they can ship something reachable and know how real stacks are
packaged and extended.

| Min | Topic | Live demo (repo) | Visual angle in Lens |
|---|---|---|---|
| 0–5 | **Network: Service** | `postgres-service` (ClusterIP) + the `web`/`nextjs` Service | Service → Endpoints → Pods; zero-endpoints = label drift |
| 5–10 | **Ingress** | `examples/nextjs-app/k8s/ingress.yaml` (or port-forward fallback) | path/host routing into the cluster |
| 10–18 | **Helm** | contrast: hand-written `apps/postgres` chart **vs** community `apache-airflow/airflow`; then `helmfile sync` the whole stack | values → rendered objects; one command, whole stack |
| 18–27 | **Custom Resources / Operators** | Strimzi Kafka operator (commands below) | a CRD (`Kafka`) the operator reconciles into Pods/Services |
| 27–30 | **Wrap → the lab** | point at the free project + PR template | "now go run your own thing" |

Strimzi demo (the operator pattern, data-eng-relevant):
```sh
kubectl create namespace kafka
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
kubectl apply -f https://strimzi.io/examples/latest/kafka/kafka-single-node.yaml -n kafka
kubectl -n kafka get kafka,pods   # watch the operator build the cluster
```

Anchor: Helm packages *known* apps; operators teach Kubernetes about *new* kinds
of app via CRDs. Strimzi is the clean example — they apply a `Kafka` resource and
the operator does the rest.

---

## Notes for you

- CronJob and Strimzi aren't in the repo (they're inline demos above). Say the
  word if you'd rather ship a `examples/cronjob/` manifest and a Strimzi pointer
  as committed artifacts.
- Session 1 is dense at 30 min; ConfigMap can compress to a mention if Pods/Events
  run long — Events is the higher-value stop.
