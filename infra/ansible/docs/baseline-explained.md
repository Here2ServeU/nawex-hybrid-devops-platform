# NAWEX Linux Baseline — Explained

## What this is

The Linux baseline (this directory, plus the sibling `roles/`, `scripts/`,
and `compliance/` directories under [infra/ansible/](../)) is the
**mandatory floor** every Linux host must meet before it can join a NAWEX
cluster, serve production traffic, or be presented for audit. Bare-metal
nodes (Cisco UCS / HPE ProLiant / Dell PowerEdge), vSphere VMs, and cloud
instances all receive the same baseline — that is what makes the hybrid
control plane work: one posture, many substrates.

If a host has not had this baseline applied, it is not a NAWEX host.

## What it covers

| Concern           | Role / script                                                                 | Enforces |
|-------------------|-------------------------------------------------------------------------------|----------|
| System            | [roles/system](../roles/system/)                                              | Packages, sysctl hardening, time sync (chrony) |
| Security          | [roles/security](../roles/security/), [scripts/harden.sh](../scripts/harden.sh) | SSH hardening, auditd + CIS-aligned rules |
| Observability     | [roles/observability](../roles/observability/), [scripts/install_monitoring.sh](../scripts/install_monitoring.sh) | node_exporter + sandboxed systemd unit |
| Container runtime | [roles/docker](../roles/docker/)                                              | Hardened Docker daemon (`no-new-privileges`, log rotation, `live-restore`, `icc=false`) |
| Compliance        | [compliance/cis-checklist.md](../compliance/cis-checklist.md), [compliance/audit-rules.conf](../compliance/audit-rules.conf) | CIS control mapping, auditd ruleset |
| Cost posture      | [scripts/cost_check.sh](../scripts/cost_check.sh)                             | Disk, log, and container drift signals |

## How it fits the rest of NAWEX

- **Entry-point playbook.** [playbooks/linux-baseline.yml](../playbooks/linux-baseline.yml) orchestrates the four roles against the `linux_nodes` group.
- **Layered playbooks build on top.** [playbooks/vsphere-join-cluster.yml](../playbooks/vsphere-join-cluster.yml) applies the baseline to `vsphere_vms` and then runs `kubeadm join`; [playbooks/baremetal-firmware-baseline.yml](../playbooks/baremetal-firmware-baseline.yml) handles the BMC / firmware preflight *before* the baseline even applies (hosts may not be powered on yet).
- **Feeds [observability/](../../../observability/).** The `node_exporter` installed by `roles/observability` is what Prometheus scrapes for host-level dashboards and SLO burn-rate math in `observability/alerts/`.
- **Feeds [finops-aiops/](../../../finops-aiops/).** `scripts/cost_check.sh` emits per-host cost-drift findings that the FinOps utilities aggregate fleet-wide.
- **Feeds [runbooks/](../../../runbooks/).** Compliance evidence (auditd streams, SSH config state) is what runbooks reference when responding to access-control or integrity incidents.

## Applying the baseline

### Fleet-wide (recommended)

```bash
ansible-playbook \
  -i infra/ansible/inventories/onprem/hosts.yml \
  infra/ansible/playbooks/linux-baseline.yml
```

Tag individual concerns for partial runs:

```bash
ansible-playbook infra/ansible/playbooks/linux-baseline.yml --tags security
```

### Single host, no Ansible

```bash
sudo ./infra/ansible/scripts/harden.sh
sudo ./infra/ansible/scripts/install_monitoring.sh
./infra/ansible/scripts/cost_check.sh
```

## Drift and evidence

- Ansible runs are idempotent — re-running the playbook is the canonical drift check. Any `changed` task indicates drift.
- `auditctl -l` must match [compliance/audit-rules.conf](../compliance/audit-rules.conf).
- `systemctl is-active node_exporter sshd auditd chrony docker` must return `active` for all five.
- `scripts/cost_check.sh` exits non-zero if any host exceeds its thresholds.

## Why baseline-as-code (and not a golden image)

Golden images drift, rot, and are hard to audit because the source of truth lives in a binary blob. NAWEX uses code because:

1. **Review.** Every control is a diff reviewed in Git.
2. **Multi-platform.** The same roles apply on Cisco UCS, HPE ProLiant, Dell PowerEdge, vSphere, AWS, and Azure — no per-platform AMI forest.
3. **Evidence.** The CIS checklist and auditd rules *are* the evidence; there is no "trust us, it's baked into the image."
4. **Reversibility.** Every change is a revert.
