# NAWEX Platform — Phased Implementation Runbook

**Version:** 1.0.0  
**Author:** Emmanuel Naweji  
**Repo:** github.com/Here2ServeU/nawex-hybrid-devops-platform  
**Updated:** April 2026

---

## Purpose

This runbook defines the recommended phased approach to implement the NAWEX Hybrid DevOps Platform from zero to full production capability. Each phase builds on the previous, ensures stability before advancing, and can be paused independently between phases.

Supported targets: on-premises vSphere, AWS EKS, Azure AKS, OpenShift ROSA, OpenShift IPI on vSphere, and bare metal (Cisco UCS, HPE ProLiant, Dell PowerEdge).

---

## Phase Overview

| Phase | Name | Focus | Duration |
|---|---|---|---|
| 1 | Foundation | Git, CI/CD, remote state, pre-commit | Week 1 |
| 2 | Infrastructure Provisioning | Terraform modules, first environment | Week 2-3 |
| 3 | Configuration Management | Ansible baseline, node onboarding | Week 3-4 |
| 4 | Kubernetes Platform | Base manifests, overlays, security hardening | Week 4-5 |
| 5 | GitOps Delivery | Argo CD app-of-apps, environment sync | Week 5-6 |
| 6 | Observability | Prometheus, Grafana, AlertManager, SLO alerts | Week 6-7 |
| 7 | Incident Response | Webhook, remediation scripts, runbooks | Week 7-8 |
| 8 | FinOps and AIOps | Cost utilities, tagging, budget alerting | Week 8-9 |
| 9 | Migration Pipeline | VM assessment, containerization, GitOps deploy | Week 9-11 |
| 10 | Hardening and Cutover | Security audit, load test, production cutover | Week 11-12 |

---

## Prerequisites Before Any Phase Begins

- [ ] Git repository access granted to the implementation team
- [ ] AWS account with IAM permissions for EKS, EC2, S3, IAM, VPC
- [ ] Azure subscription with contributor access for AKS
- [ ] vCenter credentials with read/write access to target cluster
- [ ] Red Hat account and pull secret for OpenShift deployments
- [ ] Terraform CLI >= 1.6 installed
- [ ] Ansible >= 2.14 installed with VMware collection
- [ ] kubectl and kustomize installed
- [ ] AWS CLI and Azure CLI configured
- [ ] Slack workspace with an incoming webhook URL
- [ ] Remote state backend provisioned (S3 or Azure Blob)
- [ ] SSH key pair generated for Ansible

---

## Phase 1 — Foundation

**Goal:** Establish the engineering foundation. Everything that follows depends on this being solid.

### 1.1 Clone and configure

```bash
git clone https://github.com/Here2ServeU/nawex-hybrid-devops-platform.git
cd nawex-hybrid-devops-platform
cp .env.example .env
# Edit .env: SLACK_WEBHOOK_URL, AWS credentials, vCenter credentials
```

### 1.2 Install pre-commit hooks

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

All hooks must pass before proceeding.

### 1.3 Configure CI/CD secrets

Add to GitHub Actions secrets or GitLab CI variables:
- `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- `AZURE_CREDENTIALS`
- `SLACK_WEBHOOK_URL`
- `TF_BACKEND_BUCKET`

Verify all six CI gates pass on the main branch:

```bash
ruff check . && ruff format --check .
shellcheck scripts/*.sh
terraform fmt -check -recursive infra/terraform/
pytest -q
```

### 1.4 Provision remote state backend

**AWS:**
```bash
aws s3 mb s3://nawex-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket nawex-terraform-state \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name nawex-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

**Azure:**
```bash
az group create --name nawex-tfstate-rg --location eastus
az storage account create --name nawextfstate --resource-group nawex-tfstate-rg --sku Standard_LRS
az storage container create --name tfstate --account-name nawextfstate
```

Update `envs/<env>/backend.tf` before running `terraform init`.

### Phase 1 Checklist
- [ ] Repository cloned and .env configured
- [ ] Pre-commit hooks installed and passing
- [ ] CI pipeline all six gates pass
- [ ] Remote state backend provisioned

---

## Phase 2 — Infrastructure Provisioning

**Goal:** Provision the first target environment using Terraform. Start with dev or on-prem.

### 2.1 Provision on-prem vSphere

```bash
cd infra/terraform/envs/onprem
terraform init
terraform plan -out=onprem.tfplan
terraform apply onprem.tfplan
```

### 2.2 Provision dev cloud environment

```bash
cd infra/terraform/envs/dev
terraform init && terraform plan -out=dev.tfplan && terraform apply dev.tfplan
```

### 2.3 Provision migration targets (Phase 9 only)

Do not provision idle clusters. Run these only when ready to migrate workloads.

```bash
# AWS EKS
cd infra/terraform/envs/aws-eks
terraform init && terraform apply

# Azure AKS
cd infra/terraform/envs/azure-aks
terraform init && terraform apply

# OpenShift ROSA
cd infra/terraform/envs/openshift-rosa
terraform init && terraform apply
```

### 2.4 Verify cost tags

```bash
# AWS
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=environment,Values=dev \
  --query 'ResourceTagMappingList[*].ResourceARN'

# Azure
az resource list --resource-group nawex-dev-rg \
  --query '[*].{name:name,tags:tags}' --output table
```

Every resource must show `environment`, `team`, and `cost_center` tags.

### Phase 2 Checklist
- [ ] On-prem VMs provisioned and visible in vCenter
- [ ] Dev cloud environment provisioned
- [ ] All resources tagged correctly
- [ ] tfsec and checkov pass with no CRITICAL findings

---

## Phase 3 — Configuration Management

**Goal:** Apply Linux baseline and security hardening to all provisioned hosts.

### 3.1 Configure static inventory

Edit `infra/ansible/inventories/onprem/hosts.yml`:

```yaml
all:
  hosts:
    nawex-node-01:
      ansible_host: 10.0.1.10
      ansible_user: ec2-user
      ansible_ssh_private_key_file: ~/.ssh/nawex-key
```

### 3.2 Test dynamic vSphere inventory

```bash
export VCENTER_USER=your_user
export VCENTER_PASSWORD=your_password
ansible-inventory -i infra/ansible/inventories/onprem/vmware.yml --list
```

### 3.3 Run linux-baseline (dry run first)

```bash
# Always dry-run before applying
ansible-playbook -i infra/ansible/inventories/onprem/hosts.yml \
  infra/ansible/playbooks/linux-baseline.yml --check --diff

# Apply after review
ansible-playbook -i infra/ansible/inventories/onprem/hosts.yml \
  infra/ansible/playbooks/linux-baseline.yml
```

### 3.4 Run kubeadm join playbook

After Kubernetes control plane is initialized:

```bash
ansible-playbook -i infra/ansible/inventories/onprem/hosts.yml \
  infra/ansible/playbooks/vsphere-join-cluster.yml \
  -e "k8s_control_plane_host=10.0.1.5"

kubectl get nodes -o wide
# All nodes should show Ready within 90 seconds
```

### Phase 3 Checklist
- [ ] Static inventory connects to all hosts
- [ ] Dynamic vSphere inventory returns correct VM list
- [ ] linux-baseline runs idempotently (run twice, same result)
- [ ] All nodes show Ready in kubectl get nodes
- [ ] Monitoring agent installed and reporting

---

## Phase 4 — Kubernetes Platform

**Goal:** Deploy base manifests and all seven environment overlays with full security hardening.

### 4.1 Validate all overlays

```bash
for overlay in k8s/overlays/*/; do
  echo "Validating: $overlay"
  kustomize build "$overlay" | kubeconform -strict
  echo "PASS: $overlay"
done
```

All seven overlays must pass before deploying to any cluster.

### 4.2 Label namespaces for PSA enforcement

```bash
kubectl label namespace nawex-platform \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

### 4.3 Apply base manifests to dev

```bash
kubectl apply -k k8s/overlays/dev/
kubectl get pods -n nawex-platform
kubectl describe pod -n nawex-platform | grep -A 5 "Security Context"
```

Confirm every container shows runAsNonRoot, readOnlyRootFilesystem, allowPrivilegeEscalation false.

### 4.4 Apply OpenShift overlay

```bash
oc apply -k k8s/overlays/openshift/
oc get route -n nawex-platform
oc describe rolebinding nawex-scc-binding -n nawex-platform
```

### 4.5 Verify NetworkPolicy enforcement

```bash
# Default deny should block unauthorized traffic
kubectl exec -it <test-pod> -n nawex-platform -- \
  curl -v http://unauthorized-service/
# Expected: connection refused or timeout

# DNS egress must still work
kubectl exec -it <test-pod> -n nawex-platform -- nslookup kubernetes.default
```

### Phase 4 Checklist
- [ ] All seven overlays pass kubeconform validation
- [ ] PSA restricted enforcement active on all namespaces
- [ ] All pods running with hardened security context
- [ ] NetworkPolicy blocking unauthorized traffic
- [ ] PodDisruptionBudget verified during simulated node drain
- [ ] Probes healthy: startup, readiness, liveness

---

## Phase 5 — GitOps Delivery

**Goal:** Install Argo CD and activate the app-of-apps pattern. All environments sync from Git except production.

### 5.1 Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
```

### 5.2 Update repository URL in gitops/

```bash
grep -rl "Here2ServeU/nawex-hybrid-devops-platform" gitops/ | \
  xargs sed -i 's|Here2ServeU/nawex-hybrid-devops-platform|YOUR-ORG/YOUR-REPO|g'
```

### 5.3 Apply AppProject and root application

```bash
kubectl apply -f gitops/project.yaml
kubectl apply -f gitops/root-application.yaml
```

### 5.4 Monitor initial sync

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

Open https://localhost:8080. Verify:
- Root application shows healthy
- Dev and staging syncing automatically
- Prod shows OutOfSync (expected — manual sync required)

### 5.5 Validate local GitOps harness

```bash
./scripts/start_local_gitops.sh
kubectl port-forward svc/nawex-api -n nawex-local 8081:80
./scripts/smoke_test.sh
./scripts/stop_local_gitops.sh
```

### Phase 5 Checklist
- [ ] Argo CD installed and accessible
- [ ] AppProject applied with scoped RBAC
- [ ] Root application healthy
- [ ] Dev and staging auto-syncing
- [ ] Prod requiring explicit manual sync
- [ ] Local harness end-to-end test passing

---

## Phase 6 — Observability

**Goal:** Activate Prometheus, Grafana, AlertManager. Configure multi-burn-rate SLO alerts. Connect to Slack.

### 6.1 Deploy observability stack

```bash
kubectl apply -f observability/prometheus/
kubectl create secret generic alertmanager-slack \
  --from-literal=SLACK_WEBHOOK_URL="$SLACK_WEBHOOK_URL" -n monitoring
kubectl apply -f observability/alertmanager/alertmanager.yml
kubectl apply -f observability/grafana/
```

### 6.2 Verify SLO alert rules

```bash
kubectl port-forward svc/prometheus -n monitoring 9090:9090
# Open http://localhost:9090/rules
# All rules from slo-alerts.yml should appear with state OK
```

### 6.3 Test Slack alert pipeline end-to-end

```bash
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "remediation_action": "restart-crashloop"
    },
    "annotations": {"summary": "Test alert - verifying Slack pipeline"}
  }]'
```

Verify Slack message arrives with summary, runbook link, and approve/deny commands.

### Phase 6 Checklist
- [ ] Prometheus scraping all targets
- [ ] SLO alert rules loaded with no errors
- [ ] Test alert delivered to Slack with correct format
- [ ] Grafana dashboards rendering live data
- [ ] Multi-burn-rate alerts validated

---

## Phase 7 — Incident Response

**Goal:** Activate the full incident workflow. Every alert label must map to a remediation script.

### 7.1 Start the alert webhook

```bash
python scripts/alert_webhook.py &
curl -X GET http://localhost:5001/health
```

### 7.2 Verify remediation script mapping

```bash
grep "remediation_action" observability/alerts/slo-alerts.yml
ls scripts/remediations/
# Every remediation_action value must have a corresponding script
```

### 7.3 Run a full dry-run incident test

```bash
echo '{
  "fingerprint": "test-001",
  "labels": {
    "alertname": "KubePodCrashLooping",
    "remediation_action": "restart-crashloop",
    "namespace": "nawex-platform",
    "pod": "nawex-api-test"
  }
}' > .incidents/test-001.json

./scripts/incident_respond.sh show test-001
DRY_RUN=1 ./scripts/incident_respond.sh approve test-001
```

### 7.4 Schedule a game day

Run a 30-minute incident simulation with the full operations team before production cutover. Practice the show, approve, and deny workflow for at least three different alert types.

### Phase 7 Checklist
- [ ] alert_webhook.py running and accepting alerts
- [ ] All alert labels mapped to remediation scripts
- [ ] Dry-run test passes for three different alert types
- [ ] Audit trail posting to Slack correctly
- [ ] Team has read the on-call runbook
- [ ] Game day completed

---

## Phase 8 — FinOps and AIOps

**Goal:** Activate cost visibility, rightsizing, budget burn prediction, and SLO risk analysis.

### 8.1 Verify cost tags

```bash
python finops-aiops/python/cost-report.py --env dev --output table
# Every resource must show environment, team, cost_center
```

### 8.2 Run rightsizing analysis

```bash
python finops-aiops/python/rightsizing.py \
  --namespace nawex-platform \
  --prometheus-url http://localhost:9090 \
  --output recommendations.json
cat recommendations.json
```

Apply recommendations to the relevant Kustomize overlays.

### 8.3 Configure and test budget burn alerts

```bash
export NAWEX_MONTHLY_BUDGET_USD=5000
export NAWEX_BUDGET_WARN_PCT=80

python finops-aiops/python/budget_burn.py \
  --budget $NAWEX_MONTHLY_BUDGET_USD \
  --warn-pct $NAWEX_BUDGET_WARN_PCT
```

Budget alerts must appear in the same Slack channel as infrastructure alerts.

### 8.4 Run SLO risk analysis

```bash
python finops-aiops/python/slo_risk.py \
  --prometheus-url http://localhost:9090 \
  --service nawex-api
```

If risk is HIGH, investigate before proceeding to production cutover.

### Phase 8 Checklist
- [ ] All resources tagged — no untagged resources in cost-report
- [ ] Rightsizing recommendations reviewed and applied
- [ ] Budget burn alerts firing correctly
- [ ] SLO risk analysis running without errors
- [ ] Anomaly detection baseline established (requires 72 hours of data)

---

## Phase 9 — Migration Pipeline

**Goal:** Migrate on-prem vSphere VMs to containerized workloads on EKS, AKS, or OpenShift.

### 9.1 Assess source VMs

```bash
export VCENTER_HOST=vcenter.yourorg.local
export VCENTER_USER=migration_user
export VCENTER_PASSWORD=your_password

python migration/assess/inventory.py \
  --vcenter $VCENTER_HOST \
  --output migration/samples/
```

Classify each workload in the generated WorkloadProfile YAML:
- `type: stateless-service` - migrate first
- `type: stateful-service` - requires PVC planning
- `type: legacy-requires-remediation` - backlog

### 9.2 Containerize a stateless workload

```bash
python migration/containerize/generate-dockerfile.py \
  --profile migration/samples/your-workload.yaml \
  --output migration/output/

python migration/containerize/generate-manifest.py \
  --profile migration/samples/your-workload.yaml \
  --target aws-eks \
  --output k8s/overlays/aws-eks/

docker build -t nawex-migrated/your-workload:v1 migration/output/
trivy image nawex-migrated/your-workload:v1
# Fix all CRITICAL and HIGH CVEs before proceeding
```

### 9.3 Deploy via GitOps

```bash
git add k8s/overlays/aws-eks/
git commit -m "feat(migration): containerize your-workload from vSphere"
git push origin main
# Argo CD detects the change and syncs automatically
```

### 9.4 Smoke test and validation window

```bash
./migration/validate/smoke-test.sh \
  --namespace nawex-platform \
  --service your-workload

# 72-hour validation window begins on smoke test pass
# Monitor: pod restarts, error rate, memory, CPU, AIOps anomaly alerts
```

### 9.5 Decommission source VM

Only after 72-hour validation window passes with no incidents:

```bash
cd infra/terraform/envs/onprem
terraform plan -destroy -target=vsphere_virtual_machine.your_workload
# Review destroy plan carefully
terraform destroy -target=vsphere_virtual_machine.your_workload
```

### Phase 9 Checklist
- [ ] All VMs assessed and classified
- [ ] At least one stateless workload successfully containerized
- [ ] Generated manifests pass all CI gates
- [ ] Smoke tests passing in target cluster
- [ ] 72-hour validation window completed
- [ ] Source VM decommissioned and removed from vCenter

---

## Phase 10 — Hardening and Production Cutover

**Goal:** Final security review, load testing, and production cutover. Do not rush this phase.

### 10.1 Full security audit

```bash
tfsec infra/terraform/
checkov -d infra/terraform/
hadolint app/**/Dockerfile
trivy fs . --severity HIGH,CRITICAL
kubeconform -strict k8s/overlays/prod/
```

All CRITICAL findings must be resolved before cutover.

### 10.2 Verify PSA enforcement in production

```bash
# A non-compliant pod must be rejected
kubectl apply -f - <<-YAML
apiVersion: v1
kind: Pod
metadata:
  name: security-test
  namespace: nawex-platform
spec:
  containers:
  - name: test
    image: nginx
    securityContext:
      runAsNonRoot: false
YAML
# Expected: Error from server (Forbidden)
```

If the pod is accepted, PSA enforcement is not active. Stop and fix before cutover.

### 10.3 Load test

```bash
# Run a 10-minute load test before cutover
k6 run --vus 50 --duration 10m scripts/load-test.js

# Monitor during load test
kubectl top pods -n nawex-platform
kubectl get hpa -n nawex-platform
```

Verify no pods OOMKilled and PodDisruptionBudget holds during node drain.

### 10.4 Execute production sync

```bash
# Explicit human gate — do not automate this step
argocd app sync nawex-prod --prune
```

Or through the Argo CD UI: navigate to the prod application, review the diff, click Sync.

### 10.5 Post-cutover verification

```bash
./scripts/smoke_test.sh --env prod
kubectl get pods -n nawex-platform
python finops-aiops/python/slo_risk.py --service nawex-api
python finops-aiops/python/cost-report.py --env prod
```

Schedule a postmortem 48 hours after cutover to capture lessons learned.

### Phase 10 Checklist
- [ ] Full security audit passed — no unresolved CRITICAL findings
- [ ] PSA enforcement verified — non-compliant pods rejected
- [ ] Load test completed without incidents
- [ ] Production sync executed through explicit human gate
- [ ] Smoke tests passing in production
- [ ] SLO error budget healthy after cutover
- [ ] Team notified of successful cutover
- [ ] Postmortem scheduled

---

## Rollback Procedures

### Rollback Terraform

```bash
cd infra/terraform/envs/<env>
git revert <commit-hash>
terraform apply
```

### Rollback Kubernetes deployment

```bash
argocd app history nawex-<env>
argocd app rollback nawex-<env> <revision-id>
```

### Rollback a migrated workload to vSphere

1. Power on the source VM in vCenter
2. Route traffic back to the VM endpoint
3. Remove the containerized workload from the K8s overlay
4. Commit the removal and let Argo CD sync
5. Document the rollback in the postmortem

---

## Related Runbooks

- [runbooks/incident-response.md](incident-response.md)
- [runbooks/slack-alerting.md](slack-alerting.md)
- [runbooks/vm-to-k8s-migration.md](vm-to-k8s-migration.md)
- [runbooks/openshift-operations.md](openshift-operations.md)
- [runbooks/postmortem-template.md](postmortem-template.md)

---

*NAWEX Hybrid DevOps Platform - Built by Emmanuel Naweji*  
*github.com/Here2ServeU/nawex-hybrid-devops-platform*
