# Deployment Status

## ✅ What's Complete

### Infrastructure (Terraform)
- [x] Resource Group
- [x] Key Vault (`kv-bug-buster`) with RBAC
- [x] Azure Container Registry (ACR) with admin disabled
- [x] Log Analytics Workspace
- [x] Container App Environment
- [x] Container App with Managed Identity
- [x] Registry configured in Container App (Managed Identity for ACR pull)
- [x] Role assignments:
  - [x] Container App MI → Key Vault Secrets User
  - [x] Container App MI → AcrPull on ACR
  - [x] GitHub Actions SP → AcrPush on ACR
  - [x] GitHub Actions SP → Contributor on Resource Group

### CI/CD
- [x] GitHub Actions workflow with OIDC
- [x] Docker build/push steps
- [x] Container App revision update step
- [x] Local deploy script handles infrastructure + image deployment

### Azure AD / OIDC
- [x] Service Principal created
- [x] Federated Identity Credential for GitHub Actions
- [x] Role assignments for GitHub Actions SP

## ❌ What's Still Missing

### 1. Key Vault Secrets (REQUIRED)
**Status:** Not done - App won't work without these

```bash
# Option 1: Use the setup script (reads from .env file)
./scripts/azure_setup_keyvault.sh kv-bug-buster

# Option 2: Manual
az keyvault secret set \
  --vault-name kv-bug-buster \
  --name openai-api-key \
  --value <your-key>

az keyvault secret set \
  --vault-name kv-bug-buster \
  --name semgrep-app-token \
  --value <your-token>
```

### 2. Container App Secrets Configuration (REQUIRED)
**Status:** Not done - App can't access Key Vault secrets

After adding secrets to Key Vault, configure Container App to reference them:

```bash
# Get Key Vault URI
KV_URI=$(terraform output -raw key_vault_uri)

# Add secrets to Container App
az containerapp secret set \
  --name bug-buster \
  --resource-group bug-buster-rg \
  --secret-name openai-api-key \
  --key-vault-secret-id "${KV_URI}/secrets/openai-api-key" \
  --identity System

az containerapp secret set \
  --name bug-buster \
  --resource-group bug-buster-rg \
  --secret-name semgrep-app-token \
  --key-vault-secret-id "${KV_URI}/secrets/semgrep-app-token" \
  --identity System
```

**Note:** After adding secrets, you need to update the Container App's environment variables to reference them. Check your app code to see what env var names it expects.

### 3. GitHub Secrets (REQUIRED for CI/CD)
**Status:** Not done - GitHub Actions won't work

Add these to GitHub Repository Secrets:
- `AZURE_CLIENT_ID` - Get from: `terraform output github_actions_client_id`
- `AZURE_TENANT_ID` - Get from: `terraform output tenant_id`
- `AZURE_SUBSCRIPTION_ID` - Get from: `terraform output subscription_id`

**Do NOT add `AZURE_CLIENT_SECRET`** - OIDC doesn't need it.

## 🔍 Troubleshooting Container App Update Error

If you're seeing "Failed to update Container App", check:

1. **Container App exists?**
   ```bash
   az containerapp show --name bug-buster --resource-group bug-buster-rg
   ```

2. **Permissions?**
   ```bash
   az account show  # Make sure you're logged in
   ```

3. **Image exists in ACR?**
   ```bash
   az acr repository show-tags --name bugbusteracr --repository bug-buster
   ```

4. **Try manual update to see actual error:**
   ```bash
   az containerapp update \
     --name bug-buster \
     --resource-group bug-buster-rg \
     --image bugbusteracr.azurecr.io/bug-buster:local-397e015
   ```

## 📋 Quick Start Checklist

1. [ ] Add secrets to Key Vault: `./scripts/azure_setup_keyvault.sh kv-bug-buster`
2. [ ] Configure Container App secrets (see above)
3. [ ] Update Container App env vars to reference secrets (if needed)
4. [ ] Add GitHub Secrets (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)
5. [ ] Test locally: `./scripts/azure_deploy.sh`
6. [ ] Test CI/CD: Push to GitHub and check Actions

