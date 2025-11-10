#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/azure"

QUIET=0
PLAN_FILE=".tfplan"

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

if [[ -z "${OPENAI_API_KEY:-}" || -z "${SEMGREP_APP_TOKEN:-}" ]]; then
  echo "Required environment variables OPENAI_API_KEY and SEMGREP_APP_TOKEN are not set." >&2
  exit 1
fi

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

TF_VARS=(
  "-var=openai_api_key=${OPENAI_API_KEY}"
  "-var=semgrep_app_token=${SEMGREP_APP_TOKEN}"
)

if [[ -n "${DOCKER_IMAGE_TAG:-}" ]]; then
  TF_VARS+=("-var=docker_image_tag=${DOCKER_IMAGE_TAG}")
fi

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

