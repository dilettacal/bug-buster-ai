# Deployment Guide

## Azure Setup

Sign in to the Azure Portal, ensure your subscription is active, set a cost budget, and create a resource group named `bug-buster-rg` in your chosen region before running the CLI commands below.

### Install Azure CLI (macOS Homebrew)

```bash
brew update && brew install azure-cli
```

### Verify Azure CLI Installation

```bash
az --version
```

### Authenticate the CLI with Your Azure Account

```bash
az login
```

### Confirm Available Subscriptions

```bash
az account list --output table
```

### Confirm Resource Groups in Your Subscription

```bash
az group list --output table
```

## Azure Deployment

These commands provision and manage the Azure resources that host the Bug Buster application.

### Confirm Terraform CLI Availability

```bash
terraform version
```

### Install Terraform if Missing (macOS)

```bash
brew install terraform
```

### Load `.env` Variables for Terraform (macOS/Linux)

```bash
export $(cat .env | xargs)
echo "OpenAI key loaded: ${OPENAI_API_KEY:0:8}..."
echo "Semgrep token loaded: ${SEMGREP_APP_TOKEN:0:8}..."
```

### Load `.env` Variables for Terraform (Windows PowerShell)

### Switch to the Azure Terraform Configuration

```bash
cd terraform/azure
```

### Initialize Terraform Backend and Providers

```bash
# Run after cloning or whenever .terraform/ has been cleaned
terraform init
# Run once per new environment to create the workspace
terraform workspace new azure
# Use for every session to switch into the workspace
terraform workspace select azure
terraform workspace show
```

### Register Required Azure Resource Providers

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
az provider show --namespace Microsoft.App --query "registrationState" -o tsv
az provider show --namespace Microsoft.OperationalInsights --query "registrationState" -o tsv
```

### Plan the Azure Infrastructure Deployment

```bash
terraform plan \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

### Apply the Terraform Plan (macOS/Linux)

```bash
terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

### Force Rebuild of Container Image When Needed

```bash
terraform taint docker_image.app
terraform taint docker_registry_image.app
```

### Retrieve the Deployed Application URL

```bash
terraform output app_url
```

### Stream Logs from the Running Container App

```bash
az containerapp logs show --name bug-buster --resource-group bug-buster-rg --follow
```

### Review Recent Azure Consumption for the Deployment

```bash
az consumption usage list \
  --start-date $(date -u -d '7 days ago' '+%Y-%m-%d') \
  --end-date $(date -u '+%Y-%m-%d') \
  --query "[?contains(instanceId, 'bug-buster')].{Resource:instanceName, Cost:pretaxCost, Currency:currency}" \
  --output table
```

### Destroy Azure Resources After Testing (macOS/Linux)

```bash
terraform destroy \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```


### Inspect Remaining Resources in the Resource Group

```bash
az resource list --resource-group bug-buster-rg --output table
```

### Confirm the ACR Has Been Removed

```bash
az acr show --name bugbusteracr --resource-group bug-buster-rg
```

### Delete the Resource Group When Finished

```bash
az group delete --name bug-buster-rg --yes
```

### Inspect Terraform State Details

```bash
terraform show
terraform state list
```

### Redeploy with a New Docker Image Tag

```bash
terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN" \
  -var="docker_image_tag=v2"
```

### Recreate the Azure Workspace View When Troubleshooting

```bash
terraform workspace list
terraform workspace select azure
```

### Confirm the Resource Group Exists

```bash
az group show --name bug-buster-rg
```

### Recheck Container App Logs After Changes

```bash
az containerapp logs show --name bug-buster --resource-group bug-buster-rg
```

