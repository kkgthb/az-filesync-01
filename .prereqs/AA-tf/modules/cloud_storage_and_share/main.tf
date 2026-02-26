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
  #   azure_files_authentication {
  #     directory_type = "AADKERB" # For Entra ID DS (hybrid join)
  #     active_directory {
  #       storage_sid         = var.storage_sid         # Your AD DS SID
  #       domain_name         = var.domain_name         # Your AD DS domain
  #       netbios_domain_name = var.netbios_domain_name # Your NetBIOS domain
  #       forest_name         = var.forest_name         # Your AD DS forest
  #       domain_guid         = var.domain_guid         # Your AD DS domain GUID
  #       azure_storage_sid   = var.azure_storage_sid   # Your Azure Storage SID
  #     }
  #   }
}

# # Tweak Azure Storage Account
# resource "null_resource" "enable_files_aad_auth" {
#   provisioner "local-exec" {
#     command = "az storage account update --name ${azurerm_storage_account.my_sa.name} --resource-group ${azurerm_storage_account.my_sa.resource_group_name} --subscription ${data.azurerm_client_config.current_azrm_config.subscription_id} --enable-files-aadds true"
#   }
#   depends_on = [azurerm_storage_account.my_sa]
# }
# resource "time_sleep" "wait_for_aad_auth" {
#   create_duration = "120s"
#   depends_on      = [null_resource.enable_files_aad_auth]
# }

# Grant myself adequate permissions over the storage account (required to play with file CRUD)
resource "azurerm_role_assignment" "myself_as_data_privileged_contributor" {
  role_definition_name = "Storage File Data Privileged Contributor"
  scope                = azurerm_storage_account.my_sa.id
  principal_id         = data.azurerm_client_config.current_azrm_config.object_id
}

# Azure File Share
resource "azurerm_storage_share" "my_safs" {
  name               = "${var.workload_nickname}storacctfs"
  storage_account_id = azurerm_storage_account.my_sa.id
  quota              = 1
  access_tier        = "TransactionOptimized" # or Hot, as needed
  enabled_protocol   = "SMB"
  #   depends_on         = [time_sleep.wait_for_aad_auth]
}

resource "github_actions_variable" "gh_var_storacct_sharepath" {
  repository    = var.current_gh_repo
  variable_name = "THE_STORACCT_SHAREPATH"
  value         = "\\\\${azurerm_storage_account.my_sa.name}.file.core.windows.net\\${azurerm_storage_share.my_safs.name}"
}

# Grant myself adequate permissions over the storage account file share (required to play with file CRUD)
resource "azurerm_role_assignment" "myself_as_data_smb_contributor" {
  role_definition_name = "Storage File Data SMB Share Contributor"
  scope                = azurerm_storage_share.my_safs.id
  principal_id         = data.azurerm_client_config.current_azrm_config.object_id
}

# # # Azure Storage Sync Service
# resource "azapi_resource" "my_sss" {
#   type      = "Microsoft.StorageSync/storageSyncServices@2022-09-01"
#   name      = "${var.workload_nickname}sssvc"
#   parent_id = var.resource_group.id
#   identity {
#     type = "SystemAssigned"
#   }
#   location = var.resource_group.location
#   body = {
#     properties = {
#       useIdentity = true
#     }
#   }
# }

# # # Azure Storage Sync Service
# # resource "azurerm_storage_sync" "my_sss" {
# #   name                = "${var.workload_nickname}sssvc"
# #   location            = var.resource_group.location
# #   resource_group_name = var.resource_group.name
# # }

# # # Custom role
# # resource "azurerm_role_definition" "my_custom_role" {
# #   name        = "Storage Sync Service Server Registrar (custom)"
# #   scope       = var.resource_group.id
# #   description = "Grants the minimum required permissions for a human sysadmin, logged into a Windows server that has the Azure File Sync agent installed, to register that server with a given Azure Storage Sync Service resource."
# #   permissions {
# #     actions = [
# #       "Microsoft.StorageSync/storageSyncServices/registeredServers/write",
# #       "Microsoft.StorageSync/storageSyncServices/read",
# #       "Microsoft.StorageSync/storageSyncServices/workflows/read",
# #       "Microsoft.StorageSync/storageSyncServices/workflows/operations/read"
# #     ]
# #     not_actions      = []
# #     data_actions     = []
# #     not_data_actions = []
# #   }
# #   assignable_scopes = [
# #     var.resource_group.id
# #   ]
# # }

# # Grant myself adequate permissions over the storage sync service to register a server
# # resource "azurerm_role_assignment" "myself_as_sync_registrar" {
# #   role_definition_id = azurerm_role_definition.my_custom_role.role_definition_id
# #   scope              = azapi_resource.my_sss.output.id
# #   principal_id       = data.azurerm_client_config.current_azrm_config.object_id
# # }

# # Grant the storage sync service adequate permissions over the Storage Account (required to create a Cloud Endpoint)
# # https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/file-sync
# #    /file-sync-troubleshoot-managed-identities#permissions-required-to-access-a-storage-account-and-azure-file-share
# resource "azurerm_role_assignment" "sync_as_contributor_to_sa" {
#   role_definition_name = "Storage Account Contributor"
#   scope                = azurerm_storage_account.my_sa.id
#   principal_id         = azapi_resource.my_sss.output.identity.principalId
# }

# # Grant the storage sync service adequate permissions over the File Share (required to create a Cloud Endpoint)
# # https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/file-sync
# #    /file-sync-troubleshoot-managed-identities#permissions-required-to-access-a-storage-account-and-azure-file-share
# resource "azurerm_role_assignment" "sync_as_data_contributor_to_safs" {
#   role_definition_name = "Storage File Data Privileged Contributor"
#   scope                = azurerm_storage_share.my_safs.id
#   principal_id         = azapi_resource.my_sss.output.identity.principalId
# }

# # Azure Storage Sync Group
# resource "azurerm_storage_sync_group" "my_ssgrp" {
#   name            = "${var.workload_nickname}ssgrp"
#   storage_sync_id = azapi_resource.my_sss.output.id
# }

# # Azure Storage Sync Cloud Endpoint
# # This seems to like to "MgmtForbidden2" / "Failed to provision a replica group." out 
# # and not make it into terraform.tfstate, 
# # but actually exist in Azure, and then 
# # need a "terraform import."  Sigh.  Anyway, not my focus right now.
# resource "azurerm_storage_sync_cloud_endpoint" "my_ssclep" {
#   name                  = "${var.workload_nickname}ssclep"
#   storage_sync_group_id = azurerm_storage_sync_group.my_ssgrp.id
#   file_share_name       = azurerm_storage_share.my_safs.name
#   storage_account_id    = azurerm_storage_account.my_sa.id
#   depends_on = [
#     time_sleep.wait_for_aad_auth,
#     azurerm_role_assignment.sync_as_contributor_to_sa,
#     azurerm_role_assignment.sync_as_data_contributor_to_safs,
#   ]
# }
