# NAWEX Hybrid Platform Diagram

```text
GitHub -> GitHub Actions -> Terraform + Ansible -> Argo CD -> Kubernetes -> Observability -> FinOps + AIOps
```

## Notes

- Terraform handles environment delivery and tagging standards.
- Ansible handles Linux baselines and node preparation.
- GitHub Actions validates the delivery payload and GitOps configuration.
- Argo CD reconciles desired Kubernetes state from Git.
- FinOps and SRE checks are part of the platform, not bolt-ons.
