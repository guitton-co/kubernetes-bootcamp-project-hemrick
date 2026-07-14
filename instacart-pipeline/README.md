# instacart-pipeline

Pipeline de données Instacart (Kaggle) → BigQuery, sur Kubernetes.

Repo autonome : ce dossier contient tout le code (script Python de load + projet
dbt) et son propre `Dockerfile` — pas de dépendance à un autre repo pour build
ou déployer.

## Ce que ça fait

Un seul conteneur, exécuté à la demande via un `CronJob` :
1. `ingestion/load_to_bigquery.py` — charge les CSV bruts (GCS) vers BigQuery,
   dataset `raw_instacart`, sans transformation.
2. `dbt test --select source:raw_instacart` — tests d'intégrité sur les
   tables brutes (unicité, not_null, clés étrangères, valeurs acceptées).
   Si un test échoue, le pipeline s'arrête là (`set -euo pipefail` dans
   `run_pipeline.sh`).
3. `dbt run --select product_performance` — construit le datamart
   `gold_instacart.product_performance` (popularité/taux de réachat produit).

Voir `dbt/models/sources.yml` et `dbt/models/gold_instacart/` pour le détail.

## Prérequis

- Une clé de service account GCP avec accès au bucket source, à
  `raw_instacart` (lecture/écriture) et `gold_instacart` (écriture), ainsi que
  `roles/bigquery.jobUser` sur le projet.
- Accès push à `ghcr.io/hemrick`.
- `kubectl` configuré sur le cluster du bootcamp, namespace `hemrick`.

## 1. Build + push de l'image

Le cluster du bootcamp tourne en `amd64` — builder avec `buildx` même depuis
un Mac Apple Silicon :

```sh
docker buildx build --platform linux/amd64 \
  -t ghcr.io/hemrick/instacart-pipeline:latest \
  --push .
```

Rendre le package public sur GitHub (Packages → instacart-pipeline → Package
settings → Change visibility).

## 2. Créer le Secret avec la clé de service account

**Ne jamais committer la clé.** Créer le Secret directement depuis le fichier
local :

```sh
kubectl create secret generic instacart-gcp-credentials \
  --from-file=service-account.json=/chemin/vers/ta-cle.json \
  -n hemrick
```

## 3. Déployer le CronJob

```sh
kubectl -n hemrick apply -f k8s/cronjob.yaml
```

## 4. Tester sans attendre le schedule

```sh
kubectl -n hemrick create job --from=cronjob/instacart-pipeline instacart-pipeline-manual-1
kubectl -n hemrick get jobs,pods -w
kubectl -n hemrick logs job/instacart-pipeline-manual-1
```

## Dev local (optionnel, hors cluster)

```sh
uv sync
cp .env.example .env   # puis éditer GCP_SERVICE_ACCOUNT_LOAD_AND_DBT
uv run python ingestion/load_to_bigquery.py
uv run dbt test --project-dir dbt --profiles-dir dbt --select "source:raw_instacart"
uv run dbt run --project-dir dbt --profiles-dir dbt --select product_performance
```
