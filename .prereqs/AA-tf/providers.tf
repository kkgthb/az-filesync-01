# Configure the AzureRM provider
provider "azurerm" {
  features {}
  alias                           = "demo"
  tenant_id                       = var.entra_tenant_id
  subscription_id                 = var.az_sub_id
  resource_provider_registrations = "none"
}

# Configure the AzureAPI provider
provider "azapi" {
  alias           = "demo"
  tenant_id       = var.entra_tenant_id
  subscription_id = var.az_sub_id
}

provider "github" {
  alias = "demo"
}
