# Live Sessions — 2 × 30 min (Google Meet)

Two sessions, each ~30 min. Demo in Lens/FreeLens (see [`lens.md`](lens.md));
change things in Git.

- **Session 1** — setup-first: every student has cluster access, can see the
  cluster in Lens, and has deployed their first workload before they log off.
- **Session 2** — project-driven: built from the student project proposals that
  land between sessions. Each project gets a 5-min K8s-pattern walkthrough plus
  a short live demo at the end.

The cohort shares one managed cluster. **One namespace per student** = your
GitHub handle (lowercased). All your workloads (web, nextjs, cron, project)
go into that single namespace — drilled in S1 so nobody stomps each other's
work.

---

## Session 1 — Meet the cluster (~45 min, presentation-first)

Presentation-first: Louis demoes on his own screen, students watch, take notes,
and set up their own cluster access **after** the call using the pre-S1
screencast (pinned in Slack). Session doubles as **information gathering** —
build networking value inside the cohort + capture the info needed to make
S2 relevant to each student's project.

Block-based, not minute-locked. Adjust live based on the room.

| Block | Time   | Topic                                    | What Louis does                                                                                                                                                                                                                                                                                                                                                  |
| ----- | ------ | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | 5 min  | **Welcome + how this works**             | Two sessions (today + Fri 17 Jul), Slack `#help` async in between, project PR due Mon 6 Jul. Recording will be in Drive. Today = intro + tour, not hands-on.                                                                                                                                                                                                     |
| 2     | 15 min | **Round-robin intros (info-gather)**     | Each student ~3 min. Ask specifically: name / current role / stack / **do you use K8s at work today?** / **what do you want to deploy on K8s?** / **what's your biggest K8s question or fear?** Louis takes notes — this feeds S2 prep. Push for concrete project answers even if they say "not sure yet."                                                       |
| 3     | 5 min  | **Why K8s / when NOT K8s**               | 2-slide framing: K8s wins for stateful, non-HTTP, portability, non-Node stacks. PaaS (Vercel, Fly, Railway) wins for stateless web + edge. Knowing K8s makes you a better consumer of PaaS.                                                                                                                                                                     |
| 4     | 15 min | **Meet the cluster — Lens screen-share** | Louis shares screen. Walk: `export KUBECONFIG=...` + `kubectl get nodes` → open Lens → add cluster → Nodes → Workloads (Deployment → ReplicaSet → Pod chain) → Networking (Service, Ingress) → Namespaces (show pre-created student namespaces) → Storage → Custom Resources. **Anchor**: "this is what your projects will look like."                          |
| 5     | 5 min  | **Debugging with 4 lenses**              | Deploy `examples/troubleshooting/k8s/` live. Events tab on `broken-image` (ImagePullBackOff), previous-logs on `broken-command` (CrashLoopBackOff), describe on `broken-probe` (Pod Running, not Ready). Anchor: "when things break — always here."                                                                                                              |
| 6     | 5 min  | **Homework + wrap**                      | Post-call TODO list (see below). Reiterate: Slack `#help` for anything, project proposal PR due Mon 6 Jul. `docs/project-ideas.md` if stuck.                                                                                                                                                                                                                     |

**Slide: Hard rules for the shared cluster**

- Your namespace is pre-created — name = your GitHub handle (lowercased).
  All your workloads (web, nextjs, cron, project) go there. It has a
  `ResourceQuota` (2 CPU req, 2 GB mem, 25 Pods).
- Always `export HANDLE=<your-github-handle-lowercased>` and use `-n $HANDLE`.
  Never deploy to `default`.
- The shared `data` namespace (Postgres + Airflow) is **read-only** — don't
  redeploy `examples/data-pipeline`. Use the shared instance. Contribute new
  DAGs via PR to `examples/data-pipeline/dags/`.
- Image pushes from Apple Silicon need `docker buildx build --platform linux/amd64`
  (covered in `SETUP.md`, comes up in async week).

### Intro-round question script (Louis, read out loud)

Keep it tight — ~3 min per student.

1. Name + city + current role + stack you're building on.
2. Do you use K8s at work today? What's your relationship to it?
3. What do you want to deploy on K8s during this bootcamp? Be specific if you can.
4. What's your biggest K8s question or fear?

If they don't know #3: "That's fine — think out loud. What's a side project
or work idea that needs a scheduler, a DB, or something more than a webhook?"

### Post-call homework (share as Slack `#help` post after S1)

1. Set up kubeconfig + Lens per the pinned screencast.
2. `kubectl get nodes` should show all nodes Ready — paste output in Slack thread.
3. Accept the Classroom invite (link in `WELCOME.md`) if you haven't yet.
4. Open a PR with your project proposal — due **Mon 6 Jul**. Even 3 lines is
   fine, we'll refine on Slack.
5. Ping `#help` with any snag.

**Self-study covered by repo, not S1:**

CronJob (`examples/cronjob/`), ConfigMap/Secret patterns (visible in
`apps/postgres`), Ingress (`examples/nextjs-app/k8s/ingress.yaml`), more
debugging drills (`examples/troubleshooting/`). Each has a README and runs on
the shared cluster. Slack `#help` is the support channel.

## Troubleshooting (share with students if they hit issues)

| Symptom                                                                   | Fix                                                                                                                                              |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `kubectl: command not found`                                              | `brew install kubectl` (mac) or follow `SETUP.md` §1.                                                                                            |
| `error: KUBECONFIG environment variable not set`                          | `export KUBECONFIG=/path/to/k8s-bootcamp-guittonco-2026-06-kubeconfig.yaml`; persist in `~/.zshrc`.                                              |
| `Unable to connect to the server: dial tcp ... i/o timeout`               | Network/VPN/firewall blocking 443 to the DO control plane. Switch network, try again.                                                            |
| `forbidden: User "..." cannot create resource ... in namespace "default"` | You're using the wrong namespace. `kubectl get ns \| grep <your-handle>` should show your pre-created namespace; deploy with `-n <your-handle>`. |
| Lens shows "No clusters added"                                            | File → Add Cluster → from kubeconfig → point at the downloaded file. Multi-kubeconfig is supported.                                              |
| Pod `Pending` forever                                                     | Likely `ResourceQuota` exceeded. `kubectl -n <ns> describe quota` shows usage; `kubectl -n <ns> describe pod <pod>` shows the actual reason.     |
| Pod `ImagePullBackOff` for your own image                                 | Image not pushed, or package is private. `gh` → Your Packages → Settings → Public. Or check arch — `linux/amd64`, not arm64.                     |
| Pod `CrashLoopBackOff`                                                    | App is exiting. `kubectl -n <ns> logs <pod> --previous` to read the last crashed container's logs.                                               |

---

## Session 2 — Your projects, the K8s patterns they need (30 min)

**Built from project proposals.** Pre-session work (Mon 6 Jul – Wed 15 Jul):

1. Read every proposal PR. Identify the K8s pattern each one needs.
2. Group projects by pattern. Common buckets to expect:
   - **Web service** → Deployment + Service + Ingress (covered in S1 already → recap only)
   - **Scheduled job** → CronJob + concurrency/TTL patterns
   - **Stateful** → PVC + StatefulSet (Postgres in `apps/postgres` is the reference)
   - **Async pipeline** → Helm chart consumption (Airflow in `examples/data-pipeline`)
   - **Multi-service** → Service-to-Service networking, ConfigMap/Secret injection
3. Pick 2–3 pattern blocks to cover live. Leave the rest as repo pointers + Slack.
4. Order: pattern demo → live edit → student-project mapping.

| Min   | Topic                            | Source (fill after proposals land)                                                                     |
| ----- | -------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 0–3   | **Recap S1 + map the cohort**    | 1-slide: project list grouped by pattern. "Here's what we need to cover for your projects."            |
| 3–10  | **Pattern block 1**              | _TBD from proposals_ — e.g. Ingress + TLS, CronJob, StatefulSet                                        |
| 10–17 | **Pattern block 2**              | _TBD from proposals_                                                                                   |
| 17–22 | **Pattern block 3 OR Helm deep** | If 3+ projects use community charts: contrast hand-written `apps/postgres` vs `apache-airflow/airflow` |
| 22–28 | **Student demos**                | Each student: 30s screen-share of their project running in Lens. State 1 thing that fought them.       |
| 28–30 | **Wrap + async**                 | Slack stays open after the cohort. No synchronous office hours — everything async in `#help`.          |

**Stretch patterns that might appear (kept inline, not in S1):**

- **CRDs / Operators** — Strimzi Kafka is the clean teaching example:
  ```sh
  kubectl create namespace kafka-<handle>
  kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka-<handle>' -n kafka-<handle>
  kubectl apply -f https://strimzi.io/examples/latest/kafka/kafka-single-node.yaml -n kafka-<handle>
  ```
  Anchor: Helm packages _known_ apps; operators teach K8s about _new_ kinds of
  app via CRDs.
- **HPA / autoscaling** — only if a project has variable load.
- **NetworkPolicy** — only if a project asks for tenant isolation.

---

## Async week between sessions (Mon 6 – Thu 16 Jul)

- Students iterate on their project in their own namespaces.
- Louis on Slack `#help`, M–F, **24h SLA, intra-day best-effort**. No
  synchronous office hours; everything happens in `#help` or on the project PR.
- Louis can pull student code via `gh classroom` and inspect their namespace
  directly on the shared cluster — fast triage without a call.
- `@here` only when truly blocked. Default to channel post.
- By end-of-week each project should have: namespace + Deployment(s) +
  Service + at least one of (Ingress | CronJob | PVC | ConfigMap).

## References (for your S2 prep, not for sharing)

- `docs/louis/2026-06-26-curriculum/CKAD_Curriculum_v1.35.pdf` — domain
  checklist (App Design 20%, Build & Deploy 20%, Env & Config 25%, Observability
  15%, Services & Networking 20%). Use to sanity-check coverage gaps per project.
- killercoda K8s + Helm labs — pattern for hands-on flow if a pattern block
  needs a fallback exercise.
- kodekloud Lens IDE course — visual-first framing already baked into the
  Lens-tour stop in S1.
