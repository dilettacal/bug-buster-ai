#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/azure"
ENV_FILE="${ROOT_DIR}/.env"

# Load .env file if it exists (for local development)
load_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    source "${ENV_FILE}"
    set +a
  fi
}

load_env_file

cd "${TF_DIR}"

# Get Key Vault name
PROJECT_NAME="${PROJECT_NAME:-bug-buster}"
KV_NAME="kv-${PROJECT_NAME}"
RESOURCE_GROUP="${RESOURCE_GROUP:-bug-buster-rg}"

echo "This will permanently destroy Key Vault '${KV_NAME}' and all its secrets."
echo "This action cannot be undone!"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Cancelled."
  exit 0
fi

# Check if Key Vault exists
if ! az keyvault show --name "${KV_NAME}" >/dev/null 2>&1; then
  echo "Key Vault '${KV_NAME}' does not exist."
  exit 0
fi

echo "Destroying Key Vault '${KV_NAME}'..."

# Purge Key Vault (required if soft-delete is enabled)
az keyvault purge --name "${KV_NAME}" >/dev/null 2>&1 || {
  # If purge fails, try deleting first (in case soft-delete is disabled)
  az keyvault delete --name "${KV_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1 || {
    echo "Error: Failed to destroy Key Vault. It may be in soft-delete state." >&2
    echo "Run: az keyvault purge --name ${KV_NAME}" >&2
    exit 1
  }
}

echo "✓ Key Vault '${KV_NAME}' destroyed."

# Remove from Terraform state if it exists
KV_STATE_NAME="azurerm_key_vault.main[0]"
if terraform state show "${KV_STATE_NAME}" >/dev/null 2>&1; then
  echo "Removing Key Vault from Terraform state..."
  terraform state rm "${KV_STATE_NAME}" >/dev/null 2>&1 || true
fi

echo "Done."

