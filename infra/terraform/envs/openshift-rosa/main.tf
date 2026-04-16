provider "aws" {
  region = var.region
  default_tags {
    tags = module.cost_tags.tags
  }
}

provider "rhcs" {
  token = var.ocm_token
  url   = var.ocm_url
}

module "cost_tags" {
  source      = "../../modules/nawex-cost-tags"
  environment = "openshift-rosa"
  owner       = "platform-team"
}

# ROSA Classic (STS) via the community Red Hat module. For HCP, swap to
# terraform-redhat/rosa-hcp/rhcs and re-point subnets.
module "rosa" {
  source  = "terraform-redhat/rosa-classic/rhcs"
  version = "~> 1.6"

  cluster_name           = var.cluster_name
  openshift_version      = var.openshift_version
  aws_availability_zones = var.azs
  replicas               = var.compute_replicas
  compute_machine_type   = var.compute_machine_type

  # Networking — either create a fresh VPC via the module, or pass pre-existing
  # private_subnet_ids / aws_subnet_ids for brownfield.
  create_vpc            = var.create_vpc
  installer_role_arn    = var.installer_role_arn
  support_role_arn      = var.support_role_arn
  controlplane_role_arn = var.controlplane_role_arn
  worker_role_arn       = var.worker_role_arn
  operator_role_properties = {
    # The module's helper accounts for the standard 6 operator roles.
    cluster_name = var.cluster_name
    path         = "/"
  }

  # Private API + public ingress is the usual production posture.
  private = var.private_api

  tags = module.cost_tags.tags
}
