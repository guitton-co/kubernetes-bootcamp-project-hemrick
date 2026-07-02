# Example: Next.js app (on Kubernetes)

A hello-world Next.js (App Router, TypeScript) app, containerised with the
standalone build and deployed with a Deployment + Service + (optional) Ingress.
Same shape as `../web-service`, but for the JS/TS stack.

## Run locally first

```sh
npm install
npm run dev        # http://localhost:3000
```

## Build & push the image

> On Apple Silicon (M1/M2/M3), build for `linux/amd64` — the cohort cluster
> nodes are amd64.

```sh
cd examples/nextjs-app
docker buildx build --platform linux/amd64 \
  -t ghcr.io/<your-username>/k8s-kata-nextjs:latest --push .
```

Then set that image name in `k8s/deployment.yaml`.

## Deploy

```sh
export HANDLE=<your-github-handle-lowercased>
kubectl -n $HANDLE apply -f k8s/
kubectl -n $HANDLE get pods
```

## Reach it

```sh
kubectl -n $HANDLE port-forward svc/nextjs 3000:80
# open http://localhost:3000
```

The home page prints the serving pod's hostname — scale the Deployment in Lens
and refresh to watch requests land on different pods.

## Make it yours

Replace the page and API routes with your app. Keep `/api/health` (or update the
probes in `k8s/deployment.yaml`) so Kubernetes can tell when a pod is ready.

## Notes

- `next.config.mjs` sets `output: "standalone"` — the Dockerfile depends on it.
- The image runs as a non-root user and listens on port 3000.
