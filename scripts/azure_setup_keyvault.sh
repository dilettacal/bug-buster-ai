#!/usr/bin/env bash

# Script to add secrets to Azure Key Vault
# Usage: ./scripts/azure_setup_keyvault.sh <key-vault-name>

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <key-vault-name>"
  echo ""
  echo "Example:"
  echo "  $0 kv-bug-buster"
  echo ""
  echo "You can get the Key Vault name from Terraform output:"
  echo "  terraform output key_vault_name"
  exit 1
fi

KEY_VAULT_NAME="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

# Load environment variables from .env file if it exists
load_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    source "${ENV_FILE}"
    set +a
  fi
}

load_env_file

# Check if secrets are set
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "Error: OPENAI_API_KEY not set. Please set it in your environment or .env file."
  exit 1
fi

if [[ -z "${SEMGREP_APP_TOKEN:-}" ]]; then
  echo "Error: SEMGREP_APP_TOKEN not set. Please set it in your environment or .env file."
  exit 1
fi

echo "Adding secrets to Key Vault: ${KEY_VAULT_NAME}"
echo ""

# Add OpenAI API key
echo "Adding OPENAI_API_KEY..."
az keyvault secret set \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "openai-api-key" \
  --value "${OPENAI_API_KEY}" \
  --output none

# Add Semgrep app token
echo "Adding SEMGREP_APP_TOKEN..."
az keyvault secret set \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "semgrep-app-token" \
  --value "${SEMGREP_APP_TOKEN}" \
  --output none

echo ""
echo "✓ Secrets successfully added to Key Vault!"
echo ""
echo "Next steps:"
echo "1. Deploy infrastructure: ./scripts/azure_deploy.sh"
echo "2. Configure Container App secrets manually via Azure Portal or CLI"
echo "   (Terraform does not manage secrets to avoid storing them in state)"

