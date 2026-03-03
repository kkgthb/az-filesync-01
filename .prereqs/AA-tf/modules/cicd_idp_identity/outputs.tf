output "cicd_service_principal_object_id" {
  value = data.azuread_service_principal.cicd_sp.object_id
}
