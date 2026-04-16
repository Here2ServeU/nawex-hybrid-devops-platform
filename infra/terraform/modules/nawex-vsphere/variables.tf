variable "datacenter" {
  type        = string
  description = "vSphere datacenter name."
}

variable "compute_cluster" {
  type        = string
  description = "vSphere compute cluster name."
}

variable "datastore" {
  type        = string
  description = "Datastore where VM disks are created."
}

variable "network" {
  type        = string
  description = "Port group name for VM network interfaces."
}

variable "template_name" {
  type        = string
  description = "Linux VM template to clone from (e.g. ubuntu-22.04-template)."
}

variable "folder_path" {
  type        = string
  default     = "nawex"
  description = "VM folder path under the datacenter."
}

variable "name_prefix" {
  type    = string
  default = "nawex-onprem-node"
}

variable "node_count" {
  type    = number
  default = 3
}

variable "cpu_count" {
  type    = number
  default = 4
}

variable "memory_mib" {
  type    = number
  default = 8192
}

variable "disk_gib" {
  type    = number
  default = 80
}

variable "node_subnet_cidr" {
  type        = string
  description = "Subnet CIDR the cloned VMs land on (e.g. 192.168.50.0/24)."
  default     = "192.168.50.0/24"
}

variable "ipv4_offset" {
  type        = number
  default     = 10
  description = "First host offset for VM IP assignment inside the subnet."
}

variable "ipv4_gateway" {
  type    = string
  default = "192.168.50.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["192.168.50.1", "1.1.1.1"]
}

variable "dns_domain" {
  type    = string
  default = "nawex.local"
}

variable "tag_ids" {
  type        = list(string)
  default     = []
  description = "vSphere tag IDs to attach (pass cost-center / environment tags)."
}
