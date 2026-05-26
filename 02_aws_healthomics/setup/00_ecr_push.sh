#!/usr/bin/env bash
# Create ECR repositories and push all pipeline Docker images.
#
# Run this BEFORE registering the workflow. HealthOmics pulls images from ECR
# (not Docker Hub), so all containers must be in your account's ECR registry.
#
# Prerequisites:
#   - AWS CLI configured with permissions for ECR and HealthOmics
#   - Docker images already built locally (run containers/build_and_push.sh --build-only)
#
# Usage:
#   bash 00_ecr_push.sh
#   bash 00_ecr_push.sh --region eu-west-1

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CONTAINERS_DIR="../../01_local_pipeline/containers"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --region) REGION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_PREFIX="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> Account: ${ACCOUNT_ID}"
echo "==> Region:  ${REGION}"
echo "==> ECR:     ${ECR_PREFIX}"
echo ""

# Build and push via the shared script
bash "${CONTAINERS_DIR}/build_and_push.sh" \
    --push \
    --ecr-prefix "${ECR_PREFIX}"

echo ""
echo "Update 01_local_pipeline/nextflow/nextflow.config:"
echo "  Set ECR = \"${ECR_PREFIX}\" in the healthomics profile."
