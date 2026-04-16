output "vm_names" {
  value = vsphere_virtual_machine.node[*].name
}

output "vm_ipv4" {
  value = [
    for i in range(var.node_count) : cidrhost(var.node_subnet_cidr, i + var.ipv4_offset)
  ]
}

output "vm_uuids" {
  value = vsphere_virtual_machine.node[*].uuid
}
