output "cluster_name" {
  value = module.rosa.cluster_name
}

output "api_url" {
  value = module.rosa.api_url
}

output "console_url" {
  value = module.rosa.console_url
}

output "kubeconfig_command" {
  value = "rosa describe cluster --cluster ${module.rosa.cluster_name} && oc login ${module.rosa.api_url}"
}
