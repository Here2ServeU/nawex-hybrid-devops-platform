#!/usr/bin/env bash
# scale_down_offhours.sh — scale worker replicas down for FinOps cost control.
#
# Called when APPROVED for budget-burn alerts. Only runs if the current hour is
# outside business hours (08-19 local) unless NAWEX_FORCE=1.
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
WORKER_DEPLOY="${WORKER_DEPLOY:-nawex-worker}"
OFFHOURS_REPLICAS="${OFFHOURS_REPLICAS:-1}"

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: %s\n' "$*"
  else
    "$@"
  fi
}

HOUR=$(date +%H)
if [[ "${NAWEX_FORCE:-0}" != "1" ]] && (( 10#${HOUR} >= 8 && 10#${HOUR} < 19 )); then
  echo "[scale-down] business hours (${HOUR}:00) — refusing to scale down. Set NAWEX_FORCE=1 to override."
  exit 1
fi

echo "[scale-down] setting ${WORKER_DEPLOY} to ${OFFHOURS_REPLICAS} replica(s)"
run kubectl scale "deployment/${WORKER_DEPLOY}" -n "${NAMESPACE}" --replicas="${OFFHOURS_REPLICAS}"
run kubectl rollout status "deployment/${WORKER_DEPLOY}" -n "${NAMESPACE}" --timeout=120s
echo "[scale-down] done"
