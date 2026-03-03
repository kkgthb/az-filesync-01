module "cicdidpidentity" {
  source = "./modules/cicd_idp_identity"
  providers = {
    azuread = azuread.demo
    github  = github.demo
  }
  current_gh_repo           = var.current_gh_repo
  workload_nickname         = var.workload_nickname
  entra_appreg_display_name = var.entra_appreg_name_idea
}

resource "azurerm_resource_group" "my_resource_group" {
  provider = azurerm.demo
  name     = "${var.workload_nickname}-rg-demo"
  location = "centralus"
}

# Subscription ID to CI/CD
data "azurerm_client_config" "current_azrm_config" {
  provider = azurerm.demo
}
resource "github_actions_secret" "gh_secret_azsub" {
  provider        = github.demo
  repository      = var.current_gh_repo
  secret_name     = "AZURE_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current_azrm_config.subscription_id
}

module "cloudstorageandshare" {
  source = "./modules/cloud_storage_and_share"
  providers = {
    azurerm = azurerm.demo
    azapi   = azapi.demo
    github  = github.demo
  }
  resource_group = {
    id       = azurerm_resource_group.my_resource_group.id
    name     = azurerm_resource_group.my_resource_group.name
    location = azurerm_resource_group.my_resource_group.location
  }
  workload_nickname                = var.workload_nickname
  current_gh_repo                  = var.current_gh_repo
  cicd_service_principal_object_id = module.cicdidpidentity.cicd_service_principal_object_id
}

module "windows" {
  source = "./modules/windows_vm"
  providers = {
    azurerm = azurerm.demo
    azapi   = azapi.demo
    github  = github.demo
  }
  resource_group = {
    id       = azurerm_resource_group.my_resource_group.id
    name     = azurerm_resource_group.my_resource_group.name
    location = azurerm_resource_group.my_resource_group.location
  }
  workload_nickname           = var.workload_nickname
  current_gh_repo             = var.current_gh_repo
  custom_role_definition_name = module.cloudstorageandshare.custom_role_definition_name
  sss_id                      = module.cloudstorageandshare.sss_id
}
