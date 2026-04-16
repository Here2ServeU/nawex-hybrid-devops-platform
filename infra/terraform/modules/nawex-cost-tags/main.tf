variable "environment" {
  type = string
}

variable "owner" {
  type = string
}

output "tags" {
  value = {
    project     = "nawex-hybrid-devops-platform"
    environment = var.environment
    owner       = var.owner
    cost_center = "platform-engineering"
  }
}
