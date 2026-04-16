module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "onprem"
  owner       = "platform-team"
}

module "compute" {
  source           = "../../modules/nawex-compute"
  environment      = "onprem"
  node_count       = 4
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
