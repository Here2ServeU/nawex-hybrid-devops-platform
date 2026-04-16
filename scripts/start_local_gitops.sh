#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${ROOT_DIR}/.local"
SNAPSHOT_DIR="${LOCAL_DIR}/snapshot-repo"
BARE_REPO_BASE="${LOCAL_DIR}/git"
REPO_NAME="$(basename "${ROOT_DIR}")"
BARE_REPO_DIR="${BARE_REPO_BASE}/${REPO_NAME}.git"
RENDER_DIR="${LOCAL_DIR}/rendered-gitops"
KIND_CONFIG="${ROOT_DIR}/test/kind/argocd-kind.yaml"
CLUSTER_NAME="${CLUSTER_NAME:-nawex-platform}"
LOCAL_GIT_HOST="${LOCAL_GIT_HOST:-host.docker.internal}"
LOCAL_GIT_PORT="${LOCAL_GIT_PORT:-9418}"
LOCAL_GIT_BRANCH="${LOCAL_GIT_BRANCH:-local-test}"
LOCAL_GIT_URL="git://${LOCAL_GIT_HOST}:${LOCAL_GIT_PORT}/${REPO_NAME}.git"
API_IMAGE="${API_IMAGE:-nawex-api:local}"
ARGOCD_INSTALL_URL="${ARGOCD_INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
GIT_DAEMON_PID_FILE="${LOCAL_DIR}/git-daemon.pid"
GIT_DAEMON_LOG="${LOCAL_DIR}/git-daemon.log"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[nawex] missing required command: $1" >&2
    exit 1
  fi
}

ensure_prereqs() {
  local cmd
  for cmd in docker git kind kubectl tar; do
    require_cmd "${cmd}"
  done
}

create_cluster() {
  if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
    echo "[nawex] kind cluster '${CLUSTER_NAME}' already exists"
    return
  fi

  echo "[nawex] creating kind cluster '${CLUSTER_NAME}'"
  kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
}

build_and_load_image() {
  echo "[nawex] building ${API_IMAGE}"
  docker build -t "${API_IMAGE}" "${ROOT_DIR}/app/nawex-api"

  echo "[nawex] loading ${API_IMAGE} into kind"
  kind load docker-image "${API_IMAGE}" --name "${CLUSTER_NAME}"
}

install_argocd() {
  echo "[nawex] installing Argo CD"
  kubectl get namespace argocd >/dev/null 2>&1 || kubectl create namespace argocd
  kubectl apply -n argocd -f "${ARGOCD_INSTALL_URL}"
  kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
  kubectl wait --for=condition=Available deployment/argocd-repo-server -n argocd --timeout=300s
}

prepare_snapshot_repo() {
  local git_author_name git_author_email

  mkdir -p "${LOCAL_DIR}" "${BARE_REPO_BASE}" "${RENDER_DIR}"
  rm -rf "${SNAPSHOT_DIR}"
  mkdir -p "${SNAPSHOT_DIR}"

  echo "[nawex] snapshotting the current workspace into ${LOCAL_GIT_BRANCH}"
  tar \
    --exclude=.git \
    --exclude=.local \
    --exclude=__pycache__ \
    -cf - \
    -C "${ROOT_DIR}" . | tar -xf - -C "${SNAPSHOT_DIR}"

  git_author_name="$(git -C "${ROOT_DIR}" config user.name || echo "nawex-local")"
  git_author_email="$(git -C "${ROOT_DIR}" config user.email || echo "nawex-local@example.invalid")"

  git -C "${SNAPSHOT_DIR}" init
  git -C "${SNAPSHOT_DIR}" checkout -B "${LOCAL_GIT_BRANCH}"
  git -C "${SNAPSHOT_DIR}" add .
  git -C "${SNAPSHOT_DIR}" -c user.name="${git_author_name}" -c user.email="${git_author_email}" \
    commit --allow-empty -m "Local GitOps snapshot for Argo CD testing"

  rm -rf "${BARE_REPO_DIR}"
  git init --bare "${BARE_REPO_DIR}" >/dev/null
  git -C "${SNAPSHOT_DIR}" remote add origin "${BARE_REPO_DIR}"
  git -C "${SNAPSHOT_DIR}" push --force origin "HEAD:${LOCAL_GIT_BRANCH}" >/dev/null
}

start_git_daemon() {
  mkdir -p "${LOCAL_DIR}"

  if [[ -f "${GIT_DAEMON_PID_FILE}" ]] && kill -0 "$(cat "${GIT_DAEMON_PID_FILE}")" >/dev/null 2>&1; then
    echo "[nawex] git daemon already running on port ${LOCAL_GIT_PORT}"
    return
  fi

  echo "[nawex] starting git daemon on ${LOCAL_GIT_PORT}"
  nohup git daemon \
    --reuseaddr \
    --base-path="${BARE_REPO_BASE}" \
    --export-all \
    --listen=0.0.0.0 \
    --port="${LOCAL_GIT_PORT}" \
    "${BARE_REPO_BASE}" >"${GIT_DAEMON_LOG}" 2>&1 &
  echo $! > "${GIT_DAEMON_PID_FILE}"
  sleep 1
}

render_manifest() {
  local source_file target_file
  source_file="$1"
  target_file="$2"

  sed \
    -e "s|https://github.com/example-org/nawex-hybrid-devops-platform.git|${LOCAL_GIT_URL}|g" \
    -e "s|targetRevision: main|targetRevision: ${LOCAL_GIT_BRANCH}|g" \
    "${source_file}" > "${target_file}"
}

apply_local_gitops() {
  mkdir -p "${RENDER_DIR}/gitops/local/apps"

  render_manifest "${ROOT_DIR}/gitops/project.yaml" "${RENDER_DIR}/gitops/project.yaml"
  render_manifest "${ROOT_DIR}/gitops/local/root-application.yaml" "${RENDER_DIR}/gitops/local/root-application.yaml"
  render_manifest "${ROOT_DIR}/gitops/local/apps/local-platform.yaml" "${RENDER_DIR}/gitops/local/apps/local-platform.yaml"

  echo "[nawex] applying Argo CD project and local root application"
  kubectl apply -f "${RENDER_DIR}/gitops/project.yaml"
  kubectl apply -f "${RENDER_DIR}/gitops/local/root-application.yaml"
}

wait_for_platform() {
  echo "[nawex] waiting for Argo CD to sync the local platform"

  until kubectl get deployment nawex-api -n nawex-local >/dev/null 2>&1; do
    sleep 2
  done

  kubectl rollout status deployment/nawex-api -n nawex-local --timeout=300s
}

print_next_steps() {
  cat <<EOF
[nawex] local GitOps test environment is ready

Cluster: ${CLUSTER_NAME}
Local Git source: ${LOCAL_GIT_URL} (${LOCAL_GIT_BRANCH})
Argo CD root app: nawex-local-root
Test namespace: nawex-local

Next steps:
  kubectl port-forward svc/argocd-server -n argocd 8080:443
  kubectl port-forward svc/nawex-api -n nawex-local 8081:80
  ./scripts/smoke_test.sh
EOF
}

main() {
  ensure_prereqs
  create_cluster
  build_and_load_image
  install_argocd
  prepare_snapshot_repo
  start_git_daemon
  apply_local_gitops
  wait_for_platform
  print_next_steps
}

main "$@"
