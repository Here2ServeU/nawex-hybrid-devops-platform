variable "cluster_name" {
  type    = string
  default = "nawex-ocp-bm"
}

variable "base_domain" {
  type        = string
  default     = "nawex.local"
  description = "DNS base domain. API resolves at api.<cluster>.<base>, apps at *.apps.<cluster>.<base>."
}

# ---------------------------------------------------------------------------
# Network topology
# ---------------------------------------------------------------------------
# Baremetal IPI wants two L2 networks:
#   - `baremetal`     — external/routable, carries API + ingress VIPs.
#   - `provisioning`  — isolated PXE/DHCP network used during initial install.
# Both must be bridged on every host by the installer.

variable "api_vip" {
  type    = string
  default = "192.168.70.5"
}

variable "ingress_vip" {
  type    = string
  default = "192.168.70.6"
}

variable "machine_network_cidr" {
  type    = string
  default = "192.168.70.0/24"
}

variable "cluster_network_cidr" {
  type    = string
  default = "10.128.0.0/14"
}

variable "service_network_cidr" {
  type    = string
  default = "172.30.0.0/16"
}

variable "provisioning_network_cidr" {
  type        = string
  default     = "172.22.0.0/24"
  description = "Isolated PXE/provisioning network. Not routed."
}

variable "provisioning_network_interface" {
  type        = string
  default     = "eno1"
  description = "NIC on every host that carries the provisioning VLAN."
}

variable "external_bridge" {
  type    = string
  default = "baremetal"
}

variable "provisioning_bridge" {
  type    = string
  default = "provisioning"
}

# ---------------------------------------------------------------------------
# Bare-metal host inventory
# ---------------------------------------------------------------------------
# Each host declares its vendor, its BMC (iDRAC / iLO / CIMC) endpoint, and
# the MAC address of the NIC attached to the provisioning network. The module
# renders the correct Redfish address scheme per vendor so the installer can
# power-cycle and virtual-media boot each node without human intervention.
#
# Supported `vendor` values: "dell" | "hpe" | "cisco"
#
# Example:
#   bm_hosts = [
#     {
#       name            = "master-0"
#       role            = "master"
#       vendor          = "dell"          # iDRAC 9
#       bmc_address     = "10.0.0.11"
#       bmc_system_id   = "System.Embedded.1"
#       boot_mac        = "aa:bb:cc:00:00:01"
#       root_device     = "/dev/nvme0n1"
#     },
#     {
#       name            = "master-1"
#       role            = "master"
#       vendor          = "hpe"           # iLO 5
#       bmc_address     = "10.0.0.12"
#       bmc_system_id   = "1"
#       boot_mac        = "aa:bb:cc:00:00:02"
#       root_device     = "/dev/sda"
#     },
#     {
#       name            = "worker-0"
#       role            = "worker"
#       vendor          = "cisco"         # UCS CIMC, standalone C-series
#       bmc_address     = "10.0.0.21"
#       bmc_system_id   = "1"
#       boot_mac        = "aa:bb:cc:00:01:00"
#       root_device     = "/dev/sda"
#     },
#   ]

variable "bm_hosts" {
  description = "Bare-metal host inventory for OpenShift IPI."
  type = list(object({
    name          = string
    role          = string
    vendor        = string
    bmc_address   = string
    bmc_system_id = string
    boot_mac      = string
    root_device   = string
  }))
  default = []

  validation {
    condition = alltrue([
      for h in var.bm_hosts : contains(["dell", "hpe", "cisco"], h.vendor)
    ])
    error_message = "Each bm_hosts[*].vendor must be one of: dell, hpe, cisco."
  }

  validation {
    condition = alltrue([
      for h in var.bm_hosts : contains(["master", "worker"], h.role)
    ])
    error_message = "Each bm_hosts[*].role must be one of: master, worker."
  }
}

variable "bmc_username" {
  type      = string
  sensitive = true
  default   = "admin"
}

variable "bmc_password" {
  type      = string
  sensitive = true
  default   = "REPLACE_ME"
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "control_plane_replicas" {
  type    = number
  default = 3
}

variable "worker_replicas" {
  type    = number
  default = 3
}

# ---------------------------------------------------------------------------
# Secrets required by openshift-install
# ---------------------------------------------------------------------------

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
