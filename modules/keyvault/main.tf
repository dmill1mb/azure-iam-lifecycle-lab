data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_key_vault" "lab" {
  name                = "kv-aumlab-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# A new role assignment takes a moment to reach Key Vault. Without
# this wait, writing the secret can fail with "Forbidden" even though
# the assignment already exists.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.deployer_secrets_officer]
  create_duration = "30s"
}

resource "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.lab.id

  depends_on = [time_sleep.rbac_propagation]
}