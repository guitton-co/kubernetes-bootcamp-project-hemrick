# Example: Troubleshooting (broken Pods on purpose)

Three Deployments that fail in three different ways. The point is to drill
the **four lenses** workflow — Logs, Shell, Events, YAML — on real failures
you'll hit in your own projects.

## Deploy

```sh
export HANDLE=<your-github-handle-lowercased>     # one-time per shell
kubectl -n $HANDLE apply -f examples/troubleshooting/k8s/
kubectl -n $HANDLE get pods
```

You should see three Pods, all unhealthy in different ways.

## The three failures

### 1. `broken-image` — ImagePullBackOff

The image reference points at a registry path that doesn't exist.

- **Open in Lens** → click the Pod → **Events** tab. You'll see
  `Failed to pull image ...: not found`.
- **Logs** tab: empty. The container never started.
- **Lesson**: image errors surface in Events, not Logs.

### 2. `broken-command` — CrashLoopBackOff

A `busybox` container prints "starting up", waits 2s, prints "fatal: BOOM",
exits 1. Kubelet restarts it. Restart count climbs.

- **Logs** tab → use the "previous" toggle to read the last crashed container.
  You'll see "fatal: BOOM".
- **Events** tab → `Back-off restarting failed container`.
- **Lesson**: when a Pod is restarting, the *current* container has no
  history — read the *previous* logs to find the actual error.

### 3. `broken-probe` — Pod Running but not Ready

The container starts fine, the app works, but the readiness probe hits a
404 route. Pod stays `0/1`, no traffic routes to it from the Service.

- **Events** tab → `Readiness probe failed: HTTP probe failed with statuscode: 404`.
- **Shell** into the container, `curl localhost:8000/health` works,
  `curl localhost:8000/this-route-does-not-exist` returns 404.
- **Lesson**: Pod `Running` ≠ Pod `Ready`. The Service only routes traffic
  to Ready pods. Misconfigured probes silently break your app's reachability.

## Cleanup

```sh
kubectl -n $HANDLE delete -f examples/troubleshooting/k8s/
```

## Make it harder

After you've worked through these, try breaking one of your *own* deploys
on purpose:

- Mis-spell a ConfigMap name in `envFrom` → Pod stuck in `CreateContainerConfigError`
- Set `requests.memory` higher than the node has → Pod stuck `Pending`,
  Events show `Insufficient memory`
- Mount a Secret that doesn't exist → Pod stuck `ContainerCreating`

Each one teaches a different field on the Pod object.
