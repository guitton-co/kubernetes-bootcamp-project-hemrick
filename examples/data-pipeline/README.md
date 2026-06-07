# Example: Data pipeline (Airflow on Kubernetes)

Runs the official Airflow chart against the Postgres you deploy from
`apps/postgres`, with DAGs synced straight from your fork.

## Deploy

```sh
# from the repo root
helmfile sync
kubectl -n data get pods -w
```

## See the Airflow UI

In Airflow 3 the webserver is the **API server**, so the service is
`airflow-api-server`:

```sh
kubectl -n data port-forward svc/airflow-api-server 8080:8080
# open http://localhost:8080
```

…or right-click the service in Lens/FreeLens → *port-forward*.

> Airflow 3 no longer ships a fixed `admin/admin` login. The simple auth
> manager prints a generated password on first start — grab it from the
> api-server pod logs:
> `kubectl -n data logs deploy/airflow-api-server | grep -i password`

## Make it yours

1. Edit `airflow-values.yaml`: set `dags.gitSync.repo` to **your** fork.
2. Drop your DAGs in `dags/` (replace `example_pipeline.py`).
3. `helmfile sync` again — gitSync pulls your changes, no image rebuild.

Swap the toy DAG for a dlt source, a SQLMesh run, a DuckDB transform — whatever
you pitched.
