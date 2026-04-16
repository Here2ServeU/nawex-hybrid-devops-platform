# OpenShift Operations

OpenShift-specific conventions, day-2 procedures, and migration notes for the
NAWEX platform. Complements [k8s-troubleshooting.md](k8s-troubleshooting.md);
everything in that runbook still applies — this file covers the OCP delta.

## Cluster provisioning

| Path | Topology | When to use |
| --- | --- | --- |
| [infra/terraform/envs/openshift-rosa/](../infra/terraform/envs/openshift-rosa/) | Managed OpenShift on AWS (ROSA Classic, STS) | Cloud-only footprint, no on-prem responsibility |
| [infra/terraform/envs/openshift-vsphere/](../infra/terraform/envs/openshift-vsphere/) | Self-managed IPI on vSphere | Regulated/air-gapped, hardware sovereignty |

ROSA and the IPI installer both take ~40 minutes to stand up a cluster. Plan
maintenance windows around that.

## Authentication

```bash
# ROSA
rosa login --token="$RHCS_TOKEN"
rosa describe cluster --cluster nawex-rosa
oc login $(terraform -chdir=infra/terraform/envs/openshift-rosa output -raw api_url)

# Self-managed (vSphere IPI)
export KUBECONFIG=infra/terraform/envs/openshift-vsphere/build/auth/kubeconfig
oc whoami
```

## Conventions that differ from vanilla K8s

- **Ingress is `Route`, not `Ingress`.** Our overlay at
  [k8s/overlays/openshift/route.yaml](../k8s/overlays/openshift/route.yaml) uses
  edge-terminated TLS with an HTTP→HTTPS redirect. Switch to `reencrypt` or
  `passthrough` if the pod terminates TLS.
- **SCCs govern pod admission.** The default `restricted-v2` SCC ignores
  `runAsUser` and assigns an arbitrary UID. Our hardened base pins `uid=10001`,
  so we bind the `nawex-api` ServiceAccount to `nonroot-v2` in
  [scc-binding.yaml](../k8s/overlays/openshift/scc-binding.yaml). Do **not**
  escalate to `anyuid` — it strips almost every guardrail.
- **Pod Security Admission still applies.** The namespace is labeled
  `pod-security.kubernetes.io/enforce=restricted` in addition to the SCC
  binding; both checks must pass.
- **Projects vs Namespaces.** We ship a plain `Namespace`; OpenShift wraps it
  with project metadata automatically. `openshift.io/display-name` and
  `openshift.io/description` annotations control how it appears in the console.

## Argo CD

Argo CD runs the same as any other target; the AppProject's
`namespaceResourceWhitelist` has been extended with `route.openshift.io/Route`
and `rbac.authorization.k8s.io/RoleBinding` so syncs succeed.

If you install the **GitOps Operator** instead of vanilla Argo CD, point the
operator's `ApplicationSet` at `gitops/apps/` — the manifests are compatible.

## Migration (VM → OpenShift)

Same five-step flow as EKS/AKS (see [vm-to-k8s-migration.md](vm-to-k8s-migration.md)).
The differences are picked up automatically from the WorkloadProfile:

```yaml
spec:
  target:
    cluster: openshift
    expose_externally: true      # emits a Route
    tls_termination: edge        # or reencrypt / passthrough
```

`migration/containerize/containerize.py` will:

1. Generate the same hardened Dockerfile and Deployment as other targets.
2. Emit a `Route` alongside the `Service` when `expose_externally: true`.
3. Skip the Route entirely when the workload stays cluster-internal (default).

## Troubleshooting the SCC path

If a migrated pod CrashLoops with `pods "..." is forbidden: unable to validate
against any security context constraint`:

1. `oc describe pod -n nawex-migrated <pod>` — look for the SCC denial reason.
2. `oc get sa -n nawex-migrated nawex-api -o yaml` — confirm it exists.
3. `oc get rolebinding -n nawex-migrated nawex-api-nonroot-scc -o yaml` —
   confirm the binding to `system:openshift:scc:nonroot-v2`.
4. `oc adm policy who-can use scc nonroot-v2 -n nawex-migrated` should list the
   ServiceAccount.

Do **not** grant the binding to `default` or to the whole namespace — scope it
to the workload's dedicated ServiceAccount.

## Day-2 upgrades

- ROSA: `rosa upgrade cluster --cluster nawex-rosa --version 4.17.X`.
- Self-managed: the cluster's `ClusterVersion` channel (`stable-4.17` by
  default) drives `oc adm upgrade` flows. Always check compatibility with any
  Operator your team has installed.
