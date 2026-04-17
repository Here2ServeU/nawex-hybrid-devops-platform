# NAWEX Hybrid DevOps Platform — Learning Guide

A guided walkthrough of the NAWEX hybrid DevOps platform, written so that
readers from any background — engineers, managers, students, or curious
non-technical readers — can understand what the platform does, how it is
built, and why each design decision was made.

This document is organized into five learning modules. Each module covers
one major capability of the platform, walks through the relevant code in
the repository, and ends with a set of common questions and answers to
reinforce understanding.

---

## How to read this guide

- **If you are non-technical:** Read the "Plain-language summary" at the
  start of each module. Skip the code paths and the deep Q&A on first
  reading. You will still come away with a clear mental model of the
  platform.
- **If you are technical:** Read each module in order. Open the referenced
  files in the repository as you go. The Q&A sections are designed for
  self-study and team training.
- **If you are using this for training or onboarding:** Each module has a
  checklist at the end. Treat the modules as self-contained learning units
  that can be completed in any order.

---

## Glossary of common terms

Before diving in, here are short definitions of terms used throughout the
guide.

- **IaC (Infrastructure as Code):** Defining servers, networks, and other
  infrastructure in text files instead of clicking through a web console.
  The text files live in version control, so every change is reviewable.
- **Terraform:** A widely used IaC tool. NAWEX uses it for both cloud and
  on-premises infrastructure.
- **Ansible:** A configuration management tool. It logs into servers and
  runs scripted setup steps in a repeatable way.
- **Container:** A lightweight, portable package that bundles an
  application together with everything it needs to run.
- **Kubernetes:** A system that runs and manages containers across many
  servers. Often abbreviated as "K8s".
- **OpenShift:** Red Hat's enterprise distribution of Kubernetes with
  additional security and developer tooling.
- **GitOps:** An operating model where the desired state of the system
  lives in a Git repository and an automated controller keeps the running
  system in sync with what Git says.
- **Argo CD:** The GitOps controller used in NAWEX.
- **CI/CD (Continuous Integration / Continuous Delivery):** Automated
  pipelines that test and validate code on every change.
- **SLO (Service Level Objective):** A measurable reliability target, for
  example "99.9% of requests succeed within 200 ms".
- **FinOps:** The practice of treating cloud cost as a first-class
  engineering concern, with measurement, attribution, and forecasting.
- **AIOps:** Using statistical or machine-learning techniques to detect
  anomalies and surface actionable insights from operational data.

---

## Module 1 — Terraform and Infrastructure as Code

### Plain-language summary

Imagine you need to set up identical computer environments in two
different places — one in your own data center, one in a cloud provider
like Amazon Web Services. Doing this by hand would be slow and error-prone.
Terraform lets you describe the environment in text files, and then it
builds the environment for you, the same way every time. NAWEX uses one
common pattern across both on-premises (vSphere) and cloud (AWS, Azure)
environments, so the same skills apply everywhere.

### Repository layout

```
infra/terraform/
  modules/
    nawex-vsphere/     # reusable building block for on-prem VMs
    nawex-eks/         # reusable building block for AWS Kubernetes
    nawex-aks/         # reusable building block for Azure Kubernetes
  envs/
    onprem/            # uses the nawex-vsphere module
    dev/ staging/ prod/
    aws-eks/           # cloud target
    azure-aks/         # cloud target
    openshift-rosa/    # managed OpenShift on AWS
    openshift-vsphere/ # self-managed OpenShift on vSphere
```

### Core concepts

The platform uses **reusable Terraform modules**. A module is a packaged
unit of infrastructure logic. Each environment under `envs/` is a thin
composition that declares variables and calls the module. This means a
fix in the module automatically benefits every environment that uses it,
and there is no copy-paste drift between environments.

The **vSphere provider** handles on-premises infrastructure the same way
the AWS and Azure providers handle cloud infrastructure. From the
operator's perspective, on-premises and cloud are simply different
execution backends behind the same workflow.

CI runs `tfsec` and `checkov` on every Terraform change. These tools
catch insecure configurations — public storage buckets, unencrypted
volumes, overly permissive firewall rules — *before* the change is
applied. FinOps is built in through resource tagging in modules and
through Python budget-burn prediction utilities under `finops-aiops/python/`.

### Common questions

**Q: How is infrastructure as code managed across both on-premises and cloud?**

Terraform is used as the single IaC layer across all environments —
vSphere on-prem, AWS EKS, and Azure AKS. Reusable modules such as
`nawex-vsphere`, `nawex-eks`, and `nawex-aks` are called by each
environment composition. Whether provisioning a vSphere VM or an EKS
node group, the pattern is the same: declare the environment in `envs/`,
call the module, set environment-specific variables. On-premises and
cloud are peer execution environments — that consistency is what a
hybrid platform requires.

*Reference: [infra/terraform/envs/](../infra/terraform/envs/) and [infra/terraform/modules/](../infra/terraform/modules/)*

**Q: How are security and cost guardrails enforced in Terraform?**

Two layers: static analysis in CI, and FinOps automation at runtime.
Every Terraform pull request runs `tfsec` and `checkov`, which block
misconfigured security groups, unencrypted storage, or public exposure
before anything gets applied. For cost, resource tagging is embedded in
the modules themselves so every resource carries environment, team, and
cost-center tags from the moment it is created. The utilities under
`finops-aiops/python/` perform budget-burn prediction and rightsizing
analysis, so cost drift is caught before an invoice arrives.

*Reference: [.github/workflows/](../.github/workflows/), [finops-aiops/python/](../finops-aiops/python/), Terraform modules*

**Q: What is the module strategy and how does it prevent environment drift?**

One module per platform type, many environments calling it. The
`nawex-vsphere` module encapsulates all vSphere-specific resource logic.
Each environment in `envs/onprem` is a thin composition that just sets
variables. There is no per-environment fork of the module logic — a fix
to the module propagates to all callers. CI additionally runs `terraform
fmt` and `terraform validate` on every commit, and the repository ships
a `.pre-commit-config.yaml` that enforces formatting before a commit is
even pushed.

*Reference: [infra/terraform/modules/](../infra/terraform/modules/), [.pre-commit-config.yaml](../.pre-commit-config.yaml)*

**Q: How is OpenShift handled in IaC, and how is it different from vanilla Kubernetes?**

The platform supports two OpenShift deployment models via Terraform:
`openshift-rosa` (managed Red Hat OpenShift on AWS) and
`openshift-vsphere` (self-managed installer-provisioned infrastructure
on vSphere). The key operational differences from vanilla Kubernetes:
OpenShift uses Security Context Constraints (SCC) instead of Pod
Security Admission, it uses Routes instead of Ingress objects, and all
workloads must run non-root. The OpenShift Kubernetes overlay therefore
adds a Route manifest, an SCC RoleBinding for non-root pods, and
PSA-restricted namespace labels.

*Reference: [infra/terraform/envs/openshift-rosa/](../infra/terraform/envs/openshift-rosa/), [k8s/overlays/openshift/](../k8s/overlays/openshift/)*

### Module 1 checklist

- Read [infra/terraform/modules/](../infra/terraform/modules/) — understand each module's inputs and outputs
- Read [infra/terraform/envs/onprem/](../infra/terraform/envs/onprem/) — trace how the vSphere module is called
- Read [infra/terraform/envs/aws-eks/](../infra/terraform/envs/aws-eks/) and [infra/terraform/envs/azure-aks/](../infra/terraform/envs/azure-aks/)
- Read [infra/terraform/envs/openshift-rosa/](../infra/terraform/envs/openshift-rosa/) and [infra/terraform/envs/openshift-vsphere/](../infra/terraform/envs/openshift-vsphere/)
- Review [.pre-commit-config.yaml](../.pre-commit-config.yaml) — note which tools it runs

---

## Module 2 — Ansible and CI/CD

### Plain-language summary

Once a server exists, it needs to be configured: software installed,
security settings applied, services started. Ansible automates these
steps in a repeatable way. CI/CD pipelines are automated checks that
run on every code change to catch problems early — before code reaches
production. NAWEX uses both to keep the platform predictable and safe.

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
    vsphere-join-cluster.yml  # automates joining VMs to a Kubernetes cluster
    linux-baseline.yml        # hardening, packages, sysctl
```

### CI/CD pipeline — what each stage does

1. **Lint and format:** `ruff check` and `ruff format` on Python,
   `shellcheck` on all shell scripts, `terraform fmt` on Terraform.
2. **Static security scan:** `tfsec` and `checkov` on Terraform;
   `Hadolint` on every Dockerfile.
3. **Container image scan:** `Trivy` scans every built container image.
   CRITICAL and HIGH findings cause the build to fail.
4. **Kubernetes validation:** `kubeconform` validates every Kustomize
   overlay against the Kubernetes API schema.
5. **Unit tests:** `pytest -q` runs the Python test suite for the
   FinOps and AIOps utilities.
6. **Deploy / GitOps sync:** Argo CD picks up validated manifests from
   Git. CI only validates; GitOps controls deployment.

> A note on portability: the same pipeline pattern translates directly
> between CI providers (GitHub Actions, GitLab CI, Jenkins, and so on).
> The stages, jobs, runners, artifacts, and caching concepts are
> identical — only the YAML syntax differs.

### Common questions

**Q: How is Ansible used in a hybrid environment with both static and dynamic inventory?**

In NAWEX, the on-premises vSphere environment uses both. For known,
stable infrastructure there is a `hosts.yml` static inventory — useful
when VM IP addresses are fixed and explicit control is desired. For the
dynamic side, `vmware.yml` uses the dynamic inventory plugin to query
the vCenter API and pull the current VM list at runtime. This is
critical when VMs are being created by Terraform. Both inventory
sources feed into the same playbooks: `linux-baseline.yml` runs against
all hosts regardless of how they were discovered, applying the same
hardening and package baseline everywhere.

*Reference: [infra/ansible/inventories/onprem/hosts.yml](../infra/ansible/inventories/onprem/hosts.yml), [infra/ansible/inventories/onprem/vmware.yml](../infra/ansible/inventories/onprem/vmware.yml)*

**Q: What are the quality gates in the CI/CD pipeline?**

Six progressive gates. Code quality first: `ruff` for Python and
`shellcheck` for shell scripts. Then static security: `tfsec` and
`checkov` on Terraform, `Hadolint` on Dockerfiles. Container images are
built and immediately scanned with `Trivy` — CRITICAL and HIGH
vulnerabilities fail the build. `kubeconform` validates every Kustomize
overlay against the real Kubernetes API schema, so a misconfigured
manifest never gets committed. Finally, `pytest` covers the Python
FinOps utilities. Only after all six gates pass does Argo CD sync the
change.

*Reference: [.github/workflows/](../.github/workflows/), [pyproject.toml](../pyproject.toml), [.pre-commit-config.yaml](../.pre-commit-config.yaml)*

**Q: How is joining new nodes to a Kubernetes cluster automated?**

For on-premises vSphere nodes, the `vsphere-join-cluster.yml` Ansible
playbook handles it. Terraform provisions the VM, Ansible runs the
Linux baseline, and then the kubeadm-join playbook retrieves the join
token from the control plane and executes `kubeadm join` on the new
node. Fully automated — no manual SSH required. For cloud clusters
such as EKS, node joining is handled by the managed control plane:
the Terraform module configures the node group and the cloud provider
handles bootstrapping via the EKS AMI.

*Reference: [infra/ansible/playbooks/vsphere-join-cluster.yml](../infra/ansible/playbooks/vsphere-join-cluster.yml)*

### Module 2 checklist

- Read [infra/ansible/playbooks/](../infra/ansible/playbooks/) — trace `vsphere-join-cluster.yml` step by step
- Read both inventory files (`hosts.yml` and `vmware.yml`)
- Read [.github/workflows/](../.github/workflows/) — map each job to its tool
- Read [.pre-commit-config.yaml](../.pre-commit-config.yaml) — know every hook

---

## Module 3 — Kubernetes and GitOps

### Plain-language summary

Kubernetes runs containerized applications across many servers, handling
restarts, scaling, and networking. GitOps is a discipline where the
description of what should be running lives in a Git repository, and a
controller continuously reconciles the cluster to match. NAWEX uses
Kustomize for environment-specific configuration and Argo CD as the
GitOps controller, so any change is version-controlled, reviewable, and
auditable.

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
    dev-platform.yaml     # etc.
  local/                  # kind cluster test harness
```

### Container security posture — six baseline settings

Every container in the platform runs with:

1. `runAsNonRoot: true`
2. `readOnlyRootFilesystem: true`
3. `allowPrivilegeEscalation: false`
4. `capabilities: drop: [ALL]`
5. seccomp profile `RuntimeDefault`
6. `automountServiceAccountToken: false` on service accounts that do not
   call the Kubernetes API

Namespaces are labeled for Pod Security Admission `restricted`
enforcement, so Kubernetes itself rejects non-compliant pods at
admission. NetworkPolicy starts with a default-deny stance and only
allows the minimum ingress and DNS egress required.

### Common questions

**Q: How does the Kubernetes overlay structure handle multiple environments?**

Using a Kustomize base-plus-overlay pattern. `k8s/base/` contains shared
manifests — Deployments, Services, ConfigMaps, NetworkPolicy, and
PodDisruptionBudget. Each environment in `k8s/overlays/` is a thin
Kustomize layer that patches only what differs: replica count, resource
limits, image tags, or platform-specific additions. The OpenShift
overlay adds a Route manifest and SCC RoleBinding that base does not
have. The prod overlay disables automated sync. All seven targets share
the same base, so a security fix in base propagates everywhere.

*Reference: [k8s/overlays/](../k8s/overlays/), [k8s/base/](../k8s/base/)*

**Q: How does the Argo CD GitOps flow work, and what is the app-of-apps pattern?**

Argo CD starts from `gitops/root-application.yaml`, which is a single
Argo Application pointing to `gitops/apps/`. Each file in that directory
is itself an Argo Application pointing to a specific environment
overlay. The root application deploys the child applications, and each
child application deploys an environment. Adding a new environment
means adding one file to `gitops/apps/` — Argo CD picks it up
automatically. The `project.yaml` scopes RBAC so Argo CD can only
deploy the specific resource kinds this platform uses, with no wildcard
cluster-admin access. Important: prod runs with `automated: false` for
prune and selfHeal, so prod changes need an explicit human sync; dev and
staging are fully automated.

*Reference: [gitops/root-application.yaml](../gitops/root-application.yaml), [gitops/project.yaml](../gitops/project.yaml), [gitops/apps/](../gitops/apps/)*

**Q: How are containers hardened in Kubernetes?**

Every container runs with `runAsNonRoot: true`,
`readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`,
`capabilities: drop: [ALL]`, and seccomp profile `RuntimeDefault`. At
the namespace level, Pod Security Admission `restricted` enforcement is
labeled on, so Kubernetes rejects any non-compliant pod at admission —
this is not just a runtime check. The application service account has
`automountServiceAccountToken: false` because it does not need to call
the Kubernetes API. NetworkPolicy starts with default-deny and adds
only the minimum ingress and DNS egress required.

*Reference: [k8s/base/](../k8s/base/) manifests, [k8s/overlays/](../k8s/overlays/) namespace patches*

### Module 3 checklist

- Read [k8s/base/](../k8s/base/) — understand every manifest and why it exists
- Read at least three overlays: `onprem`, `openshift`, `prod`
- Read [gitops/root-application.yaml](../gitops/root-application.yaml) and [gitops/project.yaml](../gitops/project.yaml)
- Read [gitops/apps/](../gitops/apps/) — trace how each environment app is defined
- Be able to explain the app-of-apps pattern in your own words
- Be able to recite all six container security settings from memory

---

## Module 4 — Observability and FinOps

### Plain-language summary

Once a system is running, the team needs to know how it is performing
and how much it costs. Observability covers monitoring, alerting, and
incident response. FinOps brings the same discipline to cost: tag
everything, measure spend, predict overruns, and right-size workloads.
NAWEX combines both into a single operational pipeline so cost and
reliability signals are treated equally.

### Repository layout

```
observability/
  alerts/slo-alerts.yml          # multi-burn-rate SLO alert rules
  alertmanager/
    alertmanager.yml             # routes alerts to Slack via webhook
    templates/slack.tmpl         # Go template: summary + runbook + commands
  grafana/                       # dashboard JSON

finops-aiops/python/
  anomaly_detection.py           # statistical cost/metric anomaly detection
  rightsizing.py                 # CPU/memory usage to rightsizing recommendations
  budget_burn.py                 # burn-rate prediction and forecast
  slo_risk.py                    # error-budget remaining analysis

scripts/
  alert_webhook.py               # receives alerts and writes them to .incidents/
  incident_respond.sh            # list, show, approve, deny incidents
  remediations/                  # per-alert remediation scripts
```

### Alert → incident → remediation flow

```
# 1. Prometheus fires an alert (SLO burn, crashloop, budget drift)
Prometheus rules → alertmanager.yml → Slack channel

# 2. The alert message includes approve/deny commands.
#    A remediation_action label in slo-alerts.yml maps to a script.

# 3. alert_webhook.py persists the alert to .incidents/<fingerprint>.json

# 4. On-call engineer workflow:
./scripts/incident_respond.sh show <id>     # DRY_RUN preview
./scripts/incident_respond.sh approve <id>  # runs remediations/<action>.sh
./scripts/incident_respond.sh deny <id>     # acknowledge without action

# 5. The audit trail posts back to Slack.
```

### Common questions

**Q: How are SLOs implemented, and what are multi-burn-rate alerts?**

SLIs and SLOs are defined in the architecture documents — availability
and latency targets per service. In `observability/alerts/slo-alerts.yml`,
multi-burn-rate alerts are implemented. A fast burn at 14× rate over 1
hour pages immediately because the error budget is draining fast. A
slow burn at 2× rate over 6 hours sends a warning. This follows the
Google SRE approach: severity is proportional to how fast budget is
being consumed, not just whether an alert fires. Standard threshold
alerts miss this — a service can have a technically passing error rate
while still consuming its monthly budget too quickly.

*Reference: [observability/alerts/slo-alerts.yml](../observability/alerts/slo-alerts.yml), [architecture/sli-slo-model.md](sli-slo-model.md)*

**Q: How is FinOps applied in practice?**

Three concrete mechanisms. First, cost tagging at provisioning —
Terraform modules tag every resource with environment, team, and
cost-center metadata from day one. Second, rightsizing automation —
`rightsizing.py` analyzes actual CPU and memory utilization versus
requested limits and generates recommendations, catching
over-provisioned workloads automatically. Third, budget-burn prediction
— `budget_burn.py` tracks spend rate and forecasts month-end costs;
if burn rate is trending toward a budget breach, it fires early. These
utilities feed into the same alerting pipeline as infrastructure
alerts: cost is a first-class operational signal, not an afterthought.

*Reference: [finops-aiops/python/](../finops-aiops/python/), Terraform modules (cost tags)*

**Q: Walk through an on-call incident response scenario.**

A pod enters a crashloop. Prometheus detects it via kube-state-metrics
and fires an alert defined in `slo-alerts.yml`. AlertManager routes the
alert through `alertmanager.yml` and renders a Slack message from the
`slack.tmpl` Go template; the message includes the summary, a link to
the runbook, and copy-ready approve/deny commands. Simultaneously,
`alert_webhook.py` persists the alert to `.incidents/<fingerprint>.json`.
The on-call engineer runs `incident_respond.sh show <id>`, which
previews the exact remediation in dry-run mode. They then run `approve`
and the system executes `remediations/restart-crashloop.sh`
automatically. The audit trail posts back to Slack. The whole flow is
reproducible, auditable, and does not require anyone to have ad-hoc
kubectl access during off-hours.

*Reference: [scripts/alert_webhook.py](../scripts/alert_webhook.py), [scripts/incident_respond.sh](../scripts/incident_respond.sh), [scripts/remediations/](../scripts/remediations/), [runbooks/slack-alerting.md](../runbooks/slack-alerting.md)*

### Module 4 checklist

- Read [observability/alerts/slo-alerts.yml](../observability/alerts/slo-alerts.yml) — understand the burn-rate rules
- Read [observability/alertmanager/alertmanager.yml](../observability/alertmanager/alertmanager.yml) and `slack.tmpl`
- Read [scripts/alert_webhook.py](../scripts/alert_webhook.py) and [scripts/incident_respond.sh](../scripts/incident_respond.sh)
- Read all four utilities under [finops-aiops/python/](../finops-aiops/python/) — understand what each does
- Read [runbooks/slack-alerting.md](../runbooks/slack-alerting.md) — the full operational procedure
- Be able to explain the alert-to-remediation flow end-to-end

---

## Module 5 — VM-to-Kubernetes Migration

### Plain-language summary

Many organizations have applications running on traditional virtual
machines that they want to modernize by moving into containers. NAWEX
includes tooling that makes this migration repeatable: it inventories
the existing VMs, captures their characteristics, and generates the
container and Kubernetes definitions automatically. The result is then
deployed through the same GitOps pipeline as any other workload.

### Repository layout

```
migration/
  assess/        # Step 1: inventory vCenter VMs into WorkloadProfile stubs
  containerize/  # Step 2: WorkloadProfile to Dockerfile and K8s manifest
  samples/       # example WorkloadProfile YAML files
```

### The four-step flow

**Step 1 — Assess.** The assess tooling queries vCenter, inventories the
VMs, and generates WorkloadProfile stubs — structured YAML describing
each workload's operating system, ports, environment variables, and
storage needs.

**Step 2 — Containerize.** A WorkloadProfile becomes a Dockerfile and a
Kubernetes manifest. The tool generates a container build spec and a
Kubernetes Deployment, Service, and PersistentVolumeClaim from the
profile. No manual Dockerfile writing required.

**Step 3 — Deploy via GitOps.** Generated manifests drop into the
GitOps repository, and Argo CD deploys them to EKS, AKS, or OpenShift —
consistent delivery regardless of the migration destination.

**Step 4 — Runbook.** [runbooks/vm-to-k8s-migration.md](../runbooks/vm-to-k8s-migration.md) is the operational
procedure: assessment checklist, containerization steps, validation
gates, and rollback path.

### Module 5 checklist

- Read [migration/](../migration/) — trace the full VM-to-Kubernetes flow
- Read [runbooks/vm-to-k8s-migration.md](../runbooks/vm-to-k8s-migration.md) and [runbooks/openshift-operations.md](../runbooks/openshift-operations.md)

---

## Cross-cutting topics

### How the platform stays consistent across on-premises and cloud

Five mechanisms hold this together:

1. **Shared Terraform modules** with the same interface whether calling
   into vSphere, AWS, or Azure.
2. **Common Ansible roles** — the Linux baseline runs on both on-prem
   VMs and cloud instances.
3. **Unified Kustomize overlays** — `onprem` is just another overlay
   target sharing the same base.
4. **A single GitOps control plane** — Argo CD manages both on-prem and
   cloud applications from the same root application.
5. **Shared observability** — the same Prometheus rules and
   AlertManager configuration apply to all environments.

The mental model is simple: cloud and on-premises are peer execution
environments. They differ in provider details, but the engineering
practices are identical.

### Reducing manual operations through automation

Two examples from the platform:

- **Node provisioning and cluster join** used to be a manual process —
  Terraform created the VM, then someone had to SSH in, run kubeadm,
  and copy tokens. The platform automates the full lifecycle: Terraform
  provisions the VM, Ansible's `vsphere-join-cluster.yml` automatically
  retrieves the join token and runs `kubeadm join`. Zero manual steps
  from VM creation to a production-ready Kubernetes node.
- **Incident response** used to require on-call engineers to have
  direct kubectl access and remember the right remediation command.
  The `incident_respond.sh` workflow replaces this: alerts are
  persisted, and engineers approve a pre-defined remediation through a
  dry-run preview. Cognitive load drops significantly.

### Mission-critical operational mindset

The architecture decisions in NAWEX — the hybrid GitOps model, the
non-negotiable security posture, the SLO-driven alerting, and the
manual approval gate on prod — were made with regulated, mission-critical
data contexts in mind. In such environments, reliability, auditability,
and security are not nice-to-haves; they are the entire job.

---

## Capability map

| Capability | Where it lives in the repository |
|---|---|
| Terraform IaC | [infra/terraform/](../infra/terraform/) — three modules, eight environments |
| Ansible | [infra/ansible/](../infra/ansible/) — dynamic vSphere inventory and kubeadm-join automation |
| Containers and Kubernetes | Seven overlays, security-hardened, GitOps-managed |
| CI/CD pipelines | [.github/workflows/](../.github/workflows/) — six-stage quality gate |
| FinOps | [finops-aiops/python/](../finops-aiops/python/) — four Python utilities |
| GitOps | Argo CD app-of-apps, seven targets |
| Linux systems | Ansible Linux baseline, all infrastructure Linux-based |
| Scripting (Python and Bash) | [scripts/](../scripts/) and [finops-aiops/](../finops-aiops/) |

---

## Suggested learning path

A reader new to the platform can follow this sequence:

1. Read this guide end-to-end at a high level — focus on the
   plain-language summaries.
2. Work through Module 1 (Terraform), then Module 2 (Ansible and CI/CD).
   Together these cover how infrastructure comes into existence.
3. Move to Module 3 (Kubernetes and GitOps) to see how applications are
   delivered onto that infrastructure.
4. Read Module 4 (Observability and FinOps) to learn how the running
   platform is operated and kept healthy.
5. Finish with Module 5 (Migration) to see how legacy VM workloads are
   modernized.
6. Revisit the cross-cutting topics section to understand the patterns
   that hold all five modules together.
