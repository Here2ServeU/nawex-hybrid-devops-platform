#!/usr/bin/env bash
# investigate_slo_burn.sh — scale up one replica and dump recent error logs.
#
# Called when APPROVED for warning-severity SLO burn alerts. Does not roll back.
# Honors DRY_RUN=1.

set -euo pipefail

INCIDENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --incident) INCIDENT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "${INCIDENT}" ]] || { echo "--incident required" >&2; exit 2; }

NAMESPACE="${KUBE_NAMESPACE:-nawex-platform}"
SERVICE="$(jq -r '.labels.service // "nawex-api"' "${INCIDENT}")"

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: %s\n' "$*"
  else
    "$@"
  fi
}

echo "[investigate] scaling ${SERVICE} +1 replica for headroom"
CURRENT=$(kubectl get deployment "${SERVICE}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
NEW=$((CURRENT + 1))
run kubectl scale "deployment/${SERVICE}" -n "${NAMESPACE}" --replicas="${NEW}"

echo "[investigate] recent 5xx-ish lines from ${SERVICE} (last 5m):"
run kubectl logs "deployment/${SERVICE}" -n "${NAMESPACE}" --since=5m --tail=200 \
  | grep -E '(ERROR|5[0-9]{2}|Traceback)' || true

echo "[investigate] done — review logs and decide on rollback if pattern persists"
