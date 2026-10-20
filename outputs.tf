output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "key_vault_name" {
  value = module.keyvault.key_vault_name
}

output "public_ips" {
  value = module.compute.public_ips
}

