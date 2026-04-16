variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "nawex-aks-rg"
}

variable "cluster_name" {
  type    = string
  default = "nawex-aks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "private_cluster_enabled" {
  type    = bool
  default = true
}

variable "vnet_cidr" {
  type    = string
  default = "10.90.0.0/16"
}

variable "nodes_subnet_cidr" {
  type    = string
  default = "10.90.1.0/24"
}

variable "system_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "system_node_count" {
  type    = number
  default = 2
}

variable "workload_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "workload_min_count" {
  type    = number
  default = 2
}

variable "workload_max_count" {
  type    = number
  default = 6
}
