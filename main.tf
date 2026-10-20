resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
}

module "networking" {
  source                = "./modules/networking"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  allowed_rdp_source_ip = var.allowed_rdp_source_ip
  dc01_private_ip       = var.dc01_private_ip
}

module "keyvault" {
  source              = "./modules/keyvault"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  admin_password      = var.admin_password
}

module "compute" {
  source              = "./modules/compute"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  subnet_id           = module.networking.subnet_id
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  dc01_private_ip     = var.dc01_private_ip
}