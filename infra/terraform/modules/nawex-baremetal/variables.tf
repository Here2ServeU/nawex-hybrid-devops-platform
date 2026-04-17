variable "bm_hosts" {
  description = <<-EOT
    Bare-metal host inventory for OpenShift IPI or any Redfish-driven installer.
    Each entry describes one physical server with its BMC endpoint, the NIC
    MAC attached to the provisioning network, and the target install disk.

    Supported vendors:
      - "dell"  → PowerEdge family, iDRAC 9+  (idrac-virtualmedia://)
      - "hpe"   → ProLiant family, iLO 5+     (ilo5-virtualmedia://)
      - "cisco" → UCS C-series standalone CIMC (redfish-virtualmedia://)
  EOT
  type = list(object({
    name          = string
    role          = string
    vendor        = string
    bmc_address   = string
    bmc_system_id = string
    boot_mac      = string
    root_device   = string
  }))

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
}

variable "bmc_password" {
  type      = string
  sensitive = true
}

variable "disable_bmc_tls_verification" {
  type        = bool
  default     = true
  description = "Skip BMC certificate verification. Set false once iDRAC/iLO/CIMC certs are replaced."
}
