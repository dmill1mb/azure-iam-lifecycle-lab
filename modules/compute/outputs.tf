# A map like { dc01 = "/subscriptions/.../DC01", ws01 = ..., ws02 = ... }
# The update-manager module uses it to link each VM to the patch window.
output "vm_ids" {
  value = { for k, vm in azurerm_windows_virtual_machine.vm : k => vm.id }
}

output "public_ips" {
  value = { for k, pip in azurerm_public_ip.vm : k => pip.ip_address }
}