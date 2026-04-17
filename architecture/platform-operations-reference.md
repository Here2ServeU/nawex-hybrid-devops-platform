# NAWEX Platform Operations Reference

A consolidated operational reference for the NAWEX hybrid DevOps platform. Organized by discipline: Terraform IaC, Ansible + CI/CD, Kubernetes + GitOps, Observability + FinOps, and VM-to-Kubernetes migration.

---

## 1. Terraform IaC

### Repository layout

```
infra/terraform/
  modules/
    nawex-vsphere/     # reusable vSphere VM module
    nawex-eks/         # AWS EKS cluster module
    nawex-aks/         # Azure AKS cluster module
  envs/
    onprem/            # calls nawex-vsphere module
    dev/ staging/ prod/
    aws-eks/           # migration target
    azure-aks/         # migration target
    openshift-rosa/      # managed OpenShift on AWS
    openshift-vsphere/   # self-managed IPI on vSphere
    openshift-baremetal/ # self-managed IPI on bare metal (Cisco/HPE/Dell)
```

### Core concepts

The platform uses reusable Terraform modules that each environment composition calls — the same pattern applies across cloud and on-prem. Environments are separate directories under `envs/` — thin compositions that declare variables and call modules, which prevents drift by design. The vSphere provider handles on-prem the same way the AWS provider handles cloud — they are peer execution environments. CI runs `tfsec` and `checkov` on every Terraform change as hard security gates before anything is applied. FinOps is implemented through resource tagging in modules and Python budget-burn prediction in `finops-aiops/python/`.

### FAQ

**How is infrastructure as code managed across on-premises and cloud?**

Terraform is the single IaC layer across all environments — vSphere on-prem, AWS EKS, and Azure AKS. Reusable modules (`nawex-vsphere`, `nawex-eks`, `nawex-aks`) are called by each environment composition. Whether provisioning a vSphere VM or an EKS node group, the pattern is the same: declare the environment in `envs/`, call the module, set env-specific variables. On-prem and cloud are peer execution environments.

Ref: [infra/terraform/envs/](../infra/terraform/envs/), [infra/terraform/modules/](../infra/terraform/modules/)

**How are security and cost guardrails enforced in Terraform?**

Two layers: static analysis in CI, and FinOps automation at runtime. Every Terraform PR runs `tfsec` and `checkov` — these block misconfigured security groups, unencrypted storage, or public exposure before apply. For cost, resource tagging is embedded in the modules so every resource carries environment, team, and cost-center tags. The `finops-aiops/python/` utilities handle budget-burn prediction and rightsizing analysis — cost drift is caught before the invoice.

Ref: [.github/workflows/](../.github/workflows/), [finops-aiops/python/](../finops-aiops/python/)

**What is the module strategy and how is environment drift prevented?**

One module per platform type, many environments calling it. The `nawex-vsphere` module encapsulates all vSphere-specific resource logic. Each environment in `envs/onprem` is a thin composition that sets variables. There is no per-environment fork of module logic — a fix to the module propagates to all callers. CI additionally runs `terraform fmt` and `terraform validate` on every commit, and the repo ships a `.pre-commit-config.yaml` that enforces formatting before a commit is pushed.

Ref: [infra/terraform/modules/](../infra/terraform/modules/), [.pre-commit-config.yaml](../.pre-commit-config.yaml)

**How is OpenShift handled in IaC and how does it differ from vanilla Kubernetes?**

The platform supports three OpenShift deployment models via Terraform: `openshift-rosa` (managed Red Hat OpenShift on AWS), `openshift-vsphere` (self-managed IPI on vSphere), and `openshift-baremetal` (self-managed IPI on physical servers). Key operational differences from vanilla Kubernetes: OpenShift uses Security Context Constraints (SCC) instead of Pod Security Admission, it uses Routes instead of Ingress objects, and all workloads must run non-root. The OpenShift K8s overlay adds a Route manifest, an SCC RoleBinding for non-root pods, and PSA-restricted namespace labels.

Ref: [infra/terraform/envs/openshift-rosa/](../infra/terraform/envs/openshift-rosa/), [infra/terraform/envs/openshift-vsphere/](../infra/terraform/envs/openshift-vsphere/), [infra/terraform/envs/openshift-baremetal/](../infra/terraform/envs/openshift-baremetal/), [k8s/overlays/openshift/](../k8s/overlays/openshift/)

**How is OpenShift installed on bare-metal servers (Cisco, HPE, Dell)?**

The `openshift-baremetal` environment uses OpenShift's `platform: baremetal` IPI mode. Each physical host is declared with its vendor, its Baseboard Management Controller address (iDRAC for Dell PowerEdge, iLO for HPE ProLiant, CIMC for Cisco UCS), and the MAC address of the NIC on the provisioning network. Terraform translates each `vendor` field into the correct Redfish virtual-media URL scheme:

- Dell iDRAC 9+ → `idrac-virtualmedia://<bmc>/redfish/v1/Systems/System.Embedded.1`
- HPE iLO 5+ → `ilo5-virtualmedia://<bmc>/redfish/v1/Systems/1`
- Cisco UCS CIMC → `redfish-virtualmedia://<bmc>/redfish/v1/Systems/1`

`openshift-install` then drives the install over each BMC: it mounts the CoreOS ISO via virtual media, power-cycles the host, and installs onto the disk matched by `rootDeviceHints`. Mixed-vendor clusters are supported. Before install, the `baremetal-firmware-baseline.yml` Ansible playbook probes each BMC over Redfish to catch firmware drift — the most common cause of baremetal install failure.

Ref: [infra/terraform/envs/openshift-baremetal/](../infra/terraform/envs/openshift-baremetal/), [infra/ansible/inventories/baremetal/](../infra/ansible/inventories/baremetal/), [infra/ansible/playbooks/baremetal-firmware-baseline.yml](../infra/ansible/playbooks/baremetal-firmware-baseline.yml)

---

## 2. Ansible + CI/CD

### Repository layout

```
infra/ansible/
  inventories/
    onprem/
      hosts.yml        # static inventory for vSphere VMs
      vmware.yml       # dynamic inventory plugin (vCenter API)
    dev/ staging/ prod/
  roles/               # shared reusable roles
  playbooks/
    vsphere-join-cluster.yml  # kubeadm join automation
    linux-baseline.yml        # hardening, packages, sysctl
```

### CI/CD pipeline stages

1. **Lint & format** — `ruff check`/`ruff format` on Python, `shellcheck` on shell scripts, `terraform fmt`
2. **Security scan** — `tfsec` and `checkov` on Terraform; `Hadolint` on every Dockerfile
3. **Image scan** — `Trivy` scans every built container image. CRITICAL and HIGH findings are a hard gate
4. **K8s validation** — `kubeconform` validates every Kustomize overlay against the Kubernetes API schema
5. **Unit tests** — `pytest -q` runs the Python test suite for FinOps/AIOps utilities
6. **Deploy / GitOps sync** — Argo CD picks up validated manifests from Git. CI only validates, GitOps controls deployment

### FAQ

**How is Ansible used in a hybrid environment with both static and dynamic inventory?**

The on-prem vSphere environment uses both. For known, stable infrastructure, `hosts.yml` is the static inventory — explicit control when VM IPs are fixed. For the dynamic side, `vmware.yml` uses the dynamic inventory plugin to query the vCenter API and pull the current VM list at runtime — critical when VMs are being created by Terraform. Both inventory sources feed into the same playbooks: `linux-baseline.yml` runs against all hosts regardless of how they were discovered, applying the same hardening and package baseline everywhere.

Ref: [infra/ansible/inventories/onprem/hosts.yml](../infra/ansible/inventories/onprem/hosts.yml), [infra/ansible/inventories/onprem/vmware.yml](../infra/ansible/inventories/onprem/vmware.yml)

**What are the CI/CD quality gates?**

Six progressive gates. Code quality first: `ruff` for Python, `shellcheck` for shell. Static security: `tfsec` and `checkov` on Terraform, `Hadolint` on Dockerfiles. Container images are built and immediately scanned with `Trivy` — CRITICAL and HIGH vulnerabilities fail the build. `kubeconform` validates every Kustomize overlay against the Kubernetes API schema so a misconfigured manifest cannot get committed. Finally, `pytest` covers the Python FinOps utilities. Only after all six gates pass does Argo CD sync the change.

Ref: [.github/workflows/](../.github/workflows/), [pyproject.toml](../pyproject.toml), [.pre-commit-config.yaml](../.pre-commit-config.yaml)

**How are new nodes automatically joined to a Kubernetes cluster?**

For on-prem vSphere nodes: `vsphere-join-cluster.yml`. Terraform provisions the VM, Ansible runs the Linux baseline, and the kubeadm-join playbook retrieves the join token from the control plane and executes `kubeadm join` on the new node. No manual SSH required. For cloud clusters like EKS, node joining is handled by the managed control plane — the Terraform module configures the node group and AWS handles bootstrapping via the EKS AMI.

Ref: [infra/ansible/playbooks/vsphere-join-cluster.yml](../infra/ansible/playbooks/vsphere-join-cluster.yml)

> **Note on CI platform portability:** This repo uses GitHub Actions, but the pipeline model (stages, jobs, runners, artifacts, caching) maps 1:1 onto GitLab CI or any comparable system.

---

## 3. Kubernetes + GitOps

### Repository layout

```
k8s/
  base/               # shared manifests: Deployment, Service, NetworkPolicy, PDB
  overlays/
    dev/ staging/ prod/
    onprem/
    aws-eks/
    azure-aks/
    openshift/        # Route + SCC RoleBinding + PSA labels

gitops/
  root-application.yaml   # Argo CD app-of-apps root
  project.yaml            # AppProject with scoped RBAC roles
  apps/
    onprem-platform.yaml
    dev-platform.yaml
  local/                  # kind cluster test harness
```

### Container security baseline

Every container runs with:

- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities: drop: [ALL]`
- seccomp profile `RuntimeDefault`
- `automountServiceAccountToken: false` on service accounts that don't call the Kubernetes API

Namespaces are labeled for Pod Security Admission `restricted` enforcement — Kubernetes rejects non-compliant pods at admission. NetworkPolicy starts with a default-deny stance.

### FAQ

**How is the Kubernetes overlay structure organized across multiple environments?**

Kustomize base-plus-overlay pattern. `k8s/base/` contains shared manifests — Deployments, Services, ConfigMaps, NetworkPolicy, PodDisruptionBudget. Each environment in `k8s/overlays/` is a thin Kustomize layer that patches only what differs: replica count, resource limits, image tags, or platform-specific additions. The OpenShift overlay adds a Route manifest and SCC RoleBinding that base does not have. The prod overlay removes automated sync. All seven targets share the same base — fix a security issue in base and it propagates everywhere.

Ref: [k8s/overlays/](../k8s/overlays/), [k8s/base/](../k8s/base/)

**How does the Argo CD GitOps flow work? What is the app-of-apps pattern?**

Argo CD starts from `gitops/root-application.yaml`, a single Argo Application pointing to `gitops/apps/`. Each file in that directory is itself an Argo Application pointing to a specific environment overlay. The root app deploys the child apps; each child app deploys an environment. Adding a new environment means adding one file to `gitops/apps/` and Argo CD picks it up automatically. The `project.yaml` scopes RBAC so Argo CD can only deploy the specific resource kinds this platform uses — no wildcard cluster-admin access. Prod runs with `automated: false` for prune and selfHeal — prod changes need an explicit human sync. Dev and staging are fully automated.

Ref: [gitops/root-application.yaml](../gitops/root-application.yaml), [gitops/project.yaml](../gitops/project.yaml), [gitops/apps/](../gitops/apps/)

**How are containers hardened in Kubernetes?**

See the baseline above. Every container runs with `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities: drop: [ALL]`, and seccomp profile `RuntimeDefault`. Namespaces are labeled for Pod Security Admission `restricted` enforcement — Kubernetes rejects any non-compliant pod at admission, not just at runtime. The API service account has `automountServiceAccountToken: false` where it doesn't need Kubernetes API access. NetworkPolicy starts with default-deny and adds only minimum ingress and DNS egress.

Ref: [k8s/base/](../k8s/base/), [k8s/overlays/](../k8s/overlays/)

---

## 4. Observability + FinOps

### Repository layout

```
observability/
  alerts/slo-alerts.yml          # multi-burn-rate SLO alert rules
  alertmanager/
    alertmanager.yml             # routes alerts → Slack via webhook
    templates/slack.tmpl         # Go template: summary + runbook + commands
  grafana/                       # dashboard JSON

finops-aiops/python/
  anomaly_detection.py           # statistical cost/metric anomaly
  rightsizing.py                 # CPU/mem usage → right-size recommendations
  budget_burn.py                 # burn rate prediction and forecast
  slo_risk.py                    # error budget remaining analysis

scripts/
  alert_webhook.py               # receives alerts → .incidents/
  incident_respond.sh            # list/show/approve/deny incidents
  remediations/                  # per-alert remediation scripts
```

### Alert → incident → remediation flow

```
1. Prometheus fires alert (SLO burn, crashloop, budget drift)
   Prometheus rules → alertmanager.yml → Slack channel

2. Alert message includes approve/deny commands
   remediation_action label in slo-alerts.yml maps to a script

3. alert_webhook.py persists to .incidents/<fingerprint>.json

4. On-call engineer workflow:
   ./scripts/incident_respond.sh show <id>     # DRY_RUN preview
   ./scripts/incident_respond.sh approve <id>  # runs remediations/<action>.sh
   ./scripts/incident_respond.sh deny <id>     # ack without action

5. Audit trail posts back to Slack
```

### FAQ

**How are SLOs implemented and what are multi-burn-rate alerts?**

SLIs and SLOs are defined in [architecture/sli-slo-model.md](./sli-slo-model.md) — availability and latency targets per service. In `observability/alerts/slo-alerts.yml`, multi-burn-rate alerts are implemented. A fast burn at 14x over 1 hour pages immediately — the error budget is draining fast. A slow burn at 2x over 6 hours sends a warning. This is the Google SRE approach: severity is proportional to how fast you're consuming budget, not just whether an alert fires. Standard threshold alerts miss this — you can have a technically passing error rate while still consuming your monthly budget too quickly.

Ref: [observability/alerts/slo-alerts.yml](../observability/alerts/slo-alerts.yml), [architecture/sli-slo-model.md](./sli-slo-model.md)

**How is FinOps applied in practice?**

Three concrete mechanisms:

1. **Cost tagging at provisioning** — Terraform modules tag every resource with environment, team, and cost center.
2. **Rightsizing automation** — `rightsizing.py` analyzes actual CPU and memory utilization versus requested limits and generates recommendations, catching over-provisioned workloads automatically.
3. **Budget burn prediction** — `budget_burn.py` tracks spend rate and forecasts month-end costs. If burn rate is trending toward a budget breach, it fires early.

These utilities feed into the same alerting pipeline as infrastructure alerts — cost is a first-class operational signal.

Ref: [finops-aiops/python/](../finops-aiops/python/), Terraform modules

**Walk through an on-call incident response scenario.**

Scenario: a pod enters a crashloop. Prometheus detects it via kube-state-metrics and fires an alert defined in `slo-alerts.yml`. AlertManager routes it through `alertmanager.yml` and renders a Slack message from the `slack.tmpl` Go template — the message includes the summary, a runbook link, and copy-ready approve/deny commands. Simultaneously, `alert_webhook.py` persists the alert to `.incidents/<fingerprint>.json`. The on-call engineer runs `incident_respond.sh show <id>` which previews the exact remediation in dry-run mode. They then run `approve` and the system executes `remediations/restart-crashloop.sh` automatically. The audit trail posts back to Slack. The whole flow is reproducible, auditable, and does not require ad hoc kubectl access at 2am.

Ref: [scripts/alert_webhook.py](../scripts/alert_webhook.py), [scripts/incident_respond.sh](../scripts/incident_respond.sh), [scripts/remediations/](../scripts/remediations/), [runbooks/slack-alerting.md](../runbooks/slack-alerting.md)

---

## 5. VM-to-Kubernetes Migration

### Repository layout

```
migration/
  assess/        # Step 1: inventory vCenter VMs → WorkloadProfile stubs
  containerize/  # Step 2: WorkloadProfile → Dockerfile + K8s manifest
  samples/       # example WorkloadProfile YAML files
```

### Flow

1. **Assess** — The assess tooling queries vCenter, inventories VMs, and generates WorkloadProfile stubs — structured YAML describing each workload's OS, ports, env vars, and storage needs.
2. **Containerize** — WorkloadProfile → Dockerfile and Kubernetes manifest. The tool generates a container build spec and a K8s Deployment, Service, and PVC from the profile. No manual Dockerfile writing.
3. **Deploy via GitOps** — Generated manifests drop into the GitOps repo and Argo CD deploys them to EKS, AKS, or OpenShift — consistent delivery regardless of migration destination.
4. **Runbook** — [runbooks/vm-to-k8s-migration.md](../runbooks/vm-to-k8s-migration.md) is the operational procedure: assessment checklist, containerization steps, validation gates, rollback path.

---

## 6. Cross-Cutting Topics

### How consistency is maintained across on-premises and cloud

Five mechanisms:

1. Shared Terraform modules with the same interface whether calling into vSphere or AWS.
2. Common Ansible roles — the Linux baseline runs on both on-prem VMs and cloud instances.
3. Unified Kustomize overlays — `onprem` is just another overlay target with the same base.
4. A single GitOps control plane — Argo CD manages both on-prem and cloud apps from the same root application.
5. Shared observability — the same Prometheus rules and AlertManager config apply to all environments.

Mental model: cloud and on-prem are peer execution environments. They differ in provider and some operational details, but the engineering practices are identical.

### Automation wins that reduced manual ops

- **Node provisioning + cluster join** was previously a manual process: Terraform created the VM, then someone had to SSH in, run kubeadm, copy tokens. Now Terraform provisions the VM and Ansible's `vsphere-join-cluster.yml` automatically retrieves the join token and runs `kubeadm join`. Zero manual steps from VM creation to production-ready Kubernetes node.
- **Incident response** previously required on-call engineers to have kubectl access and know the right remediation command. Replaced with the `incident_respond.sh` workflow — alerts are persisted and engineers approve a pre-defined remediation through a dry-run preview. Cognitive load dropped significantly.

---

## 7. Capability Matrix

| Capability | Evidence |
|---|---|
| Terraform IaC | [infra/terraform/](../infra/terraform/) — 3 modules, 8 environments |
| Ansible | [infra/ansible/](../infra/ansible/) — dynamic vSphere inventory + kubeadm-join |
| Containers + Kubernetes | 7 overlays, security hardened, GitOps |
| CI/CD pipelines | [.github/workflows/](../.github/workflows/) — 6-stage quality gate |
| FinOps | [finops-aiops/python/](../finops-aiops/python/) — 4 Python utilities |
| GitOps | Argo CD app-of-apps, 7 targets |
| Linux systems | Ansible linux-baseline, all infra Linux-based |
| Scripting (Python/Bash) | [scripts/](../scripts/) + [finops-aiops/](../finops-aiops/) |
