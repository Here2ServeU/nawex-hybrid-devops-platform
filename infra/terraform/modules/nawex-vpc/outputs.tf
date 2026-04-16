output "name" {
  value = var.name
}

output "cidr_block" {
  value = var.cidr_block
}

output "tags" {
  value = local.normalized_tags
}
