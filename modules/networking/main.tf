resource "azurerm_virtual_network" "lab" {
  name                = "vnet-aumlab"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.0.0.0/16"]

  # Every VM in this network uses DC01 for DNS. Without this,
  # WS01 and WS02 can't find the domain to join it.
  dns_servers = [var.dc01_private_ip]
}

resource "azurerm_subnet" "lab" {
  name                 = "snet-aumlab"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "lab" {
  name                = "nsg-aumlab"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-RDP-From-Me"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.allowed_rdp_source_ip
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}