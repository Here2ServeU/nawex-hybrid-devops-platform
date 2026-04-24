# Security Policy

## Supported Versions

The `main` branch is the only actively maintained version of the NAWEX platform.
Security fixes are applied to `main` and then rolled forward into the next tagged release.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report suspected vulnerabilities privately to:

- Email: [info@transformed2succeed.com](mailto:info@transformed2succeed.com)

Include in your report:

- A description of the issue and its impact.
- Steps to reproduce (minimum viable reproduction is ideal).
- The affected component (Terraform module, Ansible role, K8s manifest, GitOps app, pipeline, etc.).
- Any known mitigations or workarounds.

You can expect an initial acknowledgement within **three business days** and a
triage decision within **ten business days**.

## Security Posture

This platform implements **defense-in-depth across five layers**:

1. **CI scanning** — tfsec, checkov, Hadolint, Trivy run as mandatory pipeline gates (not audits).
2. **Kubernetes admission** — Pod Security Admission in `restricted` mode on all namespaces.
3. **Container runtime hardening** — non-root UIDs, read-only root filesystems, dropped capabilities.
4. **GitOps RBAC scoping** — Argo CD projects constrain what each environment can deploy.
5. **Default-deny NetworkPolicy** — baseline deny-all, explicit allow per workload.

Security evidence lives in-repo under
[infra/ansible/compliance/](infra/ansible/compliance/) (CIS posture)
and is continuously verified by the [CI pipeline](.github/workflows/ci.yml).

## Disclosure

We follow a coordinated disclosure model. We will work with reporters on an
appropriate disclosure timeline — typically 90 days from initial report, shorter
for actively exploited issues, longer for issues requiring upstream coordination.
