# Test local — instacart-pipeline sur le Kubernetes de Docker Desktop

Ces commandes servent à tester le `CronJob` `instacart-pipeline` **en local**,
sur le cluster Kubernetes fourni par Docker Desktop (pas le cluster distant
partagé de la cohorte). L'objectif : suivre l'exécution visuellement dans
Lens/FreeLens en pointant sur le contexte `docker-desktop`, namespace
`hemrick`, sans dépendre de `ghcr.io` (image construite et gardée en local).

```sh
# 1. Basculer sur ton cluster local (Docker Desktop)
kubectl config use-context docker-desktop

# 2. Namespace local (même nom que sur le cluster distant, par cohérence)
kubectl create namespace hemrick --dry-run=client -o yaml | kubectl apply -f -

# 3. Build l'image en local, arch native (arm64), avec un tag différent de
#    ":latest" — c'est ce qui évite que Kubernetes tente de la re-pull
#    depuis ghcr.io (imagePullPolicy par défaut = Always seulement pour ":latest")
cd instacart-pipeline
docker build -t ghcr.io/hemrick/instacart-pipeline:local-test .

# 4. Le même Secret GCP, mais dans le namespace local
kubectl -n hemrick create secret generic instacart-gcp-credentials \
  --from-file=service-account.json=/Users/emerictrossat/code/credentials/analytics-with-emeric-e0d8e4a4e0fe.json

# 5. Déployer le CronJob (nécessaire pour pouvoir en dériver un Job manuel)
kubectl -n hemrick apply -f k8s/cronjob.yaml

# 6. Job manuel, mais avec l'image locale à la place de ghcr.io:latest
kubectl -n hemrick create job --from=cronjob/instacart-pipeline instacart-pipeline-local-test \
  --dry-run=client -o yaml \
  | sed 's|ghcr.io/hemrick/instacart-pipeline:latest|ghcr.io/hemrick/instacart-pipeline:local-test|' \
  | kubectl apply -f -

# 7. Suivre le Pod
kubectl -n hemrick get pods -w

# 8. Lire les logs (mêmes 3 étapes que le run_pipeline.sh en local avec uv :
#    chargement des CSV vers BigQuery, tests dbt, build du datamart)
kubectl -n hemrick logs job/instacart-pipeline-local-test -f
```

Dans Lens/FreeLens : sélectionner le contexte `docker-desktop`, aller dans le
namespace `hemrick`, ouvrir Workloads → Jobs / Pods pour voir
`instacart-pipeline-local-test` passer par ses phases (Pending → Running →
Succeeded) et lire les logs directement dans l'UI.

## Nettoyage

```sh
kubectl -n hemrick delete job instacart-pipeline-local-test
```
