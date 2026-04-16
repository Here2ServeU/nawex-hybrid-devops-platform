output "vm_names" {
  value = module.vsphere_nodes.vm_names
}

output "vm_ipv4" {
  value = module.vsphere_nodes.vm_ipv4
}

output "ansible_inventory_hint" {
  value = <<EOT
Write these hosts into infra/ansible/inventories/onprem/hosts.yml under vsphere_vms:
%{for idx, ip in module.vsphere_nodes.vm_ipv4~}
  ${module.vsphere_nodes.vm_names[idx]}:
    ansible_host: ${ip}
%{endfor~}
EOT
}
