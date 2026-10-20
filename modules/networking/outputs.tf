output "subnet_id" {
  description = "Handed to the compute module so each VM's network card knows where to plug in."
  value       = azurerm_subnet.lab.id
}