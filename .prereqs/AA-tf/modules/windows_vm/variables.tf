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
