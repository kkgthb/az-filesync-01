# Tenant ID to CI/CD
data "azuread_client_config" "current_azad_config" {}
resource "github_actions_secret" "gh_var_entra_tenant_id" {
  repository      = var.current_gh_repo
  secret_name     = "ENTRA_TENANT_ID"
  plaintext_value = data.azuread_application.cicd_app.client_id
}

# Look up the existing Entra App Registration by display name
data "azuread_application" "cicd_app" {
  display_name = var.entra_appreg_display_name
}

# Look up the Service Principal that backs the existing App Registration
data "azuread_service_principal" "cicd_sp" {
  client_id = data.azuread_application.cicd_app.client_id
}

# Client ID to CI/CD
resource "github_actions_secret" "gh_var_entra_client_id" {
  repository      = var.current_gh_repo
  secret_name     = "ENTRA_CLIENT_ID"
  plaintext_value = data.azuread_application.cicd_app.client_id
}

# Client secret to CI/CD (for this test only; should use FedCreds)
resource "azuread_application_password" "cicd_secret" {
  application_id = data.azuread_application.cicd_app.id
  display_name   = "secret-while-testing-and-learning"
}
resource "github_actions_secret" "gh_secret_entra_client_secret" {
  repository      = var.current_gh_repo
  secret_name     = "ENTRA_CLIENT_SECRET"
  plaintext_value = azuread_application_password.cicd_secret.value
}
