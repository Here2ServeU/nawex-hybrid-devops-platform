# Changelog

All notable changes to the NAWEX platform are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- LLM gateway service (`app/nawex-llm-gateway/`) — provider-agnostic completion
  proxy with prompt caching, token-usage telemetry, mock provider for offline
  CI, and lazy-loaded Anthropic provider for production.
- RAG service (`app/nawex-rag-service/`) — ingest, deterministic hash-based
  embedding, in-memory retrieval, and grounded generation through the LLM
  gateway with explicit per-document citations.
- Kubernetes manifests for both AI services in `k8s/base/platform.yaml`
  (PSA-restricted, non-root, dedicated ServiceAccounts, HPA, PDB, and
  NetworkPolicies that scope RAG → LLM gateway traffic to the minimum needed).
- "Who This Is For" section in `README.md` describing how full-stack engineers
  moving into LLM, RAG, and ML production work map onto NAWEX primitives.
- Apache 2.0 LICENSE.
- `SECURITY.md` with vulnerability reporting process and defense-in-depth summary.
- `CONTRIBUTING.md`, `CODEOWNERS`, and GitHub issue templates.
- Fleet-wide bash environment baseline deployed via `/etc/profile.d/nawex-baseline.sh`
  from the Ansible `system` role (audit-grade history, platform PATH, safe defaults).
- Bare-metal OpenShift operations runbook.
- Dynatrace operator placeholder under `observability/dynatrace/`.

## [1.0.0] — 2026-04-23

### Added
- GitLab CI pipeline with feature parity to GitHub Actions (six quality gates).
- Reusable Terraform module and Ansible role for bare-metal targets.
- OpenShift on bare-metal IPI support (Cisco UCS, HPE ProLiant, Dell PowerEdge).
- OpenShift targets: ROSA (AWS) and self-managed vSphere IPI.
- vSphere on-prem, AWS EKS, and Azure AKS environment targets.
- VM-to-container migration pipeline (assess → containerize → deploy).
- FinOps and AIOps Python utilities (rightsizing, budget burn, anomaly detection).
- Multi-burn-rate SLO alerting with Slack incident response.
- Platform learning guide and operations reference.
- CIS-aligned Linux baseline (packages, sysctl hardening, auditd, node_exporter, hardened Docker).
