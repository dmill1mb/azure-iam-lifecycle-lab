# The one and only server. Add a line here to add a server.
locals {
  vms = {
    dc01 = { name = "DC01", private_ip = var.dc01_private_ip }
  }
}
resource "azurerm_public_ip" "vm" {
  for_each = local.vms

  name                = "pip-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_network_interface" "vm" {
  for_each = local.vms

  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
    public_ip_address_id          = azurerm_public_ip.vm[each.key].id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  for_each = local.vms

  name                  = each.value.name
  computer_name         = each.value.name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.vm[each.key].id]

  # Hand patching to Azure Update Manager, on OUR schedule only.
  # Without all three, the maintenance window never patches.
  patch_mode                                             = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true
  patch_assessment_mode                                  = "AutomaticByPlatform"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}