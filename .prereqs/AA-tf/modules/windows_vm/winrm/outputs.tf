output "win_vm_umi_id" {
  value = azurerm_user_assigned_identity.my_umi.id
  depends_on = [ azurerm_role_assignment.umi_as_cert_reader ] # Make sure, with retries, that we do not move on until this is done
}

output "winrm_kv_id" {
  value = azurerm_key_vault.winrm_kv.id
}

output "winrm_cert_url" {
  value = azurerm_key_vault_certificate.winrm_cert.secret_id
}