data "azurerm_client_config" "current_azrm_config" {}

# Azure Storage Account
resource "azurerm_storage_account" "my_sa" {
  name                          = "${var.workload_nickname}storacct"
  location                      = var.resource_group.location
  resource_group_name           = var.resource_group.name
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = true
  is_hns_enabled                = false
}

# Throw a simple access key into GitHub Actions secrets
resource "github_actions_secret" "gh_secret_stor_acct_write_key" {
  repository      = var.current_gh_repo
  secret_name     = "AZ_STOR_ACCT_WRITE_KEY"
  plaintext_value = azurerm_storage_account.my_sa.primary_access_key
}

# Grant myself adequate permissions over the storage account (required to play with file CRUD)
resource "azurerm_role_assignment" "myself_as_data_privileged_contributor" {
  role_definition_name = "Storage File Data Privileged Contributor"
  scope                = azurerm_storage_account.my_sa.id
  principal_id         = data.azurerm_client_config.current_azrm_config.object_id
}

# Cache storage account name to CICD I use for testing
resource "github_actions_variable" "gh_var_storacct_name" {
  repository    = var.current_gh_repo
  variable_name = "THE_STORACCT_NAME"
  value         = azurerm_storage_account.my_sa.name
}

# Azure File Share
resource "azurerm_storage_share" "my_safs" {
  name               = "${var.workload_nickname}storacctfs"
  storage_account_id = azurerm_storage_account.my_sa.id
  quota              = 1
  access_tier        = "TransactionOptimized" # or Hot, as needed
  enabled_protocol   = "SMB"
  # Using the web portal to create a Storage Sync Cloud Endpoint seems to insert a GhostedRecall ACL access policy, 
  # so I guess we might as well create it this way in the first place.
  acl {
    id = "GhostedRecall"
    access_policy {
      permissions = "r"
    }
  }
}

# Cache share name to CICD I use for testing
resource "github_actions_variable" "gh_var_sharepath_name" {
  repository    = var.current_gh_repo
  variable_name = "THE_SHARE_NAME"
  value         = azurerm_storage_share.my_safs.name
}

# Cache share UNC path to CICD I use for testing
resource "github_actions_variable" "gh_var_storacct_sharepath" {
  repository    = var.current_gh_repo
  variable_name = "THE_STORACCT_SHAREPATH"
  value         = "\\\\${azurerm_storage_account.my_sa.name}.file.core.windows.net\\${azurerm_storage_share.my_safs.name}"
}

# Azure Storage Sync Service
resource "azapi_resource" "my_sss" {
  type      = "Microsoft.StorageSync/storageSyncServices@2022-09-01"
  name      = "${var.workload_nickname}sssvc"
  parent_id = var.resource_group.id
  identity {
    type = "SystemAssigned"
  }
  location = var.resource_group.location
  body = {
    properties = {
      useIdentity = true
    }
  }
}

# Grant the storage sync service adequate permissions over the Storage Account (required to create a Cloud Endpoint)
# https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/file-sync
#    /file-sync-troubleshoot-managed-identities#permissions-required-to-access-a-storage-account-and-azure-file-share
resource "azurerm_role_assignment" "sync_as_contributor_to_sa" {
  role_definition_name = "Storage Account Contributor"
  scope                = azurerm_storage_account.my_sa.id
  principal_id         = azapi_resource.my_sss.output.identity.principalId
}

# Grant the storage sync service adequate permissions over the File Share (required to create a Cloud Endpoint)
# https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/file-sync
#    /file-sync-troubleshoot-managed-identities#permissions-required-to-access-a-storage-account-and-azure-file-share
resource "azurerm_role_assignment" "sync_as_data_contributor_to_safs" {
  role_definition_name = "Storage File Data Privileged Contributor"
  scope                = azurerm_storage_share.my_safs.id
  principal_id         = azapi_resource.my_sss.output.identity.principalId
}

# # TODO:  Play with whether this could simply be over the File Share instead.  Least privilege.
# # Grant the storage sync service adequate permissions over the Storage Account (required to create a Cloud Endpoint)
# # https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/file-sync
# #    /file-sync-troubleshoot-managed-identities#permissions-required-to-access-a-storage-account-and-azure-file-share
# resource "azurerm_role_assignment" "sync_as_reader_and_data_access_to_safs" {
#   role_definition_name = "Reader and Data Access"
#   scope                = azurerm_storage_share.my_safs.id
#   principal_id         = azapi_resource.my_sss.output.identity.principalId
# }
resource "azurerm_role_assignment" "sync_as_reader_and_data_access_to_sa" {
  role_definition_name = "Reader and Data Access"
  scope                = azurerm_storage_account.my_sa.id
  principal_id         = azapi_resource.my_sss.output.identity.principalId
}

# Custom role
resource "azurerm_role_definition" "my_custom_role" {
  name        = "Storage Sync Service Server Registrar (custom)"
  scope       = var.resource_group.id
  description = "Grants the minimum required permissions for a human sysadmin, logged into a Windows server that has the Azure File Sync agent installed, to register that server with a given Azure Storage Sync Service resource."
  permissions {
    actions = [
      "Microsoft.StorageSync/storageSyncServices/registeredServers/write",
      "Microsoft.StorageSync/storageSyncServices/read",
      "Microsoft.StorageSync/storageSyncServices/workflows/read",
      "Microsoft.StorageSync/storageSyncServices/workflows/operations/read"
    ]
    not_actions      = []
    data_actions     = []
    not_data_actions = []
  }
  assignable_scopes = [
    var.resource_group.id
  ]
}

# Grant myself adequate permissions over the storage sync service to register a server
resource "azurerm_role_assignment" "myself_as_sync_registrar" {
  role_definition_name = azurerm_role_definition.my_custom_role.name
  scope                = azapi_resource.my_sss.output.id
  principal_id         = data.azurerm_client_config.current_azrm_config.object_id
}

# Azure Storage Sync Group
resource "azurerm_storage_sync_group" "my_ssgrp" {
  name            = "${var.workload_nickname}ssgrp"
  storage_sync_id = azapi_resource.my_sss.output.id
}

# Azure Storage Sync Cloud Endpoint
resource "azurerm_storage_sync_cloud_endpoint" "my_ssclep" {
  name                  = "${var.workload_nickname}ssclep"
  storage_sync_group_id = azurerm_storage_sync_group.my_ssgrp.id
  file_share_name       = azurerm_storage_share.my_safs.name
  storage_account_id    = azurerm_storage_account.my_sa.id
  depends_on = [
    azurerm_role_assignment.sync_as_contributor_to_sa,
    azurerm_role_assignment.sync_as_data_contributor_to_safs,
    azurerm_role_assignment.sync_as_reader_and_data_access_to_sa,
  ]
}
