#!/usr/bin/env bash

# Script to clean Terraform state and related files
# This removes all local Terraform state, plans, and cache files
# WARNING: This will make Terraform lose track of existing resources!
# Usage: ./scripts/azure_clean_terraform.sh [--force]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/azure"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

maybe_echo() {
  if [[ "${QUIET:-0}" -eq 0 ]]; then
    echo "$@"
  fi
}

# Check for --force flag
FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

cd "${TF_DIR}"

maybe_echo "🧹 Terraform Cleanup Script"
maybe_echo "=========================="
maybe_echo ""

# Find files to clean
FILES_TO_REMOVE=()
DIRS_TO_REMOVE=()

# .terraform directory (provider plugins cache)
if [[ -d ".terraform" ]]; then
  DIRS_TO_REMOVE+=(".terraform")
fi

# terraform.tfstate.d directory (workspace state files)
if [[ -d "terraform.tfstate.d" ]]; then
  DIRS_TO_REMOVE+=("terraform.tfstate.d")
fi

# .tfplan files
while IFS= read -r -d '' file; do
  FILES_TO_REMOVE+=("$file")
done < <(find . -maxdepth 1 -name "*.tfplan" -type f -print0 2>/dev/null || true)

# terraform.tfstate files in root
while IFS= read -r -d '' file; do
  FILES_TO_REMOVE+=("$file")
done < <(find . -maxdepth 1 -name "terraform.tfstate*" -type f -print0 2>/dev/null || true)

# .terraform.lock.hcl
if [[ -f ".terraform.lock.hcl" ]]; then
  FILES_TO_REMOVE+=(".terraform.lock.hcl")
fi

# Check if there's anything to clean
if [[ ${#FILES_TO_REMOVE[@]} -eq 0 && ${#DIRS_TO_REMOVE[@]} -eq 0 ]]; then
  maybe_echo "✓ No Terraform state or cache files found. Nothing to clean."
  exit 0
fi

# Show what will be removed
maybe_echo "The following files and directories will be removed:"
maybe_echo ""

if [[ ${#DIRS_TO_REMOVE[@]} -gt 0 ]]; then
  maybe_echo "${YELLOW}Directories:${NC}"
  for dir in "${DIRS_TO_REMOVE[@]}"; do
    maybe_echo "  - ${dir}/"
  done
  maybe_echo ""
fi

if [[ ${#FILES_TO_REMOVE[@]} -gt 0 ]]; then
  maybe_echo "${YELLOW}Files:${NC}"
  for file in "${FILES_TO_REMOVE[@]}"; do
    maybe_echo "  - ${file}"
  done
  maybe_echo ""
fi

maybe_echo "${RED}⚠️  WARNING: This will remove all local Terraform state!${NC}"
maybe_echo "   - Terraform will lose track of existing Azure resources"
maybe_echo "   - You'll need to re-import resources or destroy them manually"
maybe_echo "   - This does NOT delete actual Azure resources"
maybe_echo ""

# Confirmation
if [[ "${FORCE}" -eq 0 ]]; then
  read -p "Are you sure you want to continue? (yes/no): " CONFIRM
  if [[ "${CONFIRM}" != "yes" ]]; then
    maybe_echo "Cancelled."
    exit 0
  fi
fi

# Remove directories
for dir in "${DIRS_TO_REMOVE[@]}"; do
  maybe_echo "Removing ${dir}/..."
  rm -rf "${dir}"
done

# Remove files
for file in "${FILES_TO_REMOVE[@]}"; do
  maybe_echo "Removing ${file}..."
  rm -f "${file}"
done

maybe_echo ""
maybe_echo "${GREEN}✓ Terraform state and cache files cleaned successfully!${NC}"
maybe_echo ""
maybe_echo "Next steps:"
maybe_echo "1. Run 'terraform init' to reinitialize"
maybe_echo "2. If resources exist in Azure, you may need to:"
maybe_echo "   - Import them: terraform import <resource_type>.<name> <azure_id>"
maybe_echo "   - Or destroy them manually via Azure Portal/CLI"
maybe_echo ""

