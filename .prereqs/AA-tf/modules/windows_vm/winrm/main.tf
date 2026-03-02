data "azurerm_client_config" "current_user" {}

# Create a user-assigned managed identity for the eventual VM.
# Generally, I am not a fan of UMIs compared to system-assigned managed identities, 
# but unless I want to do manual idempotent WinRM-related PowerShell scripting after 
# provisioning the VM, I have to be able to grant "Key Vault Certificate User" 
# to the identity used by the VM before the VM even exists yet, or else 
# WinRM auto-setup will fail because the VM will not yet have access to 
# read the WinRM certificate out of Azure Key Vault.
resource "azurerm_user_assigned_identity" "my_umi" {
  name                = "${var.workload_nickname}Win-umi-demo"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}

# Create a Key Vault
resource "azurerm_key_vault" "winrm_kv" {
  name                       = "${var.workload_nickname}-kv-demo"
  location                   = var.resource_group.location
  resource_group_name        = var.resource_group.name
  tenant_id                  = data.azurerm_client_config.current_user.tenant_id
  rbac_authorization_enabled = true
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  enabled_for_deployment     = true
}

# Grant myself adequate permissions over it
resource "azurerm_role_assignment" "myself_as_cert_officer" {
  role_definition_name = "Key Vault Certificates Officer"
  scope                = azurerm_key_vault.winrm_kv.id
  principal_id         = data.azurerm_client_config.current_user.object_id
}

# Grant the UMI adequate permissions over it
resource "azurerm_role_assignment" "umi_as_cert_reader" {
  role_definition_name = "Key Vault Certificate User"
  scope                = azurerm_key_vault.winrm_kv.id
  principal_id         = azurerm_user_assigned_identity.my_umi.principal_id
}

# Create a certificate within it
resource "random_pet" "winrm_cert_name" {
  prefix    = "winrmcert"
  separator = ""
}
resource "azurerm_key_vault_certificate" "winrm_cert" {
  name         = random_pet.winrm_cert_name.id
  key_vault_id = azurerm_key_vault.winrm_kv.id
  depends_on   = [azurerm_role_assignment.myself_as_cert_officer]
  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    x509_certificate_properties {
      subject            = "CN=hello-world"
      validity_in_months = 12
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"] # Server Authentication = ...3.1; Client = ...3.2
      key_usage          = ["digitalSignature", "keyEncipherment"]
      subject_alternative_names {
        dns_names = [var.fqdn]
      }
    }
  }
}
