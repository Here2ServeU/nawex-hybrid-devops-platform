# nawex-baremetal — shared Redfish host-rendering module.
#
# Turns a vendor-agnostic bm_hosts list into the exact structure expected
# by OpenShift's platform: baremetal install-config. Any env that drives
# bare-metal installs over Redfish (OpenShift IPI, Metal3, Ironic) can
# consume the rendered list.

locals {
  # Redfish virtual-media URL scheme per vendor. Chosen from the set of
  # ironic/metal3 drivers OpenShift supports out of the box.
  bmc_url_scheme = {
    dell  = "idrac-virtualmedia"
    hpe   = "ilo5-virtualmedia"
    cisco = "redfish-virtualmedia"
  }

  hosts_rendered = [
    for h in var.bm_hosts : {
      name            = h.name
      role            = h.role
      bootMACAddress  = h.boot_mac
      rootDeviceHints = { deviceName = h.root_device }
      bmc = {
        address                        = "${local.bmc_url_scheme[h.vendor]}://${h.bmc_address}/redfish/v1/Systems/${h.bmc_system_id}"
        username                       = var.bmc_username
        password                       = var.bmc_password
        disableCertificateVerification = var.disable_bmc_tls_verification
      }
    }
  ]

  host_count_by_vendor = {
    for v in ["dell", "hpe", "cisco"] :
    v => length([for h in var.bm_hosts : h if h.vendor == v])
  }
}
