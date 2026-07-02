#!/usr/bin/env bash
#
# Pre-create one namespace per student on the shared cohort cluster and apply
# a ResourceQuota + LimitRange to it. Namespace name = GitHub handle
# (lowercased). Students put ALL their workloads (web, nextjs, cron, project,
# troubleshooting) into that single namespace.
#
# Usage:
#   ./scripts/init-cohort-namespaces.sh handle1 handle2 handle3 ...
#
# Idempotent — safe to re-run when a new handle joins.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <github-handle> [github-handle ...]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTA_FILE="${SCRIPT_DIR}/../apps/resource-quota/quota.yaml"

for handle in "$@"; do
  # K8s namespace names must be RFC 1123 (lowercase). GitHub handles are
  # case-insensitive, so normalise to lowercase here.
  ns="$(echo "${handle}" | tr '[:upper:]' '[:lower:]')"
  echo "==> ${ns}"
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${ns}" apply -f "${QUOTA_FILE}"
done

echo
echo "Done. Created namespaces + ResourceQuota for: $*"
echo "Verify with: kubectl get ns | grep -Ei '$(IFS=\|; echo "$*")'"
