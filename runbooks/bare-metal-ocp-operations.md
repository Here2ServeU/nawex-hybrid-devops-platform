# Bare-Metal OpenShift Operations Runbook

Operational procedures for OpenShift Container Platform (OCP) running on
mixed-vendor bare metal: **Cisco UCS, HPE ProLiant, Dell PowerEdge**.

This runbook is the hands-on companion to the bare-metal bring-up handled by
[`infra/ansible/playbooks/baremetal-bmc.yml`](../infra/ansible/playbooks/baremetal-bmc.yml)
and the `baremetal-bmc` role. It assumes OCP 4.14+ with IPI installation.

---

## Scope

| Task | When to run | Risk |
|---|---|---|
| PXE / iPXE boot validation | New rack, firmware upgrade, install re-run | Low |
| BMC access (iDRAC / iLO / CIMC) | Node unreachable, console required | Low |
| IPI installation on bare metal | Cluster bring-up, rebuild | High — destructive on targets |
| Node replacement | Hardware failure, preventative refresh | Medium — workload drain first |
| Firmware baseline validation | Before each install, quarterly fleet sweep | Low |

---

## 1. Pre-flight — firmware and BMC baseline

Firmware drift across a mixed Cisco/HPE/Dell fleet is the single most common
cause of IPI failures. The BMC must expose Redfish and virtual media before the
installer runs.

```bash
# Validate BMC reachability + firmware floor on the whole fleet.
ansible-playbook -i infra/ansible/inventories/onprem/hosts.ini \
    infra/ansible/playbooks/baremetal-bmc.yml
```

Minimum firmware floors (raise as vendors publish security fixes):

| Vendor | BMC | Minimum | Redfish endpoint |
|---|---|---|---|
| Dell | iDRAC 9 | 6.10.30.00 | `/redfish/v1/Systems/System.Embedded.1` |
| HPE | iLO 5 | 2.90 | `/redfish/v1/Systems/1` |
| Cisco | CIMC (UCS C-Series) | 4.3(2.230270) | `/redfish/v1/Systems/WZP...` |

If the playbook reports a node below floor — **do not proceed with install**.
Upgrade via the vendor's out-of-band tooling (iDRAC Lifecycle Controller, HPE SUM, Cisco HUU).

---

## 2. BMC console access

### Dell iDRAC 9

```bash
# SSH (requires iDRAC Enterprise license for console redirect).
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 root@<idrac-ip>
# Launch virtual console via racadm.
racadm remoteimage -c -l http://<boot-server>/discovery.iso -u user -p pass
```

### HPE iLO 5

```bash
# SSH to iLO.
ssh Administrator@<ilo-ip>
# Power control from the iLO CLI.
> power on
> vsp                     # virtual serial port
```

### Cisco CIMC (UCS C-Series)

```bash
ssh admin@<cimc-ip>
# Scope into virtual media + KVM.
scope vmedia
map-www http <boot-server>/discovery.iso
```

---

## 3. IPI installation on bare metal

Prerequisites — **verify before starting** (installer won't tell you clearly when these are wrong):

- [ ] Provisioning network is L2-isolated and DHCP-controlled by the installer
- [ ] Each node's BMC is reachable from the bootstrap VM
- [ ] DNS records resolve: `api.<cluster>.<base-domain>`, `*.apps.<cluster>.<base-domain>`
- [ ] Pull secret from `console.redhat.com` is current
- [ ] `openshift-install` binary matches the target OCP version exactly

```bash
# 1. Generate install-config.yaml from platform template.
cp infra/openshift/baremetal/install-config.template.yaml \
   /var/tmp/ocp-install/install-config.yaml
# Fill in cluster name, base domain, pull secret, SSH key, node BMC URLs.

# 2. Back up install-config BEFORE running the installer (it is consumed).
cp /var/tmp/ocp-install/install-config.yaml /var/tmp/ocp-install/install-config.yaml.bak

# 3. Run the installer.
openshift-install --dir=/var/tmp/ocp-install create cluster --log-level=info
```

Typical bare-metal install time: **45-90 minutes**. Progress through bootstrap → control plane → worker join is visible in `.openshift_install.log`.

If install fails past the bootstrap phase, do not re-run from scratch — gather:

```bash
openshift-install --dir=/var/tmp/ocp-install gather bootstrap
```

and escalate with the gathered tarball.

---

## 4. Node replacement

When a worker node fails hardware (PSU, DIMM ECC exhaustion, NIC fault):

```bash
# 1. Cordon and drain the failing node.
oc adm cordon <node>
oc adm drain <node> --ignore-daemonsets --delete-emptydir-data --force --grace-period=60

# 2. Remove from cluster.
oc delete node <node>

# 3. Remove the BareMetalHost object so the Machine API stops reconciling to it.
oc -n openshift-machine-api delete baremetalhost <node>

# 4. Physical replacement → re-apply BMC baseline to the new chassis.
ansible-playbook -i infra/ansible/inventories/onprem/hosts.ini \
    infra/ansible/playbooks/baremetal-bmc.yml --limit <node>

# 5. Re-create the BareMetalHost + Machine objects.
oc apply -f infra/openshift/baremetal/hosts/<node>.yaml
```

The Machine API will PXE-provision and join the new node automatically if the
BMC baseline is clean. Expect **20-40 minutes** from `oc apply` to `Ready`.

---

## 5. Common failure modes

| Symptom | Likely cause | First check |
|---|---|---|
| `bootstrap: Failed to start container` | Image pull blocked | Outbound proxy, pull secret |
| Node stuck `Provisioning` | BMC unreachable mid-install | `curl -u user:pass https://<bmc>/redfish/v1/` |
| `x509: certificate signed by unknown authority` | Cluster CA rotated, kubeconfig stale | Re-fetch kubeconfig from install dir |
| Workers join but stay `NotReady` | CNI not healthy / MTU mismatch | `oc get pods -n openshift-sdn` or `openshift-ovn-kubernetes` |
| IPI install timeout at 95% | DNS wildcard `*.apps` missing | Resolve `*.apps.<cluster>.<base>` externally |

---

## References

- [openshift-install bare-metal IPI](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal_ipi/ipi-install-overview.html)
- [Red Hat Metal³ project](https://metal3.io/)
- Platform Ansible role: [`infra/ansible/roles/baremetal-bmc/`](../infra/ansible/roles/baremetal-bmc/)
- Playbook: [`infra/ansible/playbooks/baremetal-bmc.yml`](../infra/ansible/playbooks/baremetal-bmc.yml)
- General OpenShift ops: [`runbooks/openshift-operations.md`](openshift-operations.md)
