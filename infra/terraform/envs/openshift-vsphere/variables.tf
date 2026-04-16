variable "cluster_name" {
  type    = string
  default = "nawex-ocp"
}

variable "base_domain" {
  type        = string
  default     = "nawex.local"
  description = "DNS base domain — API/Ingress will resolve at api.<cluster>.<base> and *.apps.<cluster>.<base>."
}

# vSphere connection
variable "vsphere_server" {
  type    = string
  default = "vcenter.nawex.local"
}

variable "vsphere_user" {
  type      = string
  sensitive = true
  default   = "terraform@vsphere.local"
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

# VIPs must live inside machine_network_cidr and be reachable by DHCP/DNS.
variable "api_vip" {
  type    = string
  default = "192.168.60.5"
}

variable "ingress_vip" {
  type    = string
  default = "192.168.60.6"
}

variable "machine_network_cidr" {
  type    = string
  default = "192.168.60.0/24"
}

variable "cluster_network_cidr" {
  type    = string
  default = "10.128.0.0/14"
}

variable "service_network_cidr" {
  type    = string
  default = "172.30.0.0/16"
}

# Capacity
variable "control_plane_cpus" {
  type    = number
  default = 4
}

variable "control_plane_memory_mib" {
  type    = number
  default = 16384
}

variable "control_plane_disk_gib" {
  type    = number
  default = 120
}

variable "worker_replicas" {
  type    = number
  default = 3
}

variable "worker_cpus" {
  type    = number
  default = 4
}

variable "worker_memory_mib" {
  type    = number
  default = 16384
}

variable "worker_disk_gib" {
  type    = number
  default = 120
}

# Secrets required by openshift-install
variable "pull_secret" {
  type        = string
  sensitive   = true
  description = "Pull secret JSON from https://console.redhat.com/openshift/install/pull-secret"
  default     = "{\"auths\":{}}"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key burned into the CoreOS ignition for core@<node> access."
  default     = ""
}
