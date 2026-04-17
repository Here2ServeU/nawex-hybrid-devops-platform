output "hosts" {
  description = "Host entries ready to drop into install-config.platform.baremetal.hosts."
  value       = local.hosts_rendered
}

output "host_count_by_vendor" {
  description = "Number of hosts in the cluster, broken down by hardware vendor."
  value       = local.host_count_by_vendor
}

output "summary" {
  description = "One-line summary per host, useful for runbooks and logs."
  value = [
    for h in var.bm_hosts :
    "${h.role}/${h.name} — vendor=${h.vendor} bmc=${h.bmc_address} mac=${h.boot_mac} disk=${h.root_device}"
  ]
}
