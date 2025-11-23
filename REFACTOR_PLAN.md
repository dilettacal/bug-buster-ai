# Azure Container Apps Refactoring Plan

## Goal
Refactor Terraform to follow Azure best practices:
- No secrets in Terraform state
- OIDC authentication (no passwords)
- Managed Identity for all access
- Key Vault secret references (not values)

---

## Step-by-Step Implementation Plan

### Phase 1: Clean Up Current State
1. ✅ Destroy all existing resources
2. ✅ Clean Terraform state
3. ✅ Remove old variables and logic

### Phase 2: Core Infrastructure (Terraform)

#### Step 1: Basic Resources
- [x] Resource Group (use existing)
- [x] Key Vault (RBAC enabled, no admin) - Name: `kv-bug-buster`
- [x] Container Registry (admin disabled)
- [x] Log Analytics Workspace
- [x] Container App Environment

#### Step 2: Service Principal & OIDC
- [x] Create Azure AD Application
- [x] Create Service Principal
- [x] Create Federated Identity Credential (GitHub Actions OIDC)
- [x] Grant SP roles:
  - [x] `AcrPush` on ACR
  - [x] `Contributor` on Resource Group

#### Step 3: Container App
- [x] Create Container App with SystemAssigned identity
- [x] Configure container (image, CPU, memory)
- [x] Configure ingress
- [x] **NO registry block** (add manually after creation)
- [x] **NO secrets block** (add manually after creation)
- [x] Grant Container App MI roles:
  - [x] `Key Vault Secrets User` on Key Vault
  - [x] `AcrPull` on ACR

#### Step 4: Outputs
- [ ] App URL
- [ ] ACR login server
- [ ] Key Vault name/URI
- [ ] SP Client ID (for GitHub Secrets)
- [ ] Tenant ID (for GitHub Secrets)
- [ ] Subscription ID (for GitHub Secrets)

### Phase 3: Post-Deployment Configuration (Manual/Azure CLI)

#### Step 5: Add Registry to Container App
- [x] Registry configured in Terraform (with Managed Identity)

#### Step 6: Add Secrets to Container App
```bash
az containerapp secret set \
  --name bug-buster \
  --resource-group bug-buster-rg \
  --secret-name openai-api-key \
  --key-vault-secret-id "https://<kv-name>.vault.azure.net/secrets/openai-api-key" \
  --identity System

az containerapp secret set \
  --name bug-buster \
  --resource-group bug-buster-rg \
  --secret-name semgrep-app-token \
  --key-vault-secret-id "https://<kv-name>.vault.azure.net/secrets/semgrep-app-token" \
  --identity System
```

### Phase 4: GitHub Actions Workflow

#### Step 7: Update Workflow
- [x] Remove `client-secret` (use OIDC only)
- [x] Add `id-token: write` permission
- [x] Add Docker build step
- [x] Add Docker push to ACR step
- [x] Add Container App revision update step

### Phase 5: Key Vault Secrets

#### Step 8: Add Secrets to Key Vault
- [ ] Add secrets to Key Vault (use `./scripts/azure_setup_keyvault.sh kv-bug-buster`)
```bash
az keyvault secret set \
  --vault-name kv-bug-buster \
  --name openai-api-key \
  --value <your-key>

az keyvault secret set \
  --vault-name kv-bug-buster \
  --name semgrep-app-token \
  --value <your-token>
```

### Phase 6: GitHub Secrets

#### Step 9: Add to GitHub Repository Secrets
- [ ] `AZURE_CLIENT_ID` (from Terraform output)
- [ ] `AZURE_TENANT_ID` (from Terraform output)
- [ ] `AZURE_SUBSCRIPTION_ID` (from Terraform output)
- [ ] **NO** `AZURE_CLIENT_SECRET` (OIDC doesn't need it)

---

## Key Principles

1. **Terraform NEVER touches secret values**
2. **Terraform NEVER builds/pushes Docker images**
3. **All access via Managed Identity or OIDC**
4. **No admin credentials anywhere**
5. **Secrets added manually after infrastructure is ready**

---

## Files to Modify

1. `terraform/azure/main.tf` - Core infrastructure
2. `terraform/azure/variables.tf` - Remove secret variables
3. `.github/workflows/azure-deploy.yml` - OIDC + Docker build/push
4. `scripts/azure_deploy.sh` - Remove secret handling

---

## Files to Remove/Update

- Remove Docker provider from Terraform
- Remove all `data.azurerm_key_vault_secret` (or make optional)
- Remove `use_key_vault` variable
- Remove `openai_api_key` variable
- Remove `semgrep_app_token` variable

