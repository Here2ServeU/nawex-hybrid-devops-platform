variable "environment" {
  type = string
}

variable "node_count" {
  type    = number
  default = 3
}

variable "instance_profile" {
  type    = string
  default = "standard-linux"
}
