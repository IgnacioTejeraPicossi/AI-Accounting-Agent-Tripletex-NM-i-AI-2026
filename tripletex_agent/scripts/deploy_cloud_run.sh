#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-tripletex-agent}"
REGION="${REGION:-europe-north1}"
MEMORY="${MEMORY:-1Gi}"
TIMEOUT="${TIMEOUT:-300}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"

echo "Deploying ${SERVICE_NAME} to Cloud Run in ${REGION}..."

gcloud run deploy "${SERVICE_NAME}" \
  --source . \
  --region "${REGION}" \
  --allow-unauthenticated \
  --memory "${MEMORY}" \
  --timeout "${TIMEOUT}" \
  --min-instances "${MIN_INSTANCES}"

echo "Deployment finished."
echo "Health check example:"
echo "  curl https://YOUR-SERVICE-URL/health"
