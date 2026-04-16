#!/usr/bin/env bash
# rollback_last_deploy.sh — undo the most recent rollout for a deployment.
#
# Called by scripts/incident_respond.sh after an engineer APPROVES the remediation.
# Safe to run repeatedly. Honors DRY_RUN=1.
#
# Inputs (via --incident <path>): labels.service is used to pick the deployment.

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
DEPLOY="${SERVICE}"

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: %s\n' "$*"
  else
    "$@"
  fi
}

echo "[rollback] target deployment/${DEPLOY} in namespace ${NAMESPACE}"
run kubectl rollout history "deployment/${DEPLOY}" -n "${NAMESPACE}"
run kubectl rollout undo "deployment/${DEPLOY}" -n "${NAMESPACE}"
run kubectl rollout status "deployment/${DEPLOY}" -n "${NAMESPACE}" --timeout=180s
echo "[rollback] complete"
