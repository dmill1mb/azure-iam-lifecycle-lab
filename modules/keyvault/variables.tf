variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}