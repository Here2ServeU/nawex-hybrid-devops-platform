# Migration: vSphere VMs → EKS / AKS (Containerized)

End-to-end workflow for migrating on-prem VM workloads to **containerized**
deployments running on AWS EKS or Azure AKS (option 1 of the migration path).

```text
  on-prem vSphere                           cloud Kubernetes
  ───────────────                           ───────────────
  ┌───────────────┐   assess     ┌────────────────────────┐
  │  VMware VMs   │ ───────────► │ migration/assess       │  WorkloadProfile YAML
  │  (vCenter)    │              └──────────┬─────────────┘  (1 per VM)
  └───────────────┘                         │
                                            ▼
                              ┌────────────────────────┐
                              │ migration/containerize │  →  Dockerfile + K8s
                              └──────────┬─────────────┘     manifest per app
                                         │
                       ┌─────────────────┼─────────────────┐
                       ▼                                   ▼
           ┌─────────────────────┐              ┌─────────────────────┐
           │ k8s/overlays/       │              │ k8s/overlays/       │
           │    aws-eks/         │              │    azure-aks/       │
           └──────────┬──────────┘              └──────────┬──────────┘
                      │ Argo CD syncs                       │
                      ▼                                     ▼
              EKS cluster                            AKS cluster
           (nawex-migrated ns)                    (nawex-migrated ns)
```

## Layout

- [schemas/workload-profile.schema.json](schemas/workload-profile.schema.json) — JSON Schema
  for the `WorkloadProfile` custom spec consumed by the tools below.
- [samples/](samples/) — example `WorkloadProfile` YAMLs for legacy apps (Python, Java, Node).
- [assess/](assess/) — `vm_inventory.py` pulls VMs from vCenter (or reads a static JSON for
  offline demos) and writes a pre-filled `WorkloadProfile` stub per VM.
- [containerize/](containerize/) — `containerize.py` reads a `WorkloadProfile` YAML and emits
  a Dockerfile + a Kubernetes Deployment/Service/Kustomization under `out/<name>/`.
- [deploy/](deploy/) — Kustomize base for migrated workloads, layered with cluster-specific
  overlays at [k8s/overlays/aws-eks/](../k8s/overlays/aws-eks/) and
  [k8s/overlays/azure-aks/](../k8s/overlays/azure-aks/).

## Five-step migration path

```bash
# 1. Assess — inventory the source VMs and emit one WorkloadProfile stub per VM.
python migration/assess/vm_inventory.py \
  --vcenter vcenter.nawex.local \
  --out migration/profiles/

# 2. Review — humans edit each profile YAML (runtime, entrypoint, env, etc.).

# 3. Containerize — generate Dockerfile + K8s manifest per profile.
python migration/containerize/containerize.py \
  --profile migration/profiles/legacy-reporting-api.yaml \
  --out migration/containerize/out/

# 4. Build and push the images to your registry (GHCR/ECR/ACR).
docker build -t ghcr.io/nawex/legacy-reporting-api:1.0 \
  migration/containerize/out/legacy-reporting-api/
docker push ghcr.io/nawex/legacy-reporting-api:1.0

# 5. Deploy via GitOps — Argo CD picks up the overlay and syncs to EKS / AKS.
#    Target cluster is selected by the `spec.target.cluster` field in the profile,
#    which the containerize tool writes into the generated kustomization.yaml.
```

## What Option 1 commits you to

- **Containerize, don't lift-and-shift.** Any state kept on the VM filesystem must move
  to a PVC, object storage, or an external DB. The tool flags unclassified storage mounts.
- **Re-platform the runtime.** Binaries pinned to a specific kernel/libc/distro may need
  base image updates. The tool picks a Debian-slim or UBI base matching the VM's package set.
- **Re-wire secrets and service discovery.** Profiles replace hardcoded config with
  `env.valueFrom: secret:<path>` references that get translated to K8s Secret/CSI mounts.
- **Re-tune capacity.** CPU/memory come from VM observed usage, not from VM configuration,
  so the generated Deployment requests are typically 30-60% smaller than the source VM.

See the full procedure and rollback plan in
[runbooks/vm-to-k8s-migration.md](../runbooks/vm-to-k8s-migration.md).
