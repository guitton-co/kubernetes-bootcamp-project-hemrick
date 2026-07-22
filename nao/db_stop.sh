#!/usr/bin/env bash
# Stops the nao-db Cloud SQL instance to avoid compute charges while idle.
# Storage cost still applies, but compute billing stops.
set -euo pipefail

INSTANCE="nao-db"
PROJECT="analytics-with-emeric"

echo "Stopping Cloud SQL instance ${INSTANCE}..."
gcloud sql instances patch "${INSTANCE}" \
  --activation-policy=NEVER \
  --project="${PROJECT}"

echo "${INSTANCE} stopped. The nao Cloud Run service will be unreachable until you run db_start.sh again."
