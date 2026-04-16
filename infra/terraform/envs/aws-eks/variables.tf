variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "nawex-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "cluster_endpoint_public_access" {
  type        = bool
  default     = false
  description = "Set true only for demo environments — prefer private + VPN/SSO."
}

variable "vpc_cidr" {
  type    = string
  default = "10.80.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.80.1.0/24", "10.80.2.0/24", "10.80.3.0/24"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.80.101.0/24", "10.80.102.0/24", "10.80.103.0/24"]
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "node_desired_size" {
  type    = number
  default = 3
}
