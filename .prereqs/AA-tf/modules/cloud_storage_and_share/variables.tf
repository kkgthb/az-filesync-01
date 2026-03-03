variable "resource_group" {
  description = "Parent resource group parameters"
  type = object({
    id       = string
    name     = string
    location = string
  })
}

variable "workload_nickname" {
  type = string
}

variable "current_gh_repo" {
  type = string
}

variable "cicd_service_principal_object_id" {
  type        = string
  description = "Object ID of the CI/CD service principal, for RBAC assignments over the storage account and sync service."
}
