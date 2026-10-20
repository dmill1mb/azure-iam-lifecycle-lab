# Same storage account as Labs 1 and 2 - its own key, its own state file.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstatelabs363689"
    container_name       = "tfstate"
    key                  = "iam-lab.tfstate"
  }
}