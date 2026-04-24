# Contributing to NAWEX Platform

Thanks for your interest in contributing. This repo is a reference implementation
for regulated, mission-critical hybrid infrastructure. Changes are held to the
same quality bar as production infra.

## Development setup

```bash
# Install the pre-commit framework and activate the project hooks.
pip install pre-commit && pre-commit install

# Copy the environment template and fill in local values.
cp .env.example .env
```

Local validation before pushing:

```bash
pre-commit run --all-files     # formatters, linters, secret scan
terraform fmt -recursive infra/terraform
ansible-lint infra/ansible
```

## Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new capability
- `fix:` — bug fix
- `docs:` — documentation only
- `chore:` — tooling, dependencies, non-functional cleanup
- `refactor:` — structural change with no behavior change
- `test:` — adding or fixing tests

Scope the commit by domain when it helps: `feat(terraform): add Azure tagging module`.

## Pull request process

1. Branch from `main` (`feat/<short-name>`, `fix/<short-name>`).
2. Run pre-commit hooks locally — CI will reject unformatted code.
3. Ensure CI passes all six quality gates (tfsec, checkov, Hadolint, Trivy, kubeconform, PSA).
4. Reference the domain in the PR title, e.g. `[terraform] Add Azure tagging module`.
5. Fill out the PR template — especially the **blast radius** and **rollback** sections
   for any infrastructure change.
6. At least one CODEOWNER approval is required before merge.

## Domain owners

| Domain | Path | Maintainer |
|---|---|---|
| Terraform IaC | [infra/terraform/](infra/terraform/) | @Here2ServeU |
| Ansible | [infra/ansible/](infra/ansible/) | @Here2ServeU |
| Kubernetes manifests | [k8s/](k8s/) | @Here2ServeU |
| GitOps (Argo CD) | [gitops/](gitops/) | @Here2ServeU |
| Observability | [observability/](observability/) | @Here2ServeU |
| FinOps / AIOps | [finops-aiops/](finops-aiops/) | @Here2ServeU |
| VM-to-K8s migration | [migration/](migration/) | @Here2ServeU |
| Operator tooling | [scripts/](scripts/) | @Here2ServeU |

## Security

Never commit secrets. `.env`, kubeconfigs, and credentials are ignored by default —
if you are unsure, run `git diff --cached` before committing. Report vulnerabilities
privately per [SECURITY.md](SECURITY.md).
