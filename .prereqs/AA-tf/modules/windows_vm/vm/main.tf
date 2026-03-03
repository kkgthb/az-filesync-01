data "azurerm_client_config" "current_azrm_config" {}

resource "random_password" "admin_pw" {
  length  = 32
  special = false
}

resource "azurerm_windows_virtual_machine" "my_vm" {
  name                  = "${var.workload_nickname}WinVm"
  location              = var.resource_group.location
  resource_group_name   = var.resource_group.name
  network_interface_ids = [var.nic_id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "${var.workload_nickname}WinOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  computer_name  = substr(var.workload_nickname, 0, 14)
  admin_username = var.username
  admin_password = random_password.admin_pw.result

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.umi_id]
  }

  secret {
    key_vault_id = var.winrm_kv_id
    certificate {
      store = "My" # The Windows personal certificate store
      url   = var.winrm_cert_url
    }
  }

  winrm_listener {
    protocol        = "Https"
    certificate_url = var.winrm_cert_url
  }
}

resource "azurerm_virtual_machine_extension" "my_entra_login_vmex" {
  virtual_machine_id   = azurerm_windows_virtual_machine.my_vm.id
  publisher            = "Microsoft.Azure.ActiveDirectory"
  name                 = "${var.workload_nickname}AADLoginForWindows"
  type                 = "AADLoginForWindows"
  type_handler_version = "1.0"
}

resource "azurerm_role_assignment" "myself_as_os_admin" {
  role_definition_name = "Virtual Machine Administrator Login"
  scope                = azurerm_windows_virtual_machine.my_vm.id
  principal_id         = data.azurerm_client_config.current_azrm_config.object_id
}

resource "github_actions_secret" "gh_scrt_vm_username" {
  repository      = var.current_gh_repo
  secret_name     = "THE_WINDOWS_VM_USERNAME"
  plaintext_value = var.username
}

resource "github_actions_secret" "gh_scrt_vm_winrm_pw" {
  repository      = var.current_gh_repo
  secret_name     = "THE_WINDOWS_VM_PASSWORD"
  plaintext_value = random_password.admin_pw.result
  # Note:  I'm not sure if plaintext_value would be secure enough for production, but 
  # this is just throwaway infrastructure I keep destroying between runs anyway, and my 
  # Terraform state file is secured.
}

# Grant the VM adequate permissions over the storage sync service to register a server
resource "azurerm_role_assignment" "smi_as_sync_registrar" {
  role_definition_name = var.custom_role_definition_name
  scope                = var.sss_id
  principal_id         = azurerm_windows_virtual_machine.my_vm.identity[0].principal_id
}
resource "azurerm_role_assignment" "umi_as_sync_registrar" {
  role_definition_name = var.custom_role_definition_name
  scope                = var.sss_id
  principal_id         = var.umi_principal_id
}
