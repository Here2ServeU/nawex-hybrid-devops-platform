#!/usr/bin/env bash
# incident_respond.sh — triage AlertManager incidents locally.
#
# Usage:
#   incident_respond.sh list
#   incident_respond.sh show     <fingerprint|id>
#   incident_respond.sh approve  <fingerprint|id>   # run the mapped remediation
#   incident_respond.sh deny     <fingerprint|id>   # acknowledge without remediating
#   incident_respond.sh ingest   <path/to/alert.json>   # append an AlertManager webhook payload
#
# Incident state is stored under .incidents/ at the repo root. Each incident is a
# JSON file named <fingerprint>.json written by the AlertManager webhook receiver
# (scripts/alert_webhook.py) or by `ingest`.
#
# Env (optional):
#   SLACK_WEBHOOK_URL  — post approve/deny audit trail back to Slack
#   KUBE_CONTEXT       — kubectl context override (defaults to current)
#   KUBE_NAMESPACE     — target namespace for remediations (default nawex-platform)
#   DRY_RUN=1          — print the remediation command without running it

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCIDENT_DIR="${NAWEX_INCIDENT_DIR:-${ROOT_DIR}/.incidents}"
REMEDIATION_DIR="${ROOT_DIR}/scripts/remediations"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-nawex-platform}"

mkdir -p "${INCIDENT_DIR}"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

incident_path() {
  local id="$1"
  local p="${INCIDENT_DIR}/${id}.json"
  [[ -f "${p}" ]] || die "unknown incident: ${id} (no such file ${p})"
  printf '%s' "${p}"
}

# Extract a scalar field from an incident JSON using jq.
field() {
  local path="$1" jq_expr="$2"
  jq -r "${jq_expr}" "${path}"
}

cmd_list() {
  local found=0
  shopt -s nullglob
  for f in "${INCIDENT_DIR}"/*.json; do
    found=1
    local id status severity service alertname action
    id="$(basename "${f}" .json)"
    status="$(jq -r '.status // "firing"' "${f}")"
    severity="$(jq -r '.labels.severity // "-"' "${f}")"
    service="$(jq -r '.labels.service // "-"' "${f}")"
    alertname="$(jq -r '.labels.alertname // "-"' "${f}")"
    action="$(jq -r '.labels.remediation_action // "-"' "${f}")"
    printf '%-12s  %-10s  %-9s  %-18s  %-22s  action=%s\n' \
      "${id:0:12}" "${status}" "${severity}" "${service}" "${alertname}" "${action}"
  done
  shopt -u nullglob
  [[ "${found}" -eq 1 ]] || log "no incidents recorded in ${INCIDENT_DIR}"
}

cmd_show() {
  local id="${1:?show requires an incident id}"
  local path
  path="$(incident_path "${id}")"
  jq '.' "${path}"
  local action
  action="$(jq -r '.labels.remediation_action // empty' "${path}")"
  if [[ -n "${action}" ]]; then
    echo
    log "mapped remediation: ${REMEDIATION_DIR}/${action}.sh"
    if [[ -x "${REMEDIATION_DIR}/${action}.sh" ]]; then
      log "preview (DRY_RUN=1):"
      DRY_RUN=1 "${REMEDIATION_DIR}/${action}.sh" --incident "${path}" || true
    else
      log "WARNING: remediation script not found or not executable"
    fi
  fi
}

slack_audit() {
  local outcome="$1" id="$2" action="$3"
  [[ -n "${SLACK_WEBHOOK_URL}" ]] || return 0
  local actor
  actor="$(id -un 2>/dev/null || echo unknown)"
  local payload
  payload="$(jq -cn \
    --arg text "[incident ${id}] ${outcome} by ${actor} — action=${action}" \
    '{text: $text}')"
  curl -sS --max-time 5 -H 'Content-Type: application/json' \
    --data "${payload}" "${SLACK_WEBHOOK_URL}" >/dev/null || log "WARNING: Slack audit post failed"
}

cmd_approve() {
  local id="${1:?approve requires an incident id}"
  local path action script
  path="$(incident_path "${id}")"
  action="$(jq -r '.labels.remediation_action // empty' "${path}")"
  [[ -n "${action}" ]] || die "incident ${id} has no remediation_action label"
  script="${REMEDIATION_DIR}/${action}.sh"
  [[ -x "${script}" ]] || die "no executable remediation script: ${script}"

  log "APPROVE ${id} — running ${action}"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN=1 — printing command instead of executing"
    printf '%s --incident %s\n' "${script}" "${path}"
  else
    "${script}" --incident "${path}"
  fi
  jq --arg ts "$(date -u +%FT%TZ)" '.status = "remediated" | .remediated_at = $ts' "${path}" > "${path}.tmp"
  mv "${path}.tmp" "${path}"
  slack_audit "approved" "${id}" "${action}"
}

cmd_deny() {
  local id="${1:?deny requires an incident id}"
  local path action
  path="$(incident_path "${id}")"
  action="$(jq -r '.labels.remediation_action // "-"' "${path}")"
  log "DENY ${id} — acknowledging without remediation"
  jq --arg ts "$(date -u +%FT%TZ)" '.status = "denied" | .denied_at = $ts' "${path}" > "${path}.tmp"
  mv "${path}.tmp" "${path}"
  slack_audit "denied" "${id}" "${action}"
}

cmd_ingest() {
  local file="${1:?ingest requires a path to an AlertManager webhook payload JSON}"
  [[ -f "${file}" ]] || die "no such file: ${file}"
  # AlertManager posts a batch: {status, alerts:[{fingerprint, labels, annotations, ...}]}.
  local count=0
  while read -r alert; do
    local fp
    fp="$(jq -r '.fingerprint' <<<"${alert}")"
    [[ -n "${fp}" && "${fp}" != "null" ]] || continue
    jq '.' <<<"${alert}" > "${INCIDENT_DIR}/${fp}.json"
    count=$((count + 1))
  done < <(jq -c '.alerts[]?' "${file}")
  log "ingested ${count} incident(s)"
}

usage() {
  sed -n '1,22p' "$0" >&2
  exit 2
}

main() {
  require_cmd jq
  local sub="${1:-}"; shift || true
  case "${sub}" in
    list)    cmd_list "$@" ;;
    show)    cmd_show "$@" ;;
    approve) cmd_approve "$@" ;;
    deny)    cmd_deny "$@" ;;
    ingest)  cmd_ingest "$@" ;;
    ""|-h|--help|help) usage ;;
    *) log "unknown subcommand: ${sub}"; usage ;;
  esac
}

main "$@"
