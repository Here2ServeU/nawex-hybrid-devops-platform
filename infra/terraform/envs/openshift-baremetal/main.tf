# Self-managed OpenShift 4 on bare metal (IPI).
#
# The install-config is platform: baremetal. openshift-install drives
# provisioning over Redfish against each host's BMC (iDRAC / iLO / CIMC) and
# boots CoreOS via virtual media. Terraform's job here is to:
#
#   1. Translate the vendor-agnostic bm_hosts list into correct per-vendor
#      Redfish virtual-media URLs.
#   2. Render install-config.yaml with the full baremetal platform block,
#      including api/ingress VIPs, provisioning network, and the host list.
#   3. Emit a runbook the operator executes to create the cluster.
#
# The actual install is performed by `openshift-install create cluster`,
# which runs the bootstrap VM on the provisioner host and hands off to the
# bare-metal control plane.

module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "openshift-baremetal"
  owner       = "platform-team"
}

locals {
  # Redfish virtual-media URL scheme per vendor. The installer uses this URL
  # to mount the CoreOS ISO and power-cycle the host.
  #
  #   Dell iDRAC 9+      : idrac-virtualmedia://<bmc>/redfish/v1/Systems/System.Embedded.1
  #   HPE iLO 5+         : ilo5-virtualmedia://<bmc>/redfish/v1/Systems/1
  #   Cisco UCS CIMC     : redfish-virtualmedia://<bmc>/redfish/v1/Systems/1
  bmc_url_scheme = {
    dell  = "idrac-virtualmedia"
    hpe   = "ilo5-virtualmedia"
    cisco = "redfish-virtualmedia"
  }

  hosts_rendered = [
    for h in var.bm_hosts : {
      name            = h.name
      role            = h.role
      bootMACAddress  = h.boot_mac
      rootDeviceHints = { deviceName = h.root_device }
      bmc = {
        address         = "${local.bmc_url_scheme[h.vendor]}://${h.bmc_address}/redfish/v1/Systems/${h.bmc_system_id}"
        username        = var.bmc_username
        password        = var.bmc_password
        disableCertificateVerification = true
      }
    }
  ]

  install_config = yamlencode({
    apiVersion = "v1"
    baseDomain = var.base_domain
    metadata   = { name = var.cluster_name }
    controlPlane = {
      name     = "master"
      replicas = var.control_plane_replicas
    }
    compute = [{
      name     = "worker"
      replicas = var.worker_replicas
    }]
    networking = {
      machineNetwork = [{ cidr = var.machine_network_cidr }]
      networkType    = "OVNKubernetes"
      clusterNetwork = [{ cidr = var.cluster_network_cidr, hostPrefix = 23 }]
      serviceNetwork = [var.service_network_cidr]
    }
    platform = {
      baremetal = {
        apiVIPs                      = [var.api_vip]
        ingressVIPs                  = [var.ingress_vip]
        provisioningNetwork          = "Managed"
        provisioningNetworkCIDR      = var.provisioning_network_cidr
        provisioningNetworkInterface = var.provisioning_network_interface
        externalBridge               = var.external_bridge
        provisioningBridge           = var.provisioning_bridge
        hosts                        = local.hosts_rendered
      }
    }
    pullSecret = var.pull_secret
    sshKey     = var.ssh_public_key
  })
}

resource "local_file" "install_config" {
  filename        = "${path.module}/build/install-config.yaml"
  file_permission = "0600"
  content         = local.install_config
}

resource "local_file" "install_runbook" {
  filename        = "${path.module}/build/INSTALL.md"
  file_permission = "0644"
  content         = <<-EOT
    # Bring up NAWEX OpenShift on bare metal

    Hosts in this cluster:
    ${join("\n", [for h in var.bm_hosts : "    - ${h.role}/${h.name} — vendor=${h.vendor} bmc=${h.bmc_address} mac=${h.boot_mac}"])}

    1. Confirm every BMC is reachable from the provisioner host:

       ```bash
       for h in ${join(" ", [for h in var.bm_hosts : h.bmc_address])}; do
         curl -ks -o /dev/null -w "%%{http_code}\n" https://$h/redfish/v1/
       done
       ```

    2. Confirm DNS:
         api.${var.cluster_name}.${var.base_domain}   → ${var.api_vip}
         *.apps.${var.cluster_name}.${var.base_domain} → ${var.ingress_vip}

    3. Run the installer:

       ```bash
       cd ${path.module}/build
       openshift-install create cluster --dir . --log-level=info
       ```

    4. After ~60 minutes:

       ```bash
       export KUBECONFIG=${path.module}/build/auth/kubeconfig
       oc whoami
       oc get nodes -o wide
       oc get clusteroperators
       ```

    Tear-down: `openshift-install destroy cluster --dir .`
  EOT
}
