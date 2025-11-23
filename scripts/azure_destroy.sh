#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/azure"
ENV_FILE="${ROOT_DIR}/.env"

QUIET=0

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

# Load environment variables from .env file (if exists, for local development)
# Note: Secrets are not needed for destroy since Key Vault is excluded
load_env_file

cd "${TF_DIR}"

maybe_echo() {
  if [[ "${QUIET}" -eq 0 ]]; then
    echo "$@"
  fi
}

maybe_echo "Initializing Terraform (azure destroy)..."
terraform init -input=false >/dev/null 2>&1 || {
  maybe_echo "Terraform init reported changes, re-running with output..."
  terraform init -input=false
}

if terraform workspace list | grep -qE '^[[:space:]]*(\* )?azure$'; then
  maybe_echo "Selecting terraform workspace 'azure'..."
  terraform workspace select azure >/dev/null
else
  maybe_echo "Terraform workspace 'azure' not found. Nothing to destroy."
  exit 0
fi

# Remove one-time setup resources from Terraform state before destroying
# These are preserved: Key Vault (contains secrets) and Service Principal/OIDC (GitHub Secrets config)
PROJECT_NAME="${PROJECT_NAME:-bug-buster}"
WORKSPACE=$(terraform workspace show 2>/dev/null || echo "azure")

# Resources to preserve (remove from state before destroy)
PRESERVED_RESOURCES=(
  "azurerm_key_vault.main[0]"
  "azuread_application.github_actions"
  "azuread_service_principal.github_actions"
  "azuread_application_federated_identity_credential.github_actions"
  "azurerm_role_assignment.terraform_secrets_user"
  "azurerm_role_assignment.github_actions_contributor"
)

maybe_echo "Removing one-time setup resources from Terraform state (these will be preserved)..."
for resource in "${PRESERVED_RESOURCES[@]}"; do
  if terraform state show "${resource}" >/dev/null 2>&1; then
    maybe_echo "  Removing ${resource} from state..."
    terraform state rm "${resource}" >/dev/null 2>&1 || {
      maybe_echo "    Note: ${resource} may not be in state"
    }
  fi
done

TF_VARS=()
TF_VARS+=("-var=github_repository=${GITHUB_REPOSITORY:-$(git remote get-url origin 2>/dev/null | sed -n 's/.*github\.com[:/]\([^/]*\/[^/]*\)\.git/\1/p' || echo 'unknown/unknown')}")

if [[ -n "${DOCKER_IMAGE_TAG:-}" ]]; then
  TF_VARS+=("-var=docker_image_tag=${DOCKER_IMAGE_TAG}")
fi

maybe_echo "Destroying Azure infrastructure (protected resources excluded)..."
# Use -target to only destroy non-protected resources
# This avoids trying to destroy resources with prevent_destroy lifecycle
TARGETS=(
  "-target=azurerm_container_app.main"
  "-target=azurerm_container_app_environment.main"
  "-target=azurerm_container_registry.acr"
  "-target=azurerm_log_analytics_workspace.main"
  "-target=azurerm_role_assignment.container_app_kv_secrets_user"
  "-target=azurerm_role_assignment.container_app_acr_pull"
)

# Try destroy with targets, if locked, suggest unlock command
if ! terraform destroy -input=false -auto-approve "${TF_VARS[@]}" "${TARGETS[@]}" 2>&1; then
  LOCK_ID=$(terraform force-unlock 2>&1 | sed -n 's/.*ID:\s*\([a-f0-9-]\+\).*/\1/p' || echo "")
  if [[ -n "${LOCK_ID}" ]]; then
    maybe_echo "⚠️  State is locked. Run this to unlock:"
    maybe_echo "   cd terraform/azure && terraform force-unlock -force ${LOCK_ID}"
    maybe_echo ""
    maybe_echo "   Or destroy with lock disabled:"
    maybe_echo "   terraform destroy -var=github_repository=\$(git remote get-url origin | sed -n 's/.*github\\.com[:/]\\([^/]*\\/[^/]*\\)\\.git/\\1/p') -lock=false -auto-approve"
  fi
  exit 1
fi

maybe_echo "Azure resources destroyed (one-time setup resources preserved)."
maybe_echo ""
maybe_echo "Preserved resources (one-time setup):"
maybe_echo "  - Key Vault (contains secrets)"
maybe_echo "  - Service Principal & OIDC (GitHub Actions authentication)"
maybe_echo ""
maybe_echo "To destroy Key Vault manually, run: ./scripts/azure_destroy_keyvault.sh"
maybe_echo "To destroy Service Principal/OIDC, remove lifecycle.prevent_destroy from Terraform and destroy manually"

