variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "bug-buster"
}

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' for OIDC federated identity"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$", var.github_repository))
    error_message = "GitHub repository must be in format 'owner/repo'"
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "West Europe"
}

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
  default     = "bug-buster-rg"
}

variable "create_terraform_role_assignment" {
  description = "Whether to create role assignment for current user/SP (set to false in CI/CD if SP lacks permissions)"
  type        = bool
  default     = true
}

variable "manage_azuread_resources" {
  description = "Whether to create/manage Azure AD resources (set to false in CI/CD - resources must exist and be imported)"
  type        = bool
  default     = true
}

