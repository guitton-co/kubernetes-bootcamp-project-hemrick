# nao

Agent conversationnel d'analyse de données ([getnao.io](https://getnao.io)),
déployé sur le cluster Kubernetes de la cohorte (namespace `hemrick`).

Ce dossier ne contient **pas** de code applicatif : l'image vendor
`getnao/nao:latest` embarque le runtime, `nao/` ne fournit que le contexte du
projet (config, prompts, docs de tables) copié dedans par le `Dockerfile`.

## Ce que ça fait

Un `Deployment` de 2 conteneurs par pod (contrairement au `CronJob` de
`../instacart-pipeline`, `nao` est un service HTTP long-running) :

1. **`nao-chat`** — le chat lui-même, port `5005`. Interroge BigQuery
   (`analytics-with-emeric.gold_instacart`, même projet et même clé de
   service account que `instacart-pipeline`) et stocke ses données
   d'auth/session (`better-auth`) dans Postgres.
2. **`cloud-sql-proxy`** — sidecar qui expose l'instance Cloud SQL
   (`analytics-with-emeric:us-central1:nao-db`) sur `localhost:5432` dans le
   pod ; `nao-chat` s'y connecte via `DB_URI`.

Existe aussi en déploiement Cloud Run (`service.yaml`, `db_start.sh`,
`db_stop.sh`) — ce README couvre uniquement le chemin Kubernetes.

## Cohérence avec `instacart-pipeline` — et différences

Même approche de déploiement que `../instacart-pipeline` sur tout ce qui est
partageable : image poussée sur **GCP Artifact Registry** (pas GHCR), même
service account (`bigquery-load-dbt@analytics-with-emeric.iam.gserviceaccount.com`),
même Secret de pull (`gar-pull-secret`, même registre → un seul Secret pour
les deux projets), même modèle IAM (`roles/artifactregistry.reader` par
repo). Voir `../instacart-pipeline/README.md` pour le détail de ce socle
commun.

Ce qui diffère, et pourquoi :

| | `instacart-pipeline` | `nao` | Pourquoi |
| - | - | - | - |
| Type d'objet K8s | `CronJob` | `Deployment` + `Service` (+ `Ingress` optionnel) | `nao` sert du HTTP en continu (chat), `instacart-pipeline` s'exécute puis s'arrête — pas la même sémantique K8s. |
| Conteneurs par pod | 1 | 2 (`nao-chat` + sidecar `cloud-sql-proxy`) | `nao` a besoin d'une connexion live à Postgres (auth/session `better-auth`) ; le pipeline n'a aucune dépendance à une base à l'exécution. |
| Secrets K8s | `instacart-gcp-credentials` (clé GCP) uniquement | `instacart-gcp-credentials` (réutilisée) **+** `nao-secrets` (`OPENAI_API_KEY`, `BETTER_AUTH_SECRET`, `DB_URI`) | `nao` a des identifiants propres à l'app (LLM, auth) que le pipeline n'a pas. |
| Build de l'image | un seul `Dockerfile`, une seule config | `--build-arg NAO_CONFIG_FILE=nao_config.k8s.yaml` (voir §1) | `nao` existe aussi sur Cloud Run avec une config différente (ADC, pas de fichier de clé monté) — il faut donc deux variantes d'image pour ne pas casser Cloud Run en construisant pour K8s. `instacart-pipeline` n'a pas cette contrainte : sa version Cloud Run montait déjà la clé de la même façon que sur K8s. |
| Dépendance externe à démarrer manuellement | Aucune | Instance Cloud SQL `nao-db` (`./db_start.sh` / `./db_stop.sh`) | Coût : la même logique de start/stop que sur Cloud Run est conservée pour éviter de payer le compute Cloud SQL en continu. |
| Exposition | Aucune (le résultat va dans BigQuery) | `Service` (ClusterIP) + `port-forward`, `Ingress` optionnel | Un `CronJob` n'a rien à exposer ; `nao` doit être atteignable par un navigateur. |

## Prérequis

- Une clé de service account GCP avec accès à `gold_instacart` (lecture) et
  au projet (`roles/bigquery.jobUser`), plus `roles/cloudsql.client` pour le
  proxy — même clé que `instacart-pipeline`.
- Ce même SA a besoin de `roles/artifactregistry.reader` sur le repo AR
  `nao` — **confirmé nécessaire** : la policy IAM du repo était vide par
  défaut (aucun accès en lecture hérité du flow Cloud Run), voir §2.
- `kubectl`, `docker`, `gcloud` installés en local ; accès push à
  `us-central1-docker.pkg.dev/analytics-with-emeric/nao` (`gcloud auth
  login` puis `gcloud auth configure-docker us-central1-docker.pkg.dev`, une
  fois — déjà fait si tu as suivi `instacart-pipeline/README.md` §3.2).
- L'instance Cloud SQL `nao-db` doit tourner (`./db_start.sh`) avant de
  déployer ou de scaler le Deployment — le sidecar `cloud-sql-proxy` ne
  peut pas se connecter sinon.

## 1. Build + push de l'image (amd64)

Config différente de la variante Cloud Run : pas d'ADC sur le cluster DO,
donc `nao_config.k8s.yaml` (avec `credentials_path`) remplace
`nao_config.prod.yaml` au build, via l'`ARG` du `Dockerfile`. Tag distinct
(`k8s-latest`) pour ne pas écraser le tag `latest` utilisé par Cloud Run.

```sh
gcloud auth login                                          # une fois, et à refaire si le token expire (voir Dépannage)
gcloud auth configure-docker us-central1-docker.pkg.dev     # une fois

docker buildx build --platform linux/amd64 \
  --build-arg NAO_CONFIG_FILE=nao_config.k8s.yaml \
  -t us-central1-docker.pkg.dev/analytics-with-emeric/nao/nao-chat:k8s-latest \
  --push .
```

## 2. Donner au cluster l'accès à Artifact Registry

**Étape ponctuelle (one-time setup)** : le SA utilisé pour pull doit avoir
`roles/artifactregistry.reader` sur le repo `nao`, sinon le pull échoue en
`ImagePullBackOff` / `403 Forbidden` même avec le Secret ci-dessous :

```sh
gcloud artifacts repositories add-iam-policy-binding nao \
  --location=us-central1 --project=analytics-with-emeric \
  --member="serviceAccount:bigquery-load-dbt@analytics-with-emeric.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

Le Node distant n'a aucune identité GCP par défaut — il lui faut aussi un
Secret Kubernetes dédié pour s'authentifier (si `gar-pull-secret` existe déjà
dans `hemrick`, créé pour `instacart-pipeline`, pas besoin de le recréer —
même registre) :

```sh
kubectl create secret docker-registry gar-pull-secret \
  --docker-server=us-central1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat /chemin/vers/ta-cle.json)" \
  --docker-email=ton-email@example.com \
  -n hemrick
```

`k8s/deployment.yaml` référence déjà ce Secret via `imagePullSecrets`.

## 3. Réutiliser le Secret GCP existant

`nao` réutilise la même clé de service account que `instacart-pipeline`
(déjà montée dans `hemrick` sous `instacart-gcp-credentials` — voir
`../instacart-pipeline/README.md` §3.4). Rien à recréer si ce Secret existe
déjà dans le namespace.

## 4. Créer les secrets propres à nao

```sh
kubectl create secret generic nao-secrets \
  --from-literal=OPENAI_API_KEY=<valeur> \
  --from-literal=BETTER_AUTH_SECRET=<valeur> \
  --from-literal=DB_URI='postgresql://<user>:<pass>@localhost:5432/<db>' \
  -n hemrick
```

`DB_URI` pointe vers `localhost:5432` : `nao-chat` parle au sidecar
`cloud-sql-proxy` dans le même pod, jamais directement à Cloud SQL.

## 5. Démarrer Cloud SQL et déployer

```sh
./db_start.sh   # attend RUNNABLE avant de continuer

kubectl -n hemrick apply -f k8s/
kubectl -n hemrick get pods -w
kubectl -n hemrick logs deploy/nao -c nao-chat
kubectl -n hemrick logs deploy/nao -c cloud-sql-proxy
```

## 6. Y accéder

```sh
kubectl -n hemrick port-forward svc/nao 8080:80
# http://localhost:8080
```

`BETTER_AUTH_URL` dans `k8s/deployment.yaml` doit correspondre à l'URL
réellement utilisée pour accéder à nao (better-auth lie ses cookies/redirects
à cette URL) — `http://localhost:8080` correspond au port-forward ci-dessus ;
si un Ingress avec un hostname stable est mis en place à la place
(`k8s/ingress.yaml`, optionnel), mets à jour cette valeur et redéploie.

## 7. Nettoyage

```sh
./db_stop.sh   # coupe la facturation compute Cloud SQL
```

Le Deployment/Service peuvent rester en place (pas de coût compute
significatif au repos sur le cluster partagé) — seul `nao-db` coûte tant
qu'il tourne.

### Dépannage

- **`docker buildx build --push` échoue avec `error getting credentials`** :
  le token gcloud a expiré / besoin d'un reauth. Relance `gcloud auth login`
  (flow navigateur), puis relance le build.
- **`ImagePullBackOff` avec `403 Forbidden` / `failed to fetch oauth token`**
  (`kubectl describe pod ...`) : le Secret `gar-pull-secret` existe mais le SA
  n'a pas `roles/artifactregistry.reader` sur le repo — relancer la commande
  `gcloud artifacts repositories add-iam-policy-binding` ci-dessus (one-time
  setup, à refaire seulement si le SA change).
- **`cloud-sql-proxy` en `CrashLoopBackOff` / erreurs de connexion** :
  vérifier que `nao-db` est bien `RUNNABLE` (`./db_start.sh`) et que le SA a
  `roles/cloudsql.client`.
- **`nao-chat` ne répond pas aux requêtes BigQuery** : vérifier que l'image a
  bien été buildée avec `--build-arg NAO_CONFIG_FILE=nao_config.k8s.yaml`
  (sinon `nao_config.prod.yaml` est utilisé par défaut, sans
  `credentials_path`, et l'auth BigQuery échoue faute d'ADC).
