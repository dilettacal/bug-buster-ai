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

# Check if Key Vault exists and import it if needed (informational only - Terraform doesn't read secrets)
PROJECT_NAME="${PROJECT_NAME:-bug-buster}"
WORKSPACE=$(terraform workspace show 2>/dev/null || echo "azure")
KV_NAME="${PROJECT_NAME}-kv-${WORKSPACE}"
RESOURCE_GROUP="${RESOURCE_GROUP:-bug-buster-rg}"

# Import Key Vault into Terraform state if it exists but isn't in state
# Note: Must pass TF_VARS to import command to avoid prompts for required variables
KV_RESOURCE_ID="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KV_NAME}"
KV_IMPORTED=false
if az keyvault show --name "${KV_NAME}" >/dev/null 2>&1; then
  if ! terraform state show 'azurerm_key_vault.main[0]' >/dev/null 2>&1; then
    maybe_echo "⚠️  Key Vault '${KV_NAME}' exists but not in Terraform state"
    maybe_echo "   Import it manually if needed: terraform import ${TF_VARS[*]} azurerm_key_vault.main[0] '${KV_RESOURCE_ID}'"
    maybe_echo "   Continuing - Terraform will handle the import during apply if needed"
  fi
  
  if az keyvault secret show --vault-name "${KV_NAME}" --name "openai-api-key" >/dev/null 2>&1 && \
     az keyvault secret show --vault-name "${KV_NAME}" --name "semgrep-app-token" >/dev/null 2>&1; then
    maybe_echo "✓ Secrets found in Key Vault"
  else
    maybe_echo "⚠️  Warning: Secrets not found in Key Vault '${KV_NAME}'"
    maybe_echo "   Add them before the Container App can start:"
    maybe_echo "   az keyvault secret set --vault-name ${KV_NAME} --name openai-api-key --value <your-key>"
    maybe_echo "   az keyvault secret set --vault-name ${KV_NAME} --name semgrep-app-token --value <your-token>"
  fi
else
  maybe_echo "Note: Key Vault will be created by Terraform"
fi

maybe_echo "Planning Azure infrastructure changes..."
# If Key Vault was just imported, refresh state to ensure it's recognized
if [[ "${KV_IMPORTED}" == "true" ]]; then
  maybe_echo "Refreshing state after Key Vault import..."
  terraform refresh "${TF_VARS[@]}" >/dev/null 2>&1 || true
fi

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
