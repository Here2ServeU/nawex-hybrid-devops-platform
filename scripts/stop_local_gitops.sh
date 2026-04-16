#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${ROOT_DIR}/.local"
CLUSTER_NAME="${CLUSTER_NAME:-nawex-platform}"
GIT_DAEMON_PID_FILE="${LOCAL_DIR}/git-daemon.pid"

if [[ -f "${GIT_DAEMON_PID_FILE}" ]] && kill -0 "$(cat "${GIT_DAEMON_PID_FILE}")" >/dev/null 2>&1; then
  echo "[nawex] stopping git daemon"
  kill "$(cat "${GIT_DAEMON_PID_FILE}")"
  rm -f "${GIT_DAEMON_PID_FILE}"
fi

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "[nawex] deleting kind cluster '${CLUSTER_NAME}'"
  kind delete cluster --name "${CLUSTER_NAME}"
fi
