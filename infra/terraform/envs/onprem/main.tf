terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.11"
    }
  }
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
}

module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "onprem"
  owner       = "platform-team"
}

module "vsphere_nodes" {
  source = "../../modules/nawex-vsphere"

  datacenter       = var.vsphere_datacenter
  compute_cluster  = var.vsphere_compute_cluster
  datastore        = var.vsphere_datastore
  network          = var.vsphere_network
  template_name    = var.vsphere_template
  folder_path      = "nawex/onprem"
  name_prefix      = "nawex-onprem-node"
  node_count       = var.node_count
  node_subnet_cidr = var.node_subnet_cidr
  ipv4_offset      = var.ipv4_offset
  ipv4_gateway     = var.ipv4_gateway
  dns_servers      = var.dns_servers
  dns_domain       = var.dns_domain
}

module "compute" {
  source           = "../../modules/nawex-compute"
  environment      = "onprem"
  node_count       = var.node_count
  instance_profile = "vmware-linux-k8s-worker"
}

module "cluster" {
  source       = "../../modules/nawex-k8s-cluster"
  cluster_name = "nawex-onprem-cluster"
}

module "monitoring" {
  source         = "../../modules/nawex-monitoring"
  workspace_name = "nawex-onprem-monitoring"
}
