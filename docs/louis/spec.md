# Louis's feedback — Instacart / dbt / nao project

**Date:** 2026-07-14
**Scope:** review of your spec (from `2026-07-13-spec.md`) + first pass on
the `instacart-pipeline/` code you pushed.

Merging this PR is optional — it's a feedback artifact, not code you need.
Do skim the "Answers to your Slack questions" section though; those unblock
your Step 3 (remote cluster deploy).

## Answers to your Slack questions

1. **"Comment le tester sur le k8 en ligne ?"** — Your README section 3
   already answers this correctly. Follow it verbatim on the shared cluster.
2. **"Il faut publier l'image quelque part ?"** — Yes.
   - **ghcr.io** — free, one-click GitHub package, private by default. Perfect
     for this. What you're already doing. ✅
   - **Docker Hub** — also fine; free public tier + 1 free private repo. Use
     if your team is Docker-Hub-native.
3. **"Credential d'accès à ghcr.io ?"** — Two paths:
   - **Keep the package private + `imagePullSecrets`** — your current setup
     (README §3.3). Works. Right pattern for a real project where the image
     might contain secrets in layers.
   - **Make the package public** — go to
     https://github.com/hemrick?tab=packages → click
     `instacart-pipeline` → Package settings → "Change visibility" →
     Public. Then you can drop the `imagePullSecrets` block from the
     CronJob AND drop the `docker-registry` Secret creation step from the
     README. For this bootcamp demo (no real secrets in the image), that's
     simpler — one moving part less. I'd go public.

## Feedback on your project spec

### "Using BigQuery as a database"

That's your choice — because you already have GCP creds and BQ familiarity.
Good.

**Two alternative paths available on the cohort cluster** if BQ becomes
tedious:
- **Shared Postgres in the `data` namespace** — I already run it for
  Airflow, cross-ns Service DNS =
  `postgres-service.data.svc.cluster.local:5432`. Create your own DB in it
  (`kubectl -n data exec deploy/postgres -- psql -U airflow -d airflow -c 'CREATE DATABASE instacart;'`)
  and point dbt at it via `type: postgres`.
- **DuckDB** — file-based, mount a PVC in your `hemrick` namespace, dbt
  writes to `warehouse.duckdb`. Zero external deps. Reference config in
  `docs/louis/2026-07-04-s2-prep/03-sqlmesh/` (that's on Louis's private
  branch in the template repo — I can share the file if you want).

Either would work with what you already have; BQ is fine.

### "Run on CloudRun would be enough (simpler and cheapest?)"

**Yes, CloudRun IS the right answer for prod if you optimize for cost +
simplicity.** The bootcamp is deliberately about the layer *below* that. Two
choices on the K8s side:

1. **CronJob** (what you did) — good. Direct translation of "scheduled
   container." No orchestration surface — if you add a second job or need
   dependencies, you outgrow it.
2. **Airflow via `KubernetesPodOperator`** — I run an Airflow instance in
   the `data` namespace. You'd write a DAG file, submit a PR to the
   template repo's `examples/data-pipeline/dags/` folder, gitSync picks it
   up in ~60s. The DAG uses `KubernetesPodOperator` to spawn your existing
   image as a Pod on demand. Same image, but with retries + backfill + UI +
   dependencies.

For your Instacart pipeline (single linear DAG: load → test → build), the
CronJob you have is fine. Upgrade to Airflow ONLY when you have a real
reason (multiple jobs, non-trivial dependencies, or you want the Airflow UI
for ops visibility).

### "Deploying nao"

Already done, end-to-end, during Session 2 prep. Full notes here (in the
template repo on the main branch, not gitignored):
`docs/louis/2026-07-04-s2-prep/04-nao/` — actually that's gitignored, but I
can share the file directly on Slack when you're ready. TL;DR of what
worked:

- Single container `getnao/nao:latest`, 1 Deployment + Service + Secret.
- Auth: first-user-signup admin, no OAuth required.
- Azure OpenAI **via Nao's OpenAI provider (not Azure provider)** with a
  custom base URL — Azure Foundry endpoints don't match the classic
  `openai.azure.com/deployments/...` shape.
- Warehouse: point Nao's `nao_config.yaml` at your BigQuery project with
  `type: bigquery`. Nao ships a first-class BQ connector.

For your project the wiring would be:
- Your `instacart-pipeline` CronJob writes `gold_instacart.product_performance`
  to BQ (done).
- Deploy Nao in the same namespace, config context to declare
  `type: bigquery` pointing at your `gold_instacart` dataset.
- Users chat with Nao → it writes SQL against `product_performance` → returns
  insights.

Ping me on Slack when ready to add Nao; I'll paste the manifests.

## Code review

See `docs/louis/code_review.md` for the line-by-line review of your
`instacart-pipeline/` commits. Same content is also posted as inline PR
comments on the review PR (base = template starter, head = `main`) so you
can respond in context.

## Next step suggestion

Once the CronJob has one green real run:

1. Deploy Nao in your `hemrick` namespace (30 min work — I'll share
   manifests + config).
2. Point Nao's `nao_config.yaml` `databases:` at your BQ `gold_instacart`
   dataset.
3. Chat with your pipeline output in natural language — that's your S2
   demo.

Ping on Slack when you're at that stage.
