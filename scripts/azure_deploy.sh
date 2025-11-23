#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/azure"
ENV_FILE="${ROOT_DIR}/.env"

QUIET=0
PLAN_FILE=".tfplan"

# Load .env file if it exists (for local development)
# In CI/CD (GitHub Actions), environment variables are already set from secrets
load_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    source "${ENV_FILE}"
    set +a
  elif [[ "${CI:-}" != "true" ]]; then
    # Only warn in local development if .env is missing
    echo "Warning: .env file not found. Using environment variables if set." >&2
  fi
}

if [[ "${CI:-}" == "true" ]]; then
  QUIET=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      QUIET=1
      shift
      ;;
    --verbose)
      QUIET=0
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Load environment variables from .env file if it exists (for local development)
# Note: Secrets are stored in Key Vault, not passed to Terraform
load_env_file

cd "${TF_DIR}"

maybe_echo() {
  if [[ "${QUIET}" -eq 0 ]]; then
    echo "$@"
  fi
}

maybe_echo "Initializing Terraform (azure)..."
terraform init -input=false >/dev/null 2>&1 || {
  maybe_echo "Terraform init reported changes, re-running with output..."
  terraform init -input=false
}

maybe_echo "Ensuring terraform workspace 'azure' exists..."
if ! terraform workspace list | grep -qE '^[[:space:]]*(\* )?azure$'; then
  maybe_echo "Creating terraform workspace 'azure'..."
  terraform workspace new azure >/dev/null
fi

maybe_echo "Selecting terraform workspace 'azure'..."
terraform workspace select azure >/dev/null

# Prepare Terraform variables
TF_VARS=()

# In CI/CD, disable resource creation that requires elevated permissions FIRST
# This must be set before any terraform commands
if [[ "${CI:-}" == "true" ]]; then
  TF_VARS+=("-var=create_terraform_role_assignment=false")
  TF_VARS+=("-var=manage_azuread_resources=false")
  maybe_echo "CI/CD mode: Disabling resource creation that requires elevated permissions"
  maybe_echo "  Variables set: create_terraform_role_assignment=false, manage_azuread_resources=false"
fi

# GitHub repository is required for OIDC federated credential
# Try to auto-detect from git remote if not set
if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ -n "${GIT_REMOTE}" ]]; then
    # Extract owner/repo from various git remote URL formats
    # Handles: https://github.com/owner/repo.git, git@github.com:owner/repo.git, etc.
    if [[ "${GIT_REMOTE}" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
      GITHUB_REPOSITORY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
      maybe_echo "Auto-detected GitHub repository: ${GITHUB_REPOSITORY}"
    fi
  fi
  
  # If still not set, show error
  if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
    echo "Error: GITHUB_REPOSITORY environment variable is required" >&2
    echo "Set it to 'owner/repo' format (e.g., 'myorg/bug-buster-ai')" >&2
    echo "Or ensure you're in a git repository with a GitHub remote named 'origin'" >&2
    exit 1
  fi
fi
TF_VARS+=("-var=github_repository=${GITHUB_REPOSITORY}")

# Note: docker_image_tag is no longer used - GitHub Actions manages image tags directly
# Terraform uses a placeholder tag to avoid state drift

# Import existing resources into Terraform state if they exist but aren't in state
PROJECT_NAME="${PROJECT_NAME:-bug-buster}"
RESOURCE_GROUP="${RESOURCE_GROUP:-bug-buster-rg}"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Function to check if resource exists in Azure and import if needed
import_resource() {
  local terraform_address="$1"
  local resource_name="$2"
  local resource_id="$3"
  local check_command="$4"
  
  # Check if resource exists in Azure
  if eval "${check_command}" >/dev/null 2>&1; then
    # Check if already in Terraform state
    if ! terraform state show "${terraform_address}" >/dev/null 2>&1; then
      maybe_echo "Importing existing ${resource_name} into Terraform state..."
      terraform import "${TF_VARS[@]}" "${terraform_address}" "${resource_id}" >/dev/null 2>&1 || {
        maybe_echo "⚠️  Failed to import ${resource_name}. Continuing - Terraform will handle it during apply"
      }
    fi
  fi
}

# Define resources to import: terraform_address, display_name, resource_id, check_command
declare -a RESOURCES_TO_IMPORT=(
  "azurerm_key_vault.main|Key Vault|/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/kv-${PROJECT_NAME}|az keyvault show --name kv-${PROJECT_NAME}"
  "azurerm_container_registry.acr|ACR|/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerRegistry/registries/${PROJECT_NAME//-/}acr|az acr show --name ${PROJECT_NAME//-/}acr"
  "azurerm_log_analytics_workspace.main|Log Analytics Workspace|/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${PROJECT_NAME}-law|az monitor log-analytics workspace show --resource-group ${RESOURCE_GROUP} --workspace-name ${PROJECT_NAME}-law"
  "azurerm_container_app_environment.main|Container App Environment|/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/managedEnvironments/${PROJECT_NAME}-env|az containerapp env show --name ${PROJECT_NAME}-env --resource-group ${RESOURCE_GROUP}"
)

# Import each resource
for resource_info in "${RESOURCES_TO_IMPORT[@]}"; do
  IFS='|' read -r terraform_address display_name resource_id check_command <<< "${resource_info}"
  import_resource "${terraform_address}" "${display_name}" "${resource_id}" "${check_command}"
done

# Azure AD Application import (if exists and manage_azuread_resources is false)
# Note: In CI/CD, we don't manage these resources, so we need to import them if they exist
# But if manage_azuread_resources=false, Terraform won't have the resource block to import into
# So we skip import in CI/CD - the data source will read the existing app
if [[ "${CI:-}" != "true" ]]; then
  # Only try to import if we're managing the resources (local mode)
  AD_APP_NAME="${PROJECT_NAME}-github-actions"
  AD_APP_ID=$(az ad app list --display-name "${AD_APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || echo "")
  if [[ -n "${AD_APP_ID}" && "${AD_APP_ID}" != "null" ]]; then
    if ! terraform state show 'azuread_application.github_actions[0]' >/dev/null 2>&1; then
      maybe_echo "Importing existing Azure AD Application '${AD_APP_NAME}' into Terraform state..."
      # Azure AD app import uses the application ID (client_id), not object ID
      terraform import "${TF_VARS[@]}" 'azuread_application.github_actions[0]' "${AD_APP_ID}" >/dev/null 2>&1 || {
        maybe_echo "⚠️  Failed to import Azure AD Application."
      }
    fi
    # Also import Service Principal if it exists
    SP_OBJECT_ID=$(az ad sp show --id "${AD_APP_ID}" --query id -o tsv 2>/dev/null || echo "")
    if [[ -n "${SP_OBJECT_ID}" && "${SP_OBJECT_ID}" != "null" ]]; then
      if ! terraform state show 'azuread_service_principal.github_actions[0]' >/dev/null 2>&1; then
        maybe_echo "Importing existing Service Principal into Terraform state..."
        terraform import "${TF_VARS[@]}" 'azuread_service_principal.github_actions[0]' "${SP_OBJECT_ID}" >/dev/null 2>&1 || {
          maybe_echo "⚠️  Failed to import Service Principal."
        }
      fi
    fi
  fi
else
  maybe_echo "CI/CD mode: Skipping Azure AD resource imports (using data source instead)"
fi

# Verify variables are set correctly (especially in CI/CD)
if [[ "${CI:-}" == "true" ]]; then
  maybe_echo "Verifying CI/CD variables are set..."
  if ! printf '%s\n' "${TF_VARS[@]}" | grep -q "manage_azuread_resources=false"; then
    echo "ERROR: manage_azuread_resources=false not found in TF_VARS!" >&2
    echo "TF_VARS: ${TF_VARS[*]}" >&2
    exit 1
  fi
  if ! printf '%s\n' "${TF_VARS[@]}" | grep -q "create_terraform_role_assignment=false"; then
    echo "ERROR: create_terraform_role_assignment=false not found in TF_VARS!" >&2
    exit 1
  fi
fi

# Refresh state after imports to ensure Terraform recognizes imported resources
maybe_echo "Refreshing Terraform state after imports..."
terraform refresh "${TF_VARS[@]}" >/dev/null 2>&1 || true

maybe_echo "Planning Azure infrastructure changes..."

if [[ "${QUIET}" -eq 1 ]]; then
  terraform plan -input=false -out="${PLAN_FILE}" "${TF_VARS[@]}" >/dev/null
else
  terraform plan -input=false -out="${PLAN_FILE}" "${TF_VARS[@]}"
fi

maybe_echo "Applying Azure infrastructure changes..."
if [[ "${QUIET}" -eq 1 ]]; then
  terraform apply -input=false -auto-approve "${PLAN_FILE}" >/dev/null
else
  terraform apply -input=false -auto-approve "${PLAN_FILE}"
fi

rm -f "${PLAN_FILE}"

if [[ "${QUIET}" -eq 0 ]]; then
  echo
  echo "Deployment complete. Key outputs:"
  terraform output
fi

