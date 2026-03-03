output "custom_role_definition_name" {
  value = azurerm_role_definition.my_custom_role.name
}

output "sss_id" {
  value = azapi_resource.my_sss.output.id
}
