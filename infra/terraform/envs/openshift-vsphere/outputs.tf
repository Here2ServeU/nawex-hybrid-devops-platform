output "install_config_path" {
  value = local_file.install_config.filename
}

output "install_runbook_path" {
  value = local_file.install_runbook.filename
}

output "api_fqdn" {
  value = "api.${var.cluster_name}.${var.base_domain}"
}

output "ingress_wildcard" {
  value = "*.apps.${var.cluster_name}.${var.base_domain}"
}

output "next_step" {
  value = "cd ${path.module}/build && openshift-install create cluster --dir . --log-level=info"
}
