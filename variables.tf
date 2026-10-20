variable "location" {
  description = "Region for every resource. South Central US had free vCPU quota when this lab was built."
  type        = string
  default     = "southcentralus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-iamlab"
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "admin_password" {
  description = "VM admin password. Set via $env:TF_VAR_admin_password - never in a file."
  type        = string
  sensitive   = true
}

variable "allowed_rdp_source_ip" {
  description = "Your public IP - the only address the NSG lets in on RDP."
  type        = string
}

variable "vm_size" {
  description = "Standard_D2_v4 = 2 vCPUs each, 6 total. Counts against the Dv4 family quota."
  type        = string
  default     = "Standard_D2_v4"
}

variable "dc01_private_ip" {
  description = "Static IP for DC01. The VNet hands this out as the DNS server."
  type        = string
  default     = "10.0.1.4"
}

variable "maintenance_start" {
  description = "First patch window, format 'YYYY-MM-DD hh:mm'. Must be in the future or the apply fails."
  type        = string
}

variable "maintenance_time_zone" {
  type    = string
  default = "Central Standard Time"
}

variable "maintenance_recurrence" {
  description = "How often the window repeats, e.g. 'Week Sunday'."
  type        = string
  default     = "Week Sunday"
}
