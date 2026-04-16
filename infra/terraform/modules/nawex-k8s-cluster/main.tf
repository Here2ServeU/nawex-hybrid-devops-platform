variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

output "cluster_name" {
  value = var.cluster_name
}

output "kubernetes_version" {
  value = var.kubernetes_version
}
