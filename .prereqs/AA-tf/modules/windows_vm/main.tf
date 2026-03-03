module "network_demo" {
  source = "./network"
  resource_group = {
    id       = var.resource_group.id
    name     = var.resource_group.name
    location = var.resource_group.location
  }
  workload_nickname = var.workload_nickname
  current_gh_repo   = var.current_gh_repo
}

module "winrm_cert_demo" {
  source = "./winrm"
  resource_group = {
    id       = var.resource_group.id
    name     = var.resource_group.name
    location = var.resource_group.location
  }
  workload_nickname = var.workload_nickname
  fqdn              = module.network_demo.fqdn
}

module "vm_demo" {
  source = "./vm"
  resource_group = {
    id       = var.resource_group.id
    name     = var.resource_group.name
    location = var.resource_group.location
  }
  umi_id                      = module.winrm_cert_demo.win_vm_umi_id
  umi_principal_id            = module.winrm_cert_demo.win_vm_umi_principal_id
  winrm_kv_id                 = module.winrm_cert_demo.winrm_kv_id
  winrm_cert_url              = module.winrm_cert_demo.winrm_cert_url
  nic_id                      = module.network_demo.nic_id
  fqdn                        = module.network_demo.fqdn
  username                    = "barfoo"
  workload_nickname           = var.workload_nickname
  current_gh_repo             = var.current_gh_repo
  custom_role_definition_name = var.custom_role_definition_name
  sss_id                      = var.sss_id
}
