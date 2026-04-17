# Self-managed OpenShift 4 on bare metal (IPI)

Runs OpenShift directly on physical servers — no hypervisor. Supports the
three enterprise server families commonly used in regulated data centers:

| Vendor | Platform examples        | BMC     | Redfish scheme           |
|--------|--------------------------|---------|--------------------------|
| Dell   | PowerEdge R650 / R750    | iDRAC 9 | `idrac-virtualmedia://`  |
| HPE    | ProLiant DL360 / DL380   | iLO 5   | `ilo5-virtualmedia://`   |
| Cisco  | UCS C220 / C240 M6 (stand-alone CIMC) | CIMC | `redfish-virtualmedia://` |

Terraform renders a compliant baremetal-platform `install-config.yaml` and
emits the runbook. `openshift-install` then drives provisioning over Redfish,
mounts the CoreOS ISO via virtual media on each host, and installs the OS
on the `rootDeviceHints` disk.

## When to use this over `openshift-vsphere`

- **Performance / latency.** No hypervisor tax. Good for storage-heavy
  workloads, GPU nodes, RDMA/SR-IOV, or real-time scheduling.
- **Compliance.** Some regulated deployments require direct hardware
  attestation and TPM sealing, which is simplest when OpenShift owns the
  metal.
- **Existing fleet.** Data centers with Cisco UCS, HPE ProLiant, or Dell
  PowerEdge already racked.

## Prerequisites

1. **Network.** Two L2 networks reachable by every host:
   - `baremetal` — routable, carries API VIP + ingress VIP.
   - `provisioning` — isolated PXE/DHCP, used during install.
2. **BMC connectivity.** iDRAC / iLO / CIMC reachable from the provisioner
   host. Redfish enabled, virtual media enabled, Secure Boot set
   consistently (on or off — not mixed).
3. **BMC credentials** with rights to power-control and mount virtual
   media.
4. **Firmware baseline.** iDRAC / iLO / CIMC firmware at a release that
   exposes the Redfish endpoints the installer expects. See the Red Hat
   baremetal install guide for the current matrix.
5. **DNS.** `api.<cluster>.<base>` → API VIP, `*.apps.<cluster>.<base>` →
   ingress VIP.
6. **Pull secret** from https://console.redhat.com/openshift/install/pull-secret.
7. A provisioner host (RHEL/Fedora) with `openshift-install` and `podman`.

## Apply

```bash
terraform apply \
  -var "pull_secret=$(cat ~/pull-secret.json | jq -c .)" \
  -var "ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var 'bm_hosts=[
    {name="master-0",role="master",vendor="dell", bmc_address="10.0.0.11",bmc_system_id="System.Embedded.1",boot_mac="aa:bb:cc:00:00:01",root_device="/dev/nvme0n1"},
    {name="master-1",role="master",vendor="hpe",  bmc_address="10.0.0.12",bmc_system_id="1",boot_mac="aa:bb:cc:00:00:02",root_device="/dev/sda"},
    {name="master-2",role="master",vendor="cisco",bmc_address="10.0.0.13",bmc_system_id="1",boot_mac="aa:bb:cc:00:00:03",root_device="/dev/sda"},
    {name="worker-0",role="worker",vendor="dell", bmc_address="10.0.0.21",bmc_system_id="System.Embedded.1",boot_mac="aa:bb:cc:00:01:00",root_device="/dev/nvme0n1"},
    {name="worker-1",role="worker",vendor="hpe",  bmc_address="10.0.0.22",bmc_system_id="1",boot_mac="aa:bb:cc:00:01:01",root_device="/dev/sda"},
    {name="worker-2",role="worker",vendor="cisco",bmc_address="10.0.0.23",bmc_system_id="1",boot_mac="aa:bb:cc:00:01:02",root_device="/dev/sda"}
  ]'

# Follow the printed next_step:
cd build/
openshift-install create cluster --dir . --log-level=info

export KUBECONFIG=$PWD/auth/kubeconfig
oc whoami
oc get nodes -o wide
```

The `build/` directory contains rendered secrets and is gitignored.

## Notes

- **`disableCertificateVerification: true`** is set on the BMC block because
  most factory BMCs ship with self-signed certs. In production, replace the
  BMC certs (Dell: via iDRAC Lifecycle Controller; HPE: via iLO; Cisco: via
  CIMC) and flip this to `false`.
- **Mixed vendors in one cluster are supported** — OpenShift does not care
  as long as each host can be driven over Redfish. The module generates the
  correct URL scheme per `vendor` field.
- **Root device hints** matter. On Dell NVMe platforms use `/dev/nvme0n1`;
  on HPE/Cisco SAS controllers use `/dev/sda`. Mis-hinting leads to CoreOS
  installing onto the wrong disk.
- **Firmware drift** is the single most common source of baremetal install
  failure. Keep iDRAC/iLO/CIMC firmware in sync across the fleet before
  running the installer. See the firmware baseline playbook under
  [infra/ansible/inventories/baremetal/](../../../ansible/inventories/baremetal/).
