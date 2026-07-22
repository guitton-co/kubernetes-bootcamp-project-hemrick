#!/usr/bin/env bash
# Starts the nao-db Cloud SQL instance (billed while running).
set -euo pipefail

INSTANCE="nao-db"
PROJECT="analytics-with-emeric"

echo "Starting Cloud SQL instance ${INSTANCE}..."
gcloud sql instances patch "${INSTANCE}" \
  --activation-policy=ALWAYS \
  --project="${PROJECT}"

echo "Waiting for ${INSTANCE} to come up..."
until [ "$(gcloud sql instances describe "${INSTANCE}" --project="${PROJECT}" --format='value(state)')" = "RUNNABLE" ]; do
  sleep 5
done

echo "${INSTANCE} is running."
