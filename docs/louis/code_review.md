# Code review — `instacart-pipeline/` (Louis)

**Date:** 2026-07-14
**Reviewer:** Louis (bootcamp instructor)
**Scope:** commits `a77c32e` (job bq load and dbt) + `0adf2eb` (update readme)
— everything under `instacart-pipeline/`. Template files are out of scope.
**Reader:** Emeric — data engineer with strong GCP+BQ background but zero
prior K8s experience.

The comments below are also being posted inline on the PR (base = template
starter, head = `main`) so you can respond in context. This file is the
consolidated record.

---

# Change summary: Adds a self-contained `instacart-pipeline/` project (Python loader + dbt + Dockerfile + CronJob + README) that ingests Kaggle CSVs from GCS to BigQuery, tests raw sources with dbt, and builds a `gold_instacart.product_performance` datamart on a schedule.

Overall shape is solid for a first K8s deploy. The three-tier README (local
→ docker-desktop → remote) is exactly the right progression, secret
handling avoids committing the SA file, and you already caught the amd64/M1
buildx trap. Findings below prioritise correctness + K8s idioms + a couple
of Python defensiveness nits — nothing blocking your Step 3 remote-cluster
deploy.

## File: instacart-pipeline/ingestion/configuration.py

### L18: [HIGH] `KeyError` on import + subtle pathlib behavior + stale-at-class-definition-time default

Three problems stacked on one line:

1. `os.environ["GCP_SERVICE_ACCOUNT_LOAD_AND_DBT"]` raises `KeyError` at
   **import time**, not at usage. Anything that transitively imports
   `configuration` (tests, tooling) crashes before it can print a useful
   message.
2. Dataclass field defaults are evaluated **once at class-definition
   time**. If the env var changes at runtime (test setup, subprocess),
   `CONFIG.credentials_path` won't reflect it.
3. `REPO_ROOT / os.environ[...]` — pathlib silently discards `REPO_ROOT`
   when the right-hand side is absolute (`Path("/repo") / "/secrets/x"`
   returns `Path("/secrets/x")`). Works for the K8s CronJob case (absolute
   path in the mounted Secret) AND for a relative `.env` value, but only
   because pathlib does the right thing by accident. Non-obvious to a
   future reader.

Suggested change:

```
 REPO_ROOT = Path(__file__).parent.parent
 load_dotenv(REPO_ROOT / ".env")


+def _resolve_credentials_path() -> Path:
+    raw = os.environ.get("GCP_SERVICE_ACCOUNT_LOAD_AND_DBT")
+    if not raw:
+        raise RuntimeError(
+            "GCP_SERVICE_ACCOUNT_LOAD_AND_DBT is not set. "
+            "Set it in .env (local) or via the Secret volume mount (K8s)."
+        )
+    path = Path(raw)
+    return path if path.is_absolute() else REPO_ROOT / path
+
+
 @dataclass(frozen=True)
 class IngestionConfig:
     project: str = "analytics-with-emeric"
     location: str = "US"
     tables_dir: Path = Path(__file__).parent / "tables"
-    credentials_path: Path = REPO_ROOT / os.environ["GCP_SERVICE_ACCOUNT_LOAD_AND_DBT"]
+    credentials_path: Path = field(default_factory=_resolve_credentials_path)


 CONFIG = IngestionConfig()
```

Requires `from dataclasses import dataclass, field`. Now the error message
is actionable, resolution is explicit, and lazy `default_factory` means the
env is read when `CONFIG` is instantiated (not at class-def time).

### L15: [LOW] Hardcoded GCP project name

`project: str = "analytics-with-emeric"` — impossible to point this at a
sandbox project without editing code. Mirror what `dbt/profiles.yml`
already does (`env_var('DBT_BQ_PROJECT', 'analytics-with-emeric')`):

```
-    project: str = "analytics-with-emeric"
+    project: str = os.environ.get("GCP_PROJECT", "analytics-with-emeric")
```

## File: instacart-pipeline/ingestion/load_to_bigquery.py

### L76: [MEDIUM] Silent "attempt all, fail once at end" semantics — needs a docstring line

The per-table try/except + `return 1 if any failed` pattern is deliberate
("load everything, see the full summary, THEN abort dbt via `set -e`").
Not obvious from the code alone — Emeric-in-3-months will wonder why one
bad table doesn't stop the loader immediately.

Add one line at the top of `main()`, or invert the pattern (drop the
try/except, fail-fast on first exception). Either is fine — pick one
deliberately.

```
 def main() -> int:
+    """Load every table; log failures; exit non-zero if any table failed.

+    Design choice: attempt all tables (do NOT fail-fast) so a single run
+    surfaces every broken CSV in the logs. Downstream `set -e` in
+    run_pipeline.sh then aborts dbt when this returns 1.
+    """
     client = build_client()
```

### L80: [LOW] Bare `Exception` catch loses traceback context

`except Exception` is technically correct (doesn't swallow
`KeyboardInterrupt` — that's `BaseException`). But log the traceback so
operators can debug from CronJob logs:

```
-        except Exception as exc:  # noqa: BLE001 - on veut logguer puis continuer les autres tables
-            print(f"[{name}] ECHEC — {exc}", file=sys.stderr)
+        except Exception:  # noqa: BLE001 - on veut logguer puis continuer les autres tables
+            import traceback
+            print(f"[{name}] ECHEC", file=sys.stderr)
+            traceback.print_exc()
             results[name] = "ECHEC"
```

`kubectl logs job/…` will then include the full stack, not just
`str(exc)`.

## File: instacart-pipeline/Dockerfile

### L21: [MEDIUM] Container runs as root

No `USER` directive → the Pod runs as UID 0. The cohort cluster's
PodSecurity admission isn't strict yet, but a real prod cluster (or
turning on `restricted` PSA later) will reject the Pod.

```
 RUN dbt deps --project-dir dbt

+RUN useradd -u 1000 -m app && chown -R app /app
+USER app
+
 ENTRYPOINT ["./run_pipeline.sh"]
```

The `chown` also has a caching benefit — subsequent `docker run` commands
from other users won't hit permission surprises on `/app`.

### L19: [LOW] `dbt deps` at build time couples the image to dbt-hub availability

`RUN dbt deps --project-dir dbt` pulls `dbt_utils` from dbt-hub on every
build. If dbt-hub is down, your CI build fails even for unrelated changes.
Options:

- Vendor `dbt_utils` under `dbt/dbt_packages/` and commit it (bloat, but
  hermetic).
- Move `dbt deps` into `run_pipeline.sh` (moves the failure to runtime,
  where a retry might help).

Not urgent; flag when it bites you.

## File: instacart-pipeline/.dockerignore

### L10: [LOW] `*.md` excludes ALL markdown, including dbt model doc blocks

Right now this only drops READMEs from the image (fine). But dbt supports
`.md` sidecar files with `{% docs %}` blocks that live next to models —
the moment you add one, it silently disappears from the image and
`dbt docs generate` breaks with an unhelpful error.

Narrow it:

```
-*.md
+README.md
+*.md.tmp
```

Or exclude only the top-level README:

```
-*.md
+/*.md
```

Preserves `dbt/models/**/*.md` while dropping the repo-root README.

## File: instacart-pipeline/k8s/cronjob.yaml

### L26: [MEDIUM] Mutable `:latest` tag = future you can't tell which build shipped

`image: ghcr.io/hemrick/instacart-pipeline:latest` — works today because
K8s defaults to `imagePullPolicy: Always` for the `:latest` tag. The
moment you retag `:v1`, that default flips to `IfNotPresent` and the
node's cached blob wins, silently.

Long-term pattern (tag with git SHA on every push):

```sh
TAG=$(git rev-parse --short HEAD)
docker buildx build --platform linux/amd64 \
  -t ghcr.io/hemrick/instacart-pipeline:$TAG --push .
kubectl -n hemrick set image cronjob/instacart-pipeline \
  instacart-pipeline=ghcr.io/hemrick/instacart-pipeline:$TAG
```

Now `kubectl describe pod` tells you exactly which build shipped. Same
trap I hit during Tambo prep — same tag pointed to two different builds,
cost me 15 min.

### L40: [MEDIUM] `memory: 512Mi` limit likely tight for real Kaggle-scale runs

dbt-core + BQ client + Python loader can spike past 512Mi once you hit
the full dataset. Silent `OOMKilled` restarts at 06:00 UTC = bad debugging
UX.

Benchmark the first manual run, then set the limit to ~1.5× observed
peak:

```sh
kubectl -n hemrick top pod -l app=instacart-pipeline
# Or Lens → Workloads → Pods → your Pod → Metrics.
# Any OOMKilled in `kubectl describe pod` → bump.
```

Same reasoning applies to `activeDeadlineSeconds: 1800` (L15) —
benchmark full-scale runtime and add a 2x buffer, then add a comment
above the line with the observed duration.

### L14: [LOW] `backoffLimit: 1` is fine only if the pipeline is idempotent

Your `WRITE_TRUNCATE` disposition in `load_to_bigquery.py` makes the load
step idempotent, and dbt `run --select product_performance` recreates the
table. So a retry after a transient BQ error is safe. Worth a one-line
comment above `backoffLimit` to record that assumption — future-Emeric
will thank you when he adds an INSERT-append step and wonders why retries
duplicate rows.

## File: instacart-pipeline/dbt/profiles.yml

### L10: [MEDIUM] Missing env var renders as empty string, dbt fails with a cryptic error

`keyfile: "{{ env_var('GCP_SERVICE_ACCOUNT_LOAD_AND_DBT') }}"` — if the
env is unset, Jinja renders `""`, and dbt tries to open `""` as a keyfile
with a not-obviously-related error.

Match the pattern you used two lines above:

```
-      keyfile: "{{ env_var('GCP_SERVICE_ACCOUNT_LOAD_AND_DBT') }}"
+      keyfile: "{{ env_var('GCP_SERVICE_ACCOUNT_LOAD_AND_DBT', '/MISSING-set-GCP_SERVICE_ACCOUNT_LOAD_AND_DBT-env') }}"
```

Now the failure message points straight at the missing env var name.

## File: instacart-pipeline/pyproject.toml

### L10: [LOW] Open upper bound on dbt versions

`dbt-core>=1.8` accepts any 1.x AND 2.x major. A future dbt 2.0 will
almost certainly break your project layout. Cap the major:

```
-    "dbt-core>=1.8",
-    "dbt-bigquery>=1.8",
+    "dbt-core>=1.8,<2",
+    "dbt-bigquery>=1.8,<2",
```

Same principle for the other pins. Uv's `uv.lock` gives you build
reproducibility, but the upper bound protects `uv sync` from silently
taking a breaking version on the next fresh install.

## File: instacart-pipeline/README.md

### L104: [LOW] `sed` swap works, but `kubectl set image` is the K8s-native alternative

Your
`kubectl create job … --dry-run=client -o yaml | sed 's|:latest|:local-test|' | kubectl apply -f -`
is clever but hides a lot of moving parts. Native equivalent:

```sh
kubectl -n hemrick create job instacart-pipeline-local-test \
  --from=cronjob/instacart-pipeline

kubectl -n hemrick set image job/instacart-pipeline-local-test \
  instacart-pipeline=ghcr.io/hemrick/instacart-pipeline:local-test
```

Two commands, no string manipulation, more discoverable in
`kubectl --help`. Worth flagging as an alternative in a callout under
section 2.

---

## Nice things I noticed

- Dockerfile uses `uv sync --frozen --no-install-project --no-dev` then a
  second sync after COPY — textbook uv layer caching.
- `run_pipeline.sh` uses `set -euo pipefail` — right default; fail-loud
  between stages.
- README section 3.3 explains the private-package + `imagePullSecrets`
  pattern clearly — students will copy this.
- You spelled out the `--platform linux/amd64` reason (Apple Silicon →
  amd64 cluster). Saves the next person a 30-min head-scratch.
- `dbt/models/sources.yml` gates the raw layer with `unique`, `not_null`,
  `relationships`, `accepted_values`, and
  `dbt_utils.unique_combination_of_columns` — surprisingly thorough for a
  first pass.
