#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-nawex-local}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
PORT_FORWARD_PID=""

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]] && kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
    kill "${PORT_FORWARD_PID}"
  fi
}

trap cleanup EXIT

echo "[nawex] waiting for rollout in namespace ${NAMESPACE}"
kubectl rollout status deployment/nawex-api -n "${NAMESPACE}" --timeout=180s

echo "[nawex] port-forwarding nawex-api to localhost:${LOCAL_PORT}"
kubectl port-forward svc/nawex-api -n "${NAMESPACE}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 3

echo "[nawex] checking /healthz"
curl --fail --silent "http://127.0.0.1:${LOCAL_PORT}/healthz" >/dev/null

echo "[nawex] checking /readyz"
curl --fail --silent "http://127.0.0.1:${LOCAL_PORT}/readyz" >/dev/null

echo "[nawex] checking mission endpoint"
curl --fail --silent "http://127.0.0.1:${LOCAL_PORT}/api/v1/mission"
echo
