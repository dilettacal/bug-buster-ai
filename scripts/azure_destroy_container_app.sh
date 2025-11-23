#!/usr/bin/env bash

# Script to destroy only the Container App (useful for clean recreation)
# Usage: ./scripts/azure_destroy_container_app.sh

set -euo pipefail

# Allow script to continue even if some commands fail (for cleanup)
set +e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/azure"

cd "${TF_DIR}"

PROJECT_NAME="${PROJECT_NAME:-bug-buster}"
RESOURCE_GROUP="${RESOURCE_GROUP:-bug-buster-rg}"

echo "This will destroy the Container App '${PROJECT_NAME}'"
echo "This action cannot be undone!"
echo ""
echo "Press Ctrl+C to cancel, or Enter to continue..."
read -r CONFIRM

# Check if Container App exists
if ! az containerapp show --name "${PROJECT_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
  echo "Container App '${PROJECT_NAME}' does not exist."
  exit 0
fi

echo "Destroying Container App '${PROJECT_NAME}'..."

# Remove from Terraform state if it exists (must be done first)
if terraform state show 'azurerm_container_app.main' >/dev/null 2>&1; then
  echo "Removing Container App from Terraform state..."
  terraform state rm 'azurerm_container_app.main' >/dev/null 2>&1 || true
fi

# Also remove role assignments that depend on it
for role_assignment in \
  'azurerm_role_assignment.container_app_kv_secrets_user' \
  'azurerm_role_assignment.container_app_acr_pull'; do
  if terraform state show "${role_assignment}" >/dev/null 2>&1; then
    echo "Removing ${role_assignment} from Terraform state..."
    terraform state rm "${role_assignment}" >/dev/null 2>&1 || true
  fi
done

# Destroy via Azure CLI (this actually deletes the resource)
echo "Deleting Container App in Azure..."
DELETE_OUTPUT=$(az containerapp delete \
  --name "${PROJECT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --yes \
  2>&1)
DELETE_EXIT=$?

if [[ ${DELETE_EXIT} -eq 0 ]]; then
  echo "✓ Container App deleted successfully"
else
  echo "⚠️  Deletion output:"
  echo "${DELETE_OUTPUT}"
  echo ""
  echo "Checking if Container App still exists..."
  if az containerapp show --name "${PROJECT_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
    echo "❌ Container App still exists. Trying force delete..."
    # Try without --yes flag (might need confirmation)
    az containerapp delete \
      --name "${PROJECT_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --yes \
      --output none || {
      echo "❌ Failed to delete Container App. You may need to delete it manually via Azure Portal or CLI"
      exit 1
    }
    echo "✓ Container App force deleted"
  else
    echo "✓ Container App does not exist (may have been deleted)"
  fi
fi

# Re-enable strict error handling
set -e

echo "✓ Container App '${PROJECT_NAME}' destroyed."
echo ""
echo "You can now run './scripts/azure_deploy.sh' to recreate it with the correct configuration."

