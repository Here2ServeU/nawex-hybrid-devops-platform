variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ocm_token" {
  type        = string
  description = "OpenShift Cluster Manager (OCM) API token. Export RHCS_TOKEN or pass here."
  sensitive   = true
  default     = ""
}

variable "ocm_url" {
  type        = string
  default     = "https://api.openshift.com"
  description = "OCM endpoint. Use https://api.stage.openshift.com for staging."
}

variable "cluster_name" {
  type    = string
  default = "nawex-rosa"
}

variable "openshift_version" {
  type    = string
  default = "4.17.0"
}

variable "compute_replicas" {
  type    = number
  default = 3
}

variable "compute_machine_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "create_vpc" {
  type    = bool
  default = true
}

variable "private_api" {
  type        = bool
  default     = false
  description = "Set true to make the API endpoint private (requires VPN/TGW reach)."
}

# IAM role ARNs created by `rosa create account-roles` out-of-band. The module
# accepts either explicit ARNs (below) or auto-creation via `create_account_roles`.
variable "installer_role_arn" {
  type    = string
  default = ""
}

variable "support_role_arn" {
  type    = string
  default = ""
}

variable "controlplane_role_arn" {
  type    = string
  default = ""
}

variable "worker_role_arn" {
  type    = string
  default = ""
}
