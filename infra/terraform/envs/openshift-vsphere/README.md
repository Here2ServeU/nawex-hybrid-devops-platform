# Self-managed OpenShift 4 on vSphere (IPI)

Terraform's role is to render a compliant `install-config.yaml` and print the
openshift-install command. IPI (installer-provisioned infrastructure) mode has
openshift-install clone the CoreOS template in vCenter itself, so we do not
clone VMs from Terraform.

## Prerequisites

1. vCenter credentials with full permissions in the target datacenter.
2. DNS entries for the API VIP and `*.apps.<cluster>.<base>` pointing at the
   ingress VIP. (Most sites run a dedicated internal DNS zone per cluster.)
3. A DHCP pool inside `machine_network_cidr` large enough for control-plane +
   workers + VIPs.
4. `openshift-install` binary matching `openshift_version` and a
   [pull secret](https://console.redhat.com/openshift/install/pull-secret).
5. A CoreOS OVA template uploaded to vCenter (openshift-install will import
   automatically if absent, but pre-importing speeds things up).

## Apply

```bash
terraform apply \
  -var "pull_secret=$(cat ~/pull-secret.json | jq -c .)" \
  -var "ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"

# Follow the printed next_step:
cd build/
openshift-install create cluster --dir . --log-level=info

export KUBECONFIG=$PWD/auth/kubeconfig
oc whoami
```

The `build/` directory contains rendered secrets and is gitignored.
