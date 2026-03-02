resource "azurerm_resource_group" "my_resource_group" {
  provider = azurerm.demo
  name     = "${var.workload_nickname}-rg-demo"
  location = "centralus"
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
  workload_nickname = var.workload_nickname
  current_gh_repo   = var.current_gh_repo
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
  workload_nickname = var.workload_nickname
  current_gh_repo   = var.current_gh_repo
}
