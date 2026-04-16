# Self-managed OpenShift 4 on vSphere (IPI).
#
# Terraform's job here is threefold:
#   1. Size and render a compliant install-config.yaml for openshift-install.
#   2. Pre-create the DNS-reachable load balancer VIPs in the ordered IP space.
#   3. Produce a kick-off command block for the operator to run openshift-install.
#
# The actual cluster bring-up is handled by `openshift-install create cluster`,
# which in IPI mode provisions the VMs in vCenter itself. We do not clone VMs
# from Terraform here — that is the Option 2 workflow (lift-and-shift) and is
# out of scope.

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
}

module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "openshift-vsphere"
  owner       = "platform-team"
}

# We read vSphere metadata to echo it back into install-config.yaml — the
# openshift-install binary will use these exact names when it clones VMs.
data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "ds" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

locals {
  install_config = yamlencode({
    apiVersion = "v1"
    baseDomain = var.base_domain
    metadata   = { name = var.cluster_name }
    controlPlane = {
      name     = "master"
      replicas = 3
      platform = {
        vsphere = {
          cpus           = var.control_plane_cpus
          coresPerSocket = var.control_plane_cpus
          memoryMB       = var.control_plane_memory_mib
          osDisk         = { diskSizeGB = var.control_plane_disk_gib }
        }
      }
    }
    compute = [{
      name     = "worker"
      replicas = var.worker_replicas
      platform = {
        vsphere = {
          cpus           = var.worker_cpus
          coresPerSocket = var.worker_cpus
          memoryMB       = var.worker_memory_mib
          osDisk         = { diskSizeGB = var.worker_disk_gib }
        }
      }
    }]
    networking = {
      machineNetwork = [{ cidr = var.machine_network_cidr }]
      networkType    = "OVNKubernetes"
      clusterNetwork = [{ cidr = var.cluster_network_cidr, hostPrefix = 23 }]
      serviceNetwork = [var.service_network_cidr]
    }
    platform = {
      vsphere = {
        vcenter          = var.vsphere_server
        username         = var.vsphere_user
        password         = var.vsphere_password
        datacenter       = var.vsphere_datacenter
        defaultDatastore = var.vsphere_datastore
        cluster          = var.vsphere_compute_cluster
        network          = var.vsphere_network
        apiVIP           = var.api_vip
        ingressVIP       = var.ingress_vip
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
    # Run this to bring up the cluster

    ```bash
    cd ${path.module}/build
    openshift-install create cluster --dir . --log-level=info
    ```

    The installer will create VMs in datacenter `${var.vsphere_datacenter}` on
    cluster `${var.vsphere_compute_cluster}` using datastore
    `${var.vsphere_datastore}` and network `${var.vsphere_network}`.

    After ~40 minutes:

    ```bash
    export KUBECONFIG=${path.module}/build/auth/kubeconfig
    oc whoami
    oc get nodes
    ```

    Tear-down: `openshift-install destroy cluster --dir .`
  EOT
}
