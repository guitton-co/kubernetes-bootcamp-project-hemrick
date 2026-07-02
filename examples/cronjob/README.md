# Example: CronJob (scheduled batch work on Kubernetes)

Schedule something to run on a cron expression. No image to build — uses
`busybox` so you can focus on the resource model.

## What's in here

- `k8s/cronjob.yaml` — a `CronJob` that runs every 2 minutes, prints the
  timestamp and the Pod name. Notable fields:
  - `schedule` — standard cron, server-side time zone unless you set `timeZone`.
  - `concurrencyPolicy: Forbid` — don't overlap runs; the default `Allow` will
    happily stack them when work runs long.
  - `ttlSecondsAfterFinished` + `successfulJobsHistoryLimit` — auto-garbage-
    collect old Jobs/Pods. Without these you'll drown in `Completed` Pods.
  - `restartPolicy: OnFailure` + `backoffLimit: 2` — retry twice on crash, then
    give up; Job is marked Failed.

## Deploy

```sh
export HANDLE=<your-github-handle-lowercased>
kubectl -n $HANDLE apply -f examples/cronjob/k8s/cronjob.yaml
```

## Watch the chain `CronJob → Job → Pod`

```sh
kubectl -n $HANDLE get cronjob,jobs,pods
kubectl -n $HANDLE logs job/$(kubectl -n $HANDLE get jobs -o name | head -1 | cut -d/ -f2)
```

In FreeLens/Lens: open the CronJob → see the spawned Jobs in the right panel,
click any Job → see its Pod → check Logs/Events.

## Try this

- Edit the schedule to `"*/1 * * * *"` and `apply` — next run picks up the
  change.
- Change `concurrencyPolicy: Forbid` to `Allow`, then make the command sleep
  longer than the schedule (`sleep 90`) and watch runs overlap.
- Break it on purpose — `command: ["false"]` — and watch `backoffLimit` cap
  the retries.

## Make it yours

Replace the `busybox` container with whatever you want scheduled: a database
backup (mount a Secret with creds, write to a PVC), a Python script (build
your own image), a curl to a webhook. The Job-Pod plumbing stays identical.
