#!/usr/bin/env bash
# worker_heap_profile.sh — capture a heap profile and restart one worker pod.
#
# Called when APPROVED for worker memory pressure. Honors DRY_RUN=1.

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
WORKDIR="${NAWEX_INCIDENT_DIR:-$(pwd)/.incidents}/artifacts"
mkdir -p "${WORKDIR}"

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: %s\n' "$*"
  else
    "$@"
  fi
}

POD=$(kubectl get pods -n "${NAMESPACE}" -l app=nawex-worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "${POD}" ]]; then
  echo "[heap] no nawex-worker pod found in ${NAMESPACE}"
  exit 1
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
PROFILE="${WORKDIR}/heap-${POD}-${TS}.txt"
echo "[heap] capturing top / RSS snapshot from ${POD} into ${PROFILE}"
run kubectl exec -n "${NAMESPACE}" "${POD}" -- sh -c 'cat /proc/1/status 2>/dev/null; echo ---; ps -eo pid,rss,cmd 2>/dev/null || true' \
  | tee "${PROFILE}" >/dev/null

echo "[heap] restarting ${POD}"
run kubectl delete pod "${POD}" -n "${NAMESPACE}"

echo "[heap] done — profile saved to ${PROFILE}"
