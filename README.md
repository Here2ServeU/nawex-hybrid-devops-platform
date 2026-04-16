# nawex-hybrid-devops-platform

Enterprise Hybrid DevOps, FinOps, SRE, AIOps, and GitOps reference implementation for a fictional regulated mission data platform.

## Positioning

This repository demonstrates a hybrid-ready platform that deploys and operates containerized workloads on Linux and Kubernetes using Terraform, Ansible, GitHub Actions, Argo CD GitOps, observability, FinOps guardrails, and Python-based AIOps helpers.

## What This Proves

- Linux administration in enterprise-style environments
- Docker and Kubernetes packaging and deployment
- Infrastructure as code with reusable Terraform modules
- Configuration management with Ansible
- Python and Bash automation
- CI/CD with GitHub Actions
- GitOps delivery with Argo CD and environment overlays
- FinOps guardrails and reporting
- SRE controls using SLIs, SLOs, and error budgets
- AIOps-driven anomaly and burn-risk analysis

## Services

- `nawex-web-ui`
- `nawex-api`
- `nawex-worker`

## GitOps Model

- GitHub Actions validates application, infrastructure, and GitOps payloads.
- Argo CD reconciles Kubernetes state from the repository.
- Kustomize overlays define `dev`, `staging`, and `prod` deployment variants.
- `gitops/argocd/root-application.yaml` provides a starter app-of-apps pattern.

## Demo Flow

1. Explain the hybrid mission platform architecture.
2. Show GitHub Actions quality, infra, GitOps handoff, FinOps, and SRE gates.
3. Walk through Terraform modules and Ansible Linux baseline.
4. Show Kubernetes base manifests and Argo CD environment overlays.
5. Show Argo CD application manifests and explain automated reconciliation.
6. Show observability, rightsizing output, and SLO risk output.

## Repository Layout

```text
nawex-hybrid-devops-platform/
├── architecture/
├── app/
├── infra/
├── k8s/
├── gitops/argocd/
├── .github/workflows/
├── observability/
├── finops-aiops/
├── scripts/
└── runbooks/
```

## Notes

- Replace the placeholder GitHub repository URL in `gitops/argocd/*.yaml` before using Argo CD.
- The starter overlays keep a shared namespace for simplicity; in a real multi-env deployment you would usually separate clusters or namespaces per environment.
