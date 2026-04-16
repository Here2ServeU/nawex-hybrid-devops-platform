variable "name" {
  type        = string
  description = "Logical VPC name."
}

variable "cidr_block" {
  type        = string
  description = "CIDR block for the environment network."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tagging standard."
}
