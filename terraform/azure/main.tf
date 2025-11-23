terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate.d/azure/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "azuread" {
}

# Data source for existing resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Key Vault with RBAC (no access policies)
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Enable RBAC (no access policies)
  enable_rbac_authorization = true

  # Soft delete retention
  soft_delete_retention_days = 7
  purge_protection_enabled    = false

  lifecycle {
    ignore_changes = [soft_delete_retention_days]
    prevent_destroy = true  # Key Vault is a one-time setup, preserve secrets
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Get current client config (for tenant_id, object_id)
data "azurerm_client_config" "current" {
}

# Grant current user/SP "Key Vault Secrets User" role for Terraform operations
# Only create if running locally (not via GitHub Actions SP)
# GitHub Actions SP should already have this role or it can be granted manually
resource "azurerm_role_assignment" "terraform_secrets_user" {
  count                = var.create_terraform_role_assignment ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ============================================================================
# Service Principal & OIDC for GitHub Actions
# ============================================================================

# Azure AD Application for GitHub Actions
# Only create if manage_azuread_resources is true (not in CI/CD)
resource "azuread_application" "github_actions" {
  count        = var.manage_azuread_resources ? 1 : 0
  display_name = "${var.project_name}-github-actions"
  description  = "Service Principal for GitHub Actions CI/CD via OIDC"

  lifecycle {
    prevent_destroy = true  # OIDC setup is one-time, preserve GitHub Secrets configuration
  }
}

# Service Principal
resource "azuread_service_principal" "github_actions" {
  count    = var.manage_azuread_resources ? 1 : 0
  client_id = azuread_application.github_actions[0].client_id

  lifecycle {
    prevent_destroy = true  # OIDC setup is one-time, preserve GitHub Secrets configuration
  }
}

# Federated Identity Credential for GitHub Actions OIDC
resource "azuread_application_federated_identity_credential" "github_actions" {
  count         = var.manage_azuread_resources ? 1 : 0
  application_id = azuread_application.github_actions[0].id
  display_name   = "github-actions-oidc"
  description    = "Federated identity for GitHub Actions"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:ref:refs/heads/main"

  lifecycle {
    prevent_destroy = true  # OIDC setup is one-time, preserve GitHub Secrets configuration
  }
}

# Grant Service Principal "Contributor" role on Resource Group
# (This allows GitHub Actions to manage resources in the resource group)
resource "azurerm_role_assignment" "github_actions_contributor" {
  count                = var.manage_azuread_resources ? 1 : 0
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}

# ============================================================================
# Container Registry
# ============================================================================

# Azure Container Registry (admin disabled - use Managed Identity)
resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.project_name, "-", "")}acr"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false  # Use Managed Identity instead of admin credentials

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Grant GitHub Actions SP "AcrPush" role on ACR
# (This allows GitHub Actions to push Docker images)
# Note: In CI/CD, this requires the SP to already exist and be imported
resource "azurerm_role_assignment" "github_actions_acr_push" {
  count                = var.manage_azuread_resources ? 1 : 0
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions[0].object_id
}

# ============================================================================
# Log Analytics Workspace
# ============================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-law"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# Container App Environment
# ============================================================================

resource "azurerm_container_app_environment" "main" {
  name                       = "${var.project_name}-env"
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Outputs
output "resource_group_name" {
  description = "Resource group name"
  value       = data.azurerm_resource_group.main.name
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "location" {
  description = "Azure region"
  value       = data.azurerm_resource_group.main.location
}

# GitHub Actions OIDC outputs (for GitHub Secrets)
# Note: In CI/CD mode (manage_azuread_resources=false), client_id is not available
# because the Service Principal lacks permissions to read Azure AD resources.
# The client_id should already be in GitHub Secrets from the initial local setup.
output "github_actions_client_id" {
  description = "Service Principal Client ID for GitHub Actions (add to GitHub Secrets as AZURE_CLIENT_ID)"
  value       = var.manage_azuread_resources ? azuread_application.github_actions[0].client_id : null
  sensitive   = false
}

output "github_actions_tenant_id" {
  description = "Azure Tenant ID (add to GitHub Secrets as AZURE_TENANT_ID)"
  value       = data.azurerm_client_config.current.tenant_id
}

output "github_actions_subscription_id" {
  description = "Azure Subscription ID (add to GitHub Secrets as AZURE_SUBSCRIPTION_ID)"
  value       = data.azurerm_client_config.current.subscription_id
}

# Container Registry outputs
output "acr_login_server" {
  description = "ACR login server (for Docker push/pull)"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  description = "ACR name"
  value       = azurerm_container_registry.acr.name
}

# Log Analytics Workspace output
output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = azurerm_log_analytics_workspace.main.id
}

# Container App Environment output
output "container_app_environment_id" {
  description = "Container App Environment ID"
  value       = azurerm_container_app_environment.main.id
}

