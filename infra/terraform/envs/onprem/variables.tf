variable "vsphere_server" {
  type        = string
  description = "vCenter server FQDN or IP."
  default     = "vcenter.nawex.local"
}

variable "vsphere_user" {
  type        = string
  description = "vSphere user (prefer a service account)."
  sensitive   = true
  default     = "terraform@vsphere.local"
}

variable "vsphere_password" {
  type      = string
  sensitive = true
  default   = "REPLACE_ME"
}

variable "vsphere_allow_unverified_ssl" {
  type    = bool
  default = false
}

variable "vsphere_datacenter" {
  type    = string
  default = "nawex-dc"
}

variable "vsphere_compute_cluster" {
  type    = string
  default = "nawex-cluster"
}

variable "vsphere_datastore" {
  type    = string
  default = "nawex-nvme-ds"
}

variable "vsphere_network" {
  type    = string
  default = "nawex-lan"
}

variable "vsphere_template" {
  type        = string
  description = "Linux VM template (packer-built Ubuntu 22.04 or RHEL 9)."
  default     = "ubuntu-22.04-template"
}

variable "node_count" {
  type    = number
  default = 4
}

variable "node_subnet_cidr" {
  type    = string
  default = "192.168.50.0/24"
}

variable "ipv4_offset" {
  type    = number
  default = 10
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
