module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "dev"
  owner       = "platform-team"
}

module "vpc" {
  source     = "../../modules/nawex-vpc"
  name       = "nawex-dev-vpc"
  cidr_block = "10.42.0.0/16"
  tags       = module.cost_tags.tags
}

module "compute" {
  source           = "../../modules/nawex-compute"
  environment      = "dev"
  node_count       = 3
  instance_profile = "ubuntu-k8s-worker"
}

module "cluster" {
  source       = "../../modules/nawex-k8s-cluster"
  cluster_name = "nawex-dev-cluster"
}

module "monitoring" {
  source         = "../../modules/nawex-monitoring"
  workspace_name = "nawex-dev-monitoring"
}
