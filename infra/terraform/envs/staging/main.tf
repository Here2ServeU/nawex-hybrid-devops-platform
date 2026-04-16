terraform {
  required_version = ">= 1.7.0"
}

module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "staging"
  owner       = "platform-team"
}

module "vpc" {
  source     = "../../modules/nawex-vpc"
  name       = "nawex-staging-vpc"
  cidr_block = "10.52.0.0/16"
  tags       = module.cost_tags.tags
}

module "compute" {
  source           = "../../modules/nawex-compute"
  environment      = "staging"
  node_count       = 3
  instance_profile = "ubuntu-k8s-worker"
}

module "cluster" {
  source       = "../../modules/nawex-k8s-cluster"
  cluster_name = "nawex-staging-cluster"
}

module "monitoring" {
  source         = "../../modules/nawex-monitoring"
  workspace_name = "nawex-staging-monitoring"
}
