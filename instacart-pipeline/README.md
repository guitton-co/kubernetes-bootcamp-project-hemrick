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

Ce README couvre 3 façons de faire tourner le pipeline, du plus rapide au plus
réaliste :

| # | Où | Pourquoi |
| - | -- | -------- |
| 1 | En local avec `uv`, sans Kubernetes | Valider la logique métier (chargement + tests dbt + datamart) le plus vite possible. |
| 2 | Sur un Kubernetes local (Docker Desktop) | Valider l'image Docker et le `CronJob` tels quels, sans dépendre d'un registre externe. |
| 3 | Sur le cluster distant de la cohorte (namespace `hemrick`) | Déploiement réel, planifié (`schedule` du `CronJob`). |

## Prérequis

- Une clé de service account GCP avec accès au bucket source, à
  `raw_instacart` (lecture/écriture) et `gold_instacart` (écriture), ainsi que
  `roles/bigquery.jobUser` sur le projet.
- Accès push à `us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline`
  (repo Artifact Registry, déjà créé pour l'ancien déploiement Cloud Run) —
  utile dès la section 2. `gcloud auth configure-docker
  us-central1-docker.pkg.dev` en local si ce n'est pas déjà fait.
- `kubectl`, `docker`, `uv` installés en local.
- Le SA GCP utilisé doit avoir `roles/artifactregistry.reader` sur ce repo —
  voir section 3 pour comment le cluster distant y accède.

## 1. Tester en local (sans cluster)

```sh
uv sync

# Créer .env (jamais commité) et pointer vers ta clé GCP
cp .env.example .env
# éditer .env : GCP_SERVICE_ACCOUNT_LOAD_AND_DBT=/chemin/vers/ta-cle.json
# (chemin absolu recommandé si la clé vit hors du repo — configuration.py
# résout un chemin relatif par rapport à instacart-pipeline/, pas à ton cwd)

# dbt_utils est requis par les tests de sources.yml (unique_combination_of_columns) :
uv run dbt deps --project-dir dbt

uv run python ingestion/load_to_bigquery.py
```

`dbt`, contrairement au script Python, ne lit pas `.env` (le chargement via
`python-dotenv` n'a lieu que dans `ingestion/configuration.py`). Exporte la
variable avant les commandes `dbt` :

```sh
export GCP_SERVICE_ACCOUNT_LOAD_AND_DBT=/chemin/vers/ta-cle.json

uv run dbt test --project-dir dbt --profiles-dir dbt --select "source:raw_instacart"
uv run dbt run --project-dir dbt --profiles-dir dbt --select product_performance
```

Si tout passe, la logique métier est validée — vérifie dans BigQuery que
`gold_instacart.product_performance` existe et contient des lignes (triées
par `times_ordered` décroissant, les produits populaires comme les bananes
doivent être en tête).

## 2. Tester sur un Kubernetes local (Docker Desktop)

But : valider que l'image Docker et le `CronJob` fonctionnent tels quels,
sans toucher au registre distant — Docker Desktop partage le même moteur
Docker que ton terminal, donc une image buildée en local est directement
utilisable par son Kubernetes, sans push.

```sh
# Basculer sur le cluster local
kubectl config use-context docker-desktop

# Namespace local (même nom que sur le cluster distant, par cohérence)
kubectl create namespace hemrick --dry-run=client -o yaml | kubectl apply -f -

# Build natif (pas de --platform, pas de --push), tag différent de ":latest"
# pour que Kubernetes utilise imagePullPolicy: IfNotPresent (comportement
# par défaut) et ne tente jamais de contacter un registre
docker build -t us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:local-test .

# Secret GCP dans ce namespace local
kubectl create secret generic instacart-gcp-credentials \
  --from-file=service-account.json=/chemin/vers/ta-cle.json -n hemrick

kubectl -n hemrick apply -f k8s/cronjob.yaml

# Job manuel utilisant l'image locale à la place du tag :latest
kubectl -n hemrick create job --from=cronjob/instacart-pipeline instacart-pipeline-local-test \
  --dry-run=client -o yaml \
  | sed 's|us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:latest|us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:local-test|' \
  | kubectl apply -f -

kubectl -n hemrick get pods -w
kubectl -n hemrick logs job/instacart-pipeline-local-test -f
```

Observable dans Lens/FreeLens en sélectionnant le contexte `docker-desktop`,
namespace `hemrick`, Workloads → Jobs/Pods.

> Le `CronJob` référence `imagePullSecrets: [gar-pull-secret]` (voir
> section 3) qui n'existe pas forcément dans ce namespace local — sans
> importance ici : ce champ n'est consulté que si un pull réseau est
> réellement tenté, or l'image est déjà en cache local (`IfNotPresent`).

Nettoyage (pas de suppression automatique — voir note en section 3) :

```sh
kubectl -n hemrick delete job instacart-pipeline-local-test
```

## 3. Déployer sur le cluster distant (cohorte, namespace `hemrick`)

### 3.1 Se connecter au bon cluster

```sh
export KUBECONFIG=/Users/emerictrossat/code/credentials/k8s-bootcamp-guittonco-2026-06-kubeconfig.yaml
kubectl config current-context   # doit pointer vers le cluster de la cohorte
kubectl get ns | grep hemrick    # ton namespace existe déjà
```

### 3.2 Build + push de l'image (amd64)

Le cluster tourne en `amd64` — builder avec `buildx` même depuis un Mac
Apple Silicon. Même repo Artifact Registry que l'ancien déploiement Cloud
Run :

```sh
gcloud auth login                                          # une fois, et à refaire si le token expire (voir Dépannage)
gcloud auth configure-docker us-central1-docker.pkg.dev     # une fois

docker buildx build --platform linux/amd64 \
  -t us-central1-docker.pkg.dev/analytics-with-emeric/instacart-pipeline/ingestion:latest \
  --push .
```

### 3.3 Donner au cluster l'accès à l'image (Artifact Registry)

**Étape ponctuelle (one-time setup)**, à faire une seule fois par projet
GCP/service account — pas à chaque déploiement : le SA utilisé pour pull doit
avoir `roles/artifactregistry.reader` sur le repo, sinon le pull échoue en
`ImagePullBackOff` avec un `403 Forbidden` (même si le Secret ci-dessous est
correct) :

```sh
gcloud artifacts repositories add-iam-policy-binding instacart-pipeline \
  --location=us-central1 --project=analytics-with-emeric \
  --member="serviceAccount:bigquery-load-dbt@analytics-with-emeric.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

Le Node distant n'a aucune identité GCP par défaut — il lui faut aussi un
Secret Kubernetes dédié pour s'authentifier auprès d'Artifact Registry :

```sh
kubectl create secret docker-registry gar-pull-secret \
  --docker-server=us-central1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat /chemin/vers/ta-cle.json)" \
  --docker-email=ton-email@example.com \
  -n hemrick
```

Si ce Secret existe déjà dans `hemrick` (créé pour `nao/`, même registre),
pas besoin de le recréer — `k8s/cronjob.yaml` référence le même
`gar-pull-secret` via `imagePullSecrets`.

### 3.4 Créer le Secret avec la clé de service account GCP

**Ne jamais committer la clé.** Créer le Secret directement depuis le fichier
local :

```sh
kubectl create secret generic instacart-gcp-credentials \
  --from-file=service-account.json=/Users/emerictrossat/code/credentials/analytics-with-emeric-e0d8e4a4e0fe.json \
  -n hemrick
```

### 3.5 Déployer le CronJob

Cette commande ne lance rien immédiatement — elle enregistre l'objet
`CronJob` sur le cluster. À partir de là, Kubernetes déclenche
**automatiquement** un `Job` tous les jours à 6h UTC (`schedule` défini dans
`k8s/cronjob.yaml`), sans action de ta part :

```sh
kubectl -n hemrick apply -f k8s/cronjob.yaml
```

### 3.6 Tester sans attendre le schedule

```sh
kubectl -n hemrick create job --from=cronjob/instacart-pipeline instacart-pipeline-manual-1
```

Suivre le pod séparément — `kubectl get jobs,pods -w` (deux types de
ressource + `--watch`) échoue sur certaines versions de kubectl avec
`you may only specify a single resource type` :

```sh
kubectl -n hemrick get pods -l job-name=instacart-pipeline-manual-1 -w
```

Puis, une fois le pod `Running` (Ctrl+C pour sortir du `-w` ci-dessus) :

```sh
kubectl -n hemrick logs job/instacart-pipeline-manual-1 -f
```

Si le job existe déjà (deuxième tentative) : `kubectl -n hemrick delete job
instacart-pipeline-manual-1` avant de relancer `create job`.

### 3.7 Nettoyage

Le `CronJob` n'a volontairement pas de `ttlSecondsAfterFinished` (projet de
test, on préfère garder les Jobs visibles dans Lens plutôt que de les voir
disparaître automatiquement après 10 min). Donc chaque Job — manuel ou
issu du schedule — doit être supprimé à la main une fois consulté :

```sh
kubectl -n hemrick delete job instacart-pipeline-manual-1
```

### Dépannage

- **`docker buildx build --push` échoue avec `error getting credentials`** :
  le token gcloud a expiré / besoin d'un reauth. `docker-credential-gcloud`
  échoue silencieusement en mode non-interactif — relance `gcloud auth login`
  (flow navigateur), puis relance le build.
- **`ImagePullBackOff` avec `403 Forbidden` / `failed to fetch oauth token`**
  (`kubectl describe pod ...`) : le Secret `gar-pull-secret` existe mais le SA
  n'a pas `roles/artifactregistry.reader` sur le repo — relancer la commande
  `gcloud artifacts repositories add-iam-policy-binding` de la §3.3 (one-time
  setup, à refaire seulement si le SA change).
- **Le Job échoue en cours de script** : `run_pipeline.sh` utilise
  `set -euo pipefail`, donc les logs (`kubectl -n hemrick logs job/...`)
  s'arrêtent net à l'étape qui a cassé (chargement CSV, tests dbt, ou build
  du datamart).
- **Pod bloqué en `Pending`** : `kubectl -n hemrick describe pod <pod>`
  pour voir l'erreur (montage de Secret manquant, ressources insuffisantes,
  etc.).
