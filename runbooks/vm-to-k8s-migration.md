# VM → Kubernetes Migration (Option 1: Containerized on EKS / AKS)

End-to-end procedure for moving a workload from an on-prem vSphere VM to a
container running on AWS EKS or Azure AKS. This is the **re-platforming** path:
we rebuild the workload as a container, we do not lift-and-shift the VM disk.

## Prerequisites

- vSphere credentials with read access to the source VMs (`VMWARE_USER`, `VMWARE_PASSWORD`).
- Target cluster provisioned:
  - EKS — `cd infra/terraform/envs/aws-eks && terraform apply`
  - AKS — `cd infra/terraform/envs/azure-aks && terraform apply`
- `kubectl` context pointing at the target cluster (`aws eks update-kubeconfig ...`
  or `az aks get-credentials ...`).
- Container registry with write access (ECR, ACR, or GHCR).

## Step 1 — Assess

Inventory the source VMs and generate a `WorkloadProfile` stub per VM.

```bash
# Live mode
export VMWARE_USER=svc-migrator VMWARE_PASSWORD='...'
python migration/assess/vm_inventory.py \
  --vcenter vcenter.nawex.local \
  --filter nawex \
  --out migration/profiles/

# Offline mode (reads the sample inventory fixture)
python migration/assess/vm_inventory.py \
  --from-json migration/assess/sample-inventory.json \
  --out migration/profiles/
```

Review every file under `migration/profiles/`. Fill in:

- `spec.runtime` — pick the closest match from the enum in the schema.
- `spec.entrypoint` — the exact command that starts the service on the VM today
  (check `/etc/systemd/system/*.service` or whatever supervisor you use).
- `spec.env` — use `valueFrom: secret:<name>/<key>` rather than copying plaintext.
- `spec.health.liveness` / `readiness` — add a real endpoint. If the app doesn't
  have one, add one first (we will not approve a container without probes).
- `spec.target.cluster` — `aws-eks`, `azure-aks`, or `onprem`.

## Step 2 — Containerize

```bash
python migration/containerize/containerize.py \
  --profile migration/profiles/legacy-reporting-api.yaml \
  --out migration/containerize/out/
```

Output:

```text
migration/containerize/out/legacy-reporting-api/
├── Dockerfile
├── deployment.yaml       # Deployment + Service, hardened (non-root, readOnlyRootFilesystem, PSA-restricted)
└── kustomization.yaml
```

## Step 3 — Build and push the image

```bash
APP=legacy-reporting-api
REGISTRY=<your-ecr-or-acr-or-ghcr>

# Copy the VM's application code/artifacts into migration/containerize/out/${APP}/
# (source tree, JAR, compiled bin, etc.) — the Dockerfile COPYs `.` into /app.

docker build -t "${REGISTRY}/${APP}:1.0" "migration/containerize/out/${APP}"
docker push "${REGISTRY}/${APP}:1.0"

# Update deployment.yaml: replace `REPLACE_ME/${APP}:1.0` with `${REGISTRY}/${APP}:1.0`.
sed -i.bak "s|REPLACE_ME|${REGISTRY}|g" "migration/containerize/out/${APP}/deployment.yaml"
```

## Step 4 — Deploy via GitOps

1. Commit `migration/containerize/out/<name>/` to the repo on a feature branch.
2. Add the app's `kustomization.yaml` to the right cluster overlay:
   - `k8s/overlays/aws-eks/kustomization.yaml` — add `../../migration/containerize/out/<name>` under `resources:`.
   - Or `k8s/overlays/azure-aks/kustomization.yaml` for AKS-targeted workloads.
3. Open a PR. CI validates Dockerfile (Hadolint), image (Trivy), manifests (kubeconform).
4. Merge. Argo CD picks up the new resources via:
   - [gitops/apps/aws-eks-platform.yaml](../gitops/apps/aws-eks-platform.yaml), or
   - [gitops/apps/azure-aks-platform.yaml](../gitops/apps/azure-aks-platform.yaml).

## Step 5 — Cutover

1. Verify pods healthy in the target cluster (`kubectl get pods -n nawex-migrated`).
2. Shift traffic — DNS, Route53 weighted record, or Front Door — gradually:
   10% → 50% → 100% over 24h, watching the SLO alerts in Slack.
3. Keep the source VM running for **7 days** with traffic drained, in case rollback
   is needed.

## Rollback

- DNS revert to the VM → immediate traffic cutback.
- Then `./scripts/incident_respond.sh approve <id>` against the `rollback_last_deploy`
  action to remove the migrated Deployment cleanly.
- Decommission the VM only after 7 days of clean operation on the new target.

## What the migration tool does NOT do

- Data migration (DBs, file shares). Use `pg_dump` / Azure Database Migration Service /
  AWS DMS / `rsync` as a separate workstream.
- Windows workloads. Option 1 is Linux-container only. Windows VMs need a separate
  decision (containerize on Windows nodes, or rehost via VMC / AVS).
- Anything that requires kernel modules, `CAP_SYS_ADMIN`, or host-network access.
  These workloads are better candidates for option 2 (lift-and-shift to EC2/Azure VM)
  and are not in scope for this path.
