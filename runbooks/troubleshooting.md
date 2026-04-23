# Troubleshooting — All Layers

Layer-by-layer triage index for the NAWEX platform. Use this as the first
stop when you don't know where to look. Each section gives you the symptoms,
the three or four diagnostic commands worth running first, the common fixes,
and a pointer to the focused runbook if you need to go deeper.

The layers here mirror the architecture diagram in the top-level
[README](../README.md#how-the-platform-works) — source → CI → IaC → targets
→ GitOps → runtime → apps → observability → ops.

---

## Quick Triage Matrix

| Symptom                                         | First layer to check            | Jump to |
|-------------------------------------------------|---------------------------------|---------|
| PR merged but nothing changed in the cluster    | CI/CD, then GitOps              | [§ CI/CD](#2--cicd-pipeline) · [§ GitOps](#5--gitops-delivery-argo-cd) |
| `terraform apply` fails                         | Infrastructure as Code          | [§ IaC](#3--infrastructure-as-code-terraform--ansible) |
| Bare-metal OpenShift install hangs              | BMC / firmware preflight        | [§ Bare-metal BMC](#3c-bare-metal-bmc--firmware) · [openshift-operations.md](openshift-operations.md) |
| `ansible-playbook` fails on a host              | Linux baseline                  | [§ Linux baseline](#4--linux-baseline--host) |
| Argo CD app stuck `OutOfSync` or `Degraded`     | GitOps delivery                 | [§ GitOps](#5--gitops-delivery-argo-cd) |
| Pod crashlooping / not ready                    | Kubernetes runtime              | [§ K8s runtime](#6--kubernetes-runtime) · [k8s-troubleshooting.md](k8s-troubleshooting.md) |
| 5xx from the API / Web UI                       | Applications                    | [§ Applications](#7--applications) |
| Alerts missing from Slack                       | Observability + AlertManager    | [§ Observability](#8--observability--alerting) · [slack-alerting.md](slack-alerting.md) |
| Cost anomaly / budget burn                      | FinOps/AIOps                    | [§ FinOps](#9--finops--aiops) · [cost-optimization.md](cost-optimization.md) |
| VM-to-K8s migration stalled                     | Migration pipeline              | [§ Migration](#10--migration-pipeline) · [vm-to-k8s-migration.md](vm-to-k8s-migration.md) |
| Production needs to be reverted                 | Any layer — stop and read       | [rollback.md](rollback.md) |
| On-call page / Slack approve-or-deny            | Operations                      | [slack-alerting.md](slack-alerting.md) · [incident-response.md](incident-response.md) |

---

## 1 · Source & Git

**Where it lives.** The repo root — one source of truth for both SCMs
(GitHub and GitLab share the same six-stage gate).

### Symptoms

- Branch won't push — pre-commit or pre-push hook blocks the commit.
- CI/CD refuses to start because the webhook or remote is misconfigured.
- Local state diverged from remote; merge conflicts in `gitops/` or `k8s/overlays/`.

### Diagnose

```bash
git status
git remote -v
pre-commit run --all-files     # run the same hooks CI runs
```

### Common fixes

- **Pre-commit hook failure.** Fix the underlying lint — do not bypass with `--no-verify`. If a hook itself is broken, `pre-commit clean && pre-commit install`.
- **Missing remote.** `git remote add origin <url>` and push.
- **Conflict in `gitops/` or `k8s/overlays/`.** Resolve by hand; both files must remain valid YAML. After resolution, `kustomize build k8s/overlays/<env>/ >/dev/null` on each affected overlay to confirm the tree still renders.

---

## 2 · CI/CD Pipeline

**Where it lives.** GitHub Actions in [.github/workflows/](../.github/workflows/) or GitLab CI/CD in [.gitlab-ci.yml](../.gitlab-ci.yml). Both run the same six stages: lint → security → test → validate → build → deploy.

### Symptoms

- Pipeline red at a specific stage.
- Pipeline green but nothing deployed (deploy is `workflow_dispatch` / `when: manual` for prod — expected).
- Image built but Argo CD still shows the old SHA.

### Diagnose

| Stage fails | First thing to check |
|-------------|----------------------|
| **lint** (ruff, shellcheck, tf fmt, hadolint) | Run the same tool locally: `ruff check .`, `shellcheck scripts/*.sh`, `terraform fmt -recursive -check`, `hadolint app/*/Dockerfile`. |
| **security** (Trivy, tfsec, checkov) | CRITICAL/HIGH gate on images, IaC misconfig on Terraform. Reproduce: `trivy image <image>:<sha>`, `tfsec infra/terraform/envs/<env>`, `checkov -d infra/terraform`. |
| **test** (pytest) | `pytest -q` locally against the same requirements. Pin Python version to match CI. |
| **validate** (kubeconform, terraform validate/plan) | `kustomize build k8s/overlays/<env> \| kubeconform -strict -`; `cd infra/terraform/envs/<env> && terraform init -backend=false && terraform validate`. |
| **build** (docker buildx) | Rebuild locally with the same context: `docker buildx build -t test app/nawex-api`. Watch for cache poisoning — try `--no-cache`. |
| **deploy** | Manual gate on prod by design. If dev/staging didn't reconcile, it's a GitOps issue — see § GitOps. |

### Common fixes

- **Matrix job fails only on one image.** Dockerfile drift between workloads. Run `hadolint` on the failing Dockerfile.
- **`terraform plan` fails only on one env.** Missing cloud creds for that env in CI secrets (`AWS_*`, `ARM_*`). GitLab: *Settings → CI/CD → Variables*. GitHub: *repo → Settings → Secrets*.
- **Weekly FinOps job (schedule) doesn't run.** GitHub: check `finops-sre.yml` cron. GitLab: create a schedule with `RUN_FINOPS=1` (pipelines don't autoschedule from `.gitlab-ci.yml`).

---

## 3 · Infrastructure as Code (Terraform + Ansible)

### 3a · Terraform

**Where it lives.** [infra/terraform/](../infra/terraform/) — reusable modules + nine env compositions (dev, staging, prod, onprem, aws-eks, azure-aks, openshift-rosa, openshift-vsphere, openshift-baremetal).

#### Diagnose

```bash
cd infra/terraform/envs/<env>
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan | head -200
```

#### Common fixes

- **`Error: provider produced inconsistent final plan`.** Usually a drift between plan and apply on a cloud API. Re-plan with a fresh lockfile: `rm -f .terraform.lock.hcl && terraform init -upgrade`.
- **State lock held.** Someone else is running against the same backend. Wait, or if it's genuinely stale: `terraform force-unlock <lock-id>` (only with the team's sign-off).
- **Module change not picked up.** `terraform init -upgrade` to re-resolve the module source.

### 3b · Ansible (Linux baseline + kubeadm join)

**Where it lives.** [infra/ansible/](../infra/ansible/) — the four-role baseline (`system`, `security`, `observability`, `docker`), plus `baremetal-bmc` and the environment playbooks.

#### Diagnose

```bash
# Syntax + inventory sanity (no SSH required)
ansible-playbook infra/ansible/playbooks/linux-baseline.yml --syntax-check
ansible-inventory -i infra/ansible/inventories/onprem/hosts.yml --list

# Dry run against real hosts
ansible-playbook \
  -i infra/ansible/inventories/onprem/hosts.yml \
  infra/ansible/playbooks/linux-baseline.yml \
  --check --diff
```

#### Common fixes

- **`UNREACHABLE` on a host.** SSH key or user mismatch. Confirm from the control node: `ansible -i <inv> <host> -m ping`.
- **auditd fails to load rules.** The prior `-e 2` line made audit immutable — reboot required, then re-run. This is by design.
- **sshd validation fails mid-play.** The `lineinfile` validator caught a bad config before writing. Check the loop item that triggered it (the failing line in the task output).
- **Dynamic vSphere inventory returns nothing.** Confirm the `vmware_vm_inventory` plugin env vars (`VMWARE_HOST`, `VMWARE_USER`, `VMWARE_PASSWORD`) and `vmware.yml` filters.

### 3c · Bare-metal BMC / firmware

**Where it lives.** [infra/ansible/roles/baremetal-bmc/](../infra/ansible/roles/baremetal-bmc/), [infra/ansible/playbooks/baremetal-firmware-baseline.yml](../infra/ansible/playbooks/baremetal-firmware-baseline.yml).

#### Symptoms

- `openshift-install create cluster` fails with a Redfish / virtual-media error.
- BMC URL returns 401 or 404.

#### Diagnose

```bash
# Per-host BMC reachability from the control plane
curl -kI https://<bmc-host>/redfish/v1/
# Vendor-specific virtual-media endpoint
curl -ku <user>:<pass> https://<bmc-host>/redfish/v1/Managers/1/VirtualMedia
```

#### Common fixes

- **Stale firmware.** Update CIMC / iLO / iDRAC before retrying the install — firmware drift is the #1 cause of bare-metal install failure.
- **Wrong Redfish scheme.** Cisco → `redfish-virtualmedia://`, HPE → `ilo5-virtualmedia://`, Dell → `idrac-virtualmedia://`. Confirm the Terraform env emits the right per-vendor URL.
- **See also.** [openshift-operations.md](openshift-operations.md).

---

## 4 · Linux Baseline / Host

**Where it lives.** [infra/ansible/roles/{system,security,observability,docker}/](../infra/ansible/roles/), fallback scripts in [infra/ansible/scripts/](../infra/ansible/scripts/), evidence in [infra/ansible/compliance/](../infra/ansible/compliance/).

### Symptoms

- CIS checklist row fails.
- `node_exporter` not scraped by Prometheus.
- Docker daemon refuses to start after baseline applied.

### Diagnose

```bash
# On the host
systemctl is-active node_exporter sshd auditd chrony docker
sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|maxauthtries)'
auditctl -l | head -20
sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space
```

### Common fixes

- **auditd rules out of date on one host.** Re-run the `security` role with `--tags security`. Reboot is required to reset the `-e 2` immutability.
- **node_exporter unit failing.** Usually a missing binary after an upgrade. Re-run `infra/ansible/scripts/install_monitoring.sh` or the `observability` role.
- **Docker `live-restore` refuses.** Incompatible with swarm mode — don't run swarm on NAWEX hosts.
- **Drift detection.** Re-running the playbook is the canonical drift check. Any `changed` task = drift.
- **See also.** [infra/ansible/docs/baseline-explained.md](../infra/ansible/docs/baseline-explained.md), [infra/ansible/compliance/cis-checklist.md](../infra/ansible/compliance/cis-checklist.md).

---

## 5 · GitOps Delivery (Argo CD)

**Where it lives.** [gitops/root-application.yaml](../gitops/root-application.yaml), [gitops/apps/](../gitops/apps/), [gitops/project.yaml](../gitops/project.yaml). Local harness: [gitops/local/](../gitops/local/).

### Symptoms

- App stuck `OutOfSync` forever.
- App `Degraded` with a clear resource-level error.
- Root app synced but a child app is missing.

### Diagnose

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application <app-name>
argocd app get <app-name>
argocd app history <app-name>
argocd app diff <app-name>
```

### Common fixes

- **`OutOfSync` with no diff.** Resource is managed by two controllers. Check `argocd app get` for `conflicts`; remove the duplicate owner.
- **`ComparisonError: Unknown.` on a CRD.** Ensure the CRD itself is synced before the CR. Use sync waves: annotate the CRD with `argocd.argoproj.io/sync-wave: "-1"`.
- **Prod didn't auto-heal.** By design — prod's Argo CD application runs with `automated: false` for `prune` and `selfHeal`. Sync manually.
- **Repo URL placeholder.** Replace the placeholder GitHub URL in `gitops/` files before using Argo CD against the real remote.
- **AppProject RBAC denied.** The project scopes resource kinds (no wildcards). Add the kind/role to [gitops/project.yaml](../gitops/project.yaml) if the need is legitimate.

---

## 6 · Kubernetes Runtime

**Where it lives.** [k8s/base/](../k8s/base/) and seven overlays in [k8s/overlays/](../k8s/overlays/).

### Symptoms

- Pod `CrashLoopBackOff` / `ImagePullBackOff` / `Pending`.
- Service reachable inside the cluster but not from outside.
- Namespace rejects pods with PSA violations.

### Diagnose

```bash
kubectl -n <ns> get pods -o wide
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --previous --tail=200
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -30
kubectl -n <ns> get networkpolicies,pdb
```

### Common fixes

- **`ImagePullBackOff`.** Wrong tag or missing imagePullSecret. For GitLab CI, the image lives at `$CI_REGISTRY_IMAGE/<image>:<short-sha>` — confirm the secret in-cluster matches the registry scheme.
- **`Pending` with no node matching.** Topology spread constraints + PodDisruptionBudget can block scheduling on a thin cluster. `kubectl describe pod` shows the scheduler reason.
- **PSA `violates PodSecurity "restricted"`.** The workload is missing `runAsNonRoot`, `seccompProfile: RuntimeDefault`, dropped capabilities, or `readOnlyRootFilesystem`. Fix the spec — do not downgrade the namespace.
- **OpenShift-only: SCC denied.** The overlay's SCC RoleBinding is missing. See [k8s/overlays/openshift/](../k8s/overlays/openshift/) and [openshift-operations.md](openshift-operations.md).
- **See also.** [k8s-troubleshooting.md](k8s-troubleshooting.md).

---

## 7 · Applications

**Where it lives.** [app/nawex-web-ui/](../app/nawex-web-ui/), [app/nawex-api/](../app/nawex-api/), [app/nawex-worker/](../app/nawex-worker/).

### Symptoms

- API 5xx; Web UI blank or CSP violations in browser console.
- Worker consuming but not acking; queue backlog.

### Diagnose

```bash
kubectl -n <ns> port-forward svc/nawex-api 8081:80
curl -fsS localhost:8081/healthz
curl -fsS localhost:8081/readyz
# Browser console for Web UI CSP; check Network tab for blocked resources
```

### Common fixes

- **API `readyz` fails, `healthz` passes.** A dependency isn't ready (DB, cache, downstream). Check the readiness probe target — it's intentionally stricter than the liveness probe.
- **CSP violation in Web UI.** The strict CSP is deliberate. Add the required source to the policy in the Web UI's HTML/headers rather than weakening it to `unsafe-inline`.
- **Worker queue backlog.** Check the deployment's replica count and HPA. If HPA is missing, the deployment won't scale under load.
- **Non-root surprises.** Containers run with `readOnlyRootFilesystem: true`; writable scratch goes to an `emptyDir` volume. Missing mount = `EROFS` at first write.

---

## 8 · Observability + Alerting

**Where it lives.** [observability/](../observability/) — Prometheus rules in [alerts/slo-alerts.yml](../observability/alerts/slo-alerts.yml), AlertManager in [alertmanager/alertmanager.yml](../observability/alertmanager/alertmanager.yml), Slack template in [alertmanager/templates/slack.tmpl](../observability/alertmanager/templates/slack.tmpl), receiver [scripts/alert_webhook.py](../scripts/alert_webhook.py).

### Symptoms

- Host missing from Grafana.
- Alert firing in Prometheus but no Slack ping.
- Slack ping arrives but `incident_respond.sh approve` says `unknown action`.

### Diagnose

```bash
# On the host
curl -fsS localhost:9100/metrics | head
# In the cluster
kubectl -n monitoring logs deploy/prometheus-server --tail=100
kubectl -n monitoring logs deploy/alertmanager --tail=100
amtool check-config observability/alertmanager/alertmanager.yml
promtool check rules observability/alerts/slo-alerts.yml
```

### Common fixes

- **Host missing from Grafana.** node_exporter unit not running (see § Linux baseline) or Prometheus scrape config missing the host. Update [observability/prometheus/](../observability/prometheus/) and reload.
- **No Slack ping.** `SLACK_WEBHOOK_URL` unset, revoked, or AlertManager has no matching route. `amtool config routes test` against a sample alert.
- **`approve` fails: `unknown action`.** The rule's `remediation_action` label doesn't match a script in [scripts/remediations/](../scripts/remediations/). They must be 1:1.
- **See also.** [slack-alerting.md](slack-alerting.md).

---

## 9 · FinOps / AIOps

**Where it lives.** [finops-aiops/](../finops-aiops/) — Python utilities for anomaly detection, rightsizing, budget burn, SLO risk. Host-level drift from [infra/ansible/scripts/cost_check.sh](../infra/ansible/scripts/cost_check.sh).

### Symptoms

- Weekly FinOps report missing.
- Rightsizing recommendation looks wrong (spike day dominated the window).
- `cost_check.sh` exits 1 but the reason is unclear.

### Diagnose

```bash
# Run the check the same way the scheduled pipeline does
python -m finops_aiops.rightsizing --env prod --window 14d
python -m finops_aiops.budget_burn --month $(date +%Y-%m)
# On a host
infra/ansible/scripts/cost_check.sh
```

### Common fixes

- **Weekly report missing.** Check the schedule (`finops-sre.yml` in GitHub, pipeline schedule with `RUN_FINOPS=1` in GitLab). Artifact retention / Slack webhook may also be the culprit.
- **Rightsizing dominated by a spike.** Increase window (`--window 28d`) or exclude the spike day explicitly — documented in each utility's `--help`.
- **`cost_check.sh` exits 1.** Read its stdout — every finding includes the breached threshold and the fix command (e.g. `docker image prune -f`).
- **See also.** [cost-optimization.md](cost-optimization.md).

---

## 10 · Migration Pipeline

**Where it lives.** [migration/assess/](../migration/assess/) → [migration/containerize/](../migration/containerize/) → GitOps deploy to EKS / AKS / OpenShift.

### Symptoms

- `assess` produces an empty or incomplete WorkloadProfile.
- `containerize` generates a Dockerfile that fails to build.
- Migrated workload runs but can't reach on-prem dependencies.

### Diagnose

```bash
python -m migration.assess --vcenter <host> --vm <vm-name>
python -m migration.containerize --profile migration/samples/<profile>.yaml --out /tmp/out
docker build /tmp/out
```

### Common fixes

- **Empty WorkloadProfile.** vCenter credentials or filter is wrong. Confirm the same env vars the dynamic vSphere inventory uses.
- **Dockerfile build fails.** Base image in the WorkloadProfile is stale. Upgrade `base_image` and re-run `containerize`.
- **Runtime DNS / connectivity fail.** Migrated workload reaches for on-prem DNS; the target cluster has no route. Either publish the dependency inside the target cluster or open the minimum network policy + route — don't flatten NetworkPolicies.
- **See also.** [vm-to-k8s-migration.md](vm-to-k8s-migration.md).

---

## When you don't know where to start

1. **Does Slack say anything?** If yes, follow [slack-alerting.md](slack-alerting.md) — the approve/deny hint + runbook URL is the fastest path.
2. **Did a deploy correlate?** If yes, [rollback.md](rollback.md). Revert in Git first, investigate second.
3. **Still stuck?** Work downward from the diagram: source → CI → IaC → targets → GitOps → runtime → apps. The first layer that looks wrong is almost always the real cause.
