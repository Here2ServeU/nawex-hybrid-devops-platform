#!/usr/bin/env bash
# reduce_requests.sh — print a kubectl patch that reduces CPU/mem requests.
#
# Intentionally does NOT apply automatically: request changes affect scheduling and
# benefit from a human reviewing the numbers. Engineers can pipe the printed patch
# into `kubectl apply -f -` when ready. Honors DRY_RUN=1.

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

cat <<YAML
# Preview patch — review, then apply with:
#   kubectl -n ${NAMESPACE} patch deployment ${SERVICE} --type merge -f - <<<'<this yaml>'
spec:
  template:
    spec:
      containers:
        - name: ${SERVICE}
          resources:
            requests:
              cpu: "60m"
              memory: "96Mi"
            limits:
              cpu: "300m"
              memory: "192Mi"
YAML
echo "[reduce-requests] dry review only — not applied"
