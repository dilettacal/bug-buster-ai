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
resource "azurerm_role_assignment" "terraform_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ============================================================================
# Service Principal & OIDC for GitHub Actions
# ============================================================================

# Azure AD Application for GitHub Actions
resource "azuread_application" "github_actions" {
  display_name = "${var.project_name}-github-actions"
  description  = "Service Principal for GitHub Actions CI/CD via OIDC"

  lifecycle {
    prevent_destroy = true  # OIDC setup is one-time, preserve GitHub Secrets configuration
  }
}

# Service Principal
resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id

  lifecycle {
    prevent_destroy = true  # OIDC setup is one-time, preserve GitHub Secrets configuration
  }
}

# Federated Identity Credential for GitHub Actions OIDC
resource "azuread_application_federated_identity_credential" "github_actions" {
  application_id = azuread_application.github_actions.id
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
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
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
resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions.object_id
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
output "github_actions_client_id" {
  description = "Service Principal Client ID for GitHub Actions (add to GitHub Secrets as AZURE_CLIENT_ID)"
  value       = azuread_application.github_actions.client_id
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

