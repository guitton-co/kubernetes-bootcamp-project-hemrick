# Pre-launch End-to-End Test

Run this against a real cluster **before** publishing the GitHub Classroom.
The point is to hit every bug yourself once, instead of N students hitting it
at the same time (some while you're away June 15–23).

Prereqs: tools installed (`SETUP.md`), a cluster running (`kubectl get nodes`
shows Ready), Docker available for the app images.

## Pass 0 — Clean clone + placeholders

```sh
git clone <your-fork-url> /tmp/k8s-kata-e2e && cd /tmp/k8s-kata-e2e
grep -rn "<your-username>" .        # find every placeholder you must set
```

Replace `<your-username>` in:
- `examples/data-pipeline/airflow-values.yaml` (gitSync repo)
- `examples/web-service/k8s/deployment.yaml` (image)
- `examples/nextjs-app/k8s/deployment.yaml` (image)

Confirm the pinned Airflow chart version actually resolves:

```sh
helm repo add apache-airflow https://airflow.apache.org && helm repo update
helm search repo apache-airflow/airflow --versions | head
# adjust helmfile.yaml `version:` if 1.22.0 isn't listed
```

## Pass 1 — Data stack (highest risk)

```sh
helmfile sync
kubectl -n data get pods -w          # everything → Running / Completed
```

Checks:
- [ ] `postgres` pod Running; `pg_isready` probe passing
- [ ] `airflow-*` pods Running (api-server, scheduler, dag-processor)
- [ ] DAG `example_pipeline` shows up (gitSync pulled it from your fork)
- [ ] Trigger it → succeeds under LocalExecutor

```sh
# UI (Airflow 3 = api-server)
kubectl -n data port-forward svc/airflow-api-server 8080:8080
kubectl -n data logs deploy/airflow-api-server | grep -i password   # admin pw
```

## Pass 2 — FastAPI app

```sh
cd examples/web-service
docker build -t k8s-kata-web:latest .
kind load docker-image k8s-kata-web:latest     # or push to a registry
kubectl create namespace web
kubectl -n web apply -f k8s/
kubectl -n web port-forward svc/web 8080:80
curl localhost:8080/health                     # {"status":"ok"}
```

## Pass 3 — Next.js app

```sh
cd ../nextjs-app
docker build -t k8s-kata-nextjs:latest .
kind load docker-image k8s-kata-nextjs:latest
kubectl create namespace nextjs
kubectl -n nextjs apply -f k8s/
kubectl -n nextjs port-forward svc/nextjs 3000:80
curl localhost:3000/api/health                 # {"status":"ok"}
```

> Scale `kubectl -n nextjs scale deploy/nextjs --replicas=3` and refresh the
> page — the printed pod hostname changes. Good live demo of load-balancing.

## Teardown

```sh
helmfile destroy
kubectl delete namespace web nextjs
```

## Sign-off

- [ ] All three passes green from a clean clone
- [ ] Placeholders are the only manual edit a student must make
- [ ] Resource use is sane on a laptop-sized cluster
- [ ] Airflow chart version pinned to one that exists

Green across the board → safe to publish the Classroom.
