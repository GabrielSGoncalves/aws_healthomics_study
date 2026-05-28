#!/usr/bin/env bash
# Push official pipeline images to ECR so AWS HealthOmics can access them.
#
# All pipeline stages use official, community-maintained images — no custom
# Dockerfiles are built.  This script:
#   1. Pulls each official image from its upstream registry.
#   2. Retags it with a clean ECR URI.
#   3. Creates the ECR repository (if it doesn't exist) and pushes.
#
# Usage:
#   bash build_and_push.sh --ecr-prefix 123456789012.dkr.ecr.us-east-1.amazonaws.com
#
# For local runs with 'nextflow run main.nf -profile local', Nextflow pulls
# the official images automatically — no action required here.

set -euo pipefail

ECR_PREFIX=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ecr-prefix) ECR_PREFIX="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "${ECR_PREFIX}" ]]; then
    echo "Usage: bash build_and_push.sh --ecr-prefix <account>.dkr.ecr.<region>.amazonaws.com"
    exit 1
fi

REGION="${ECR_PREFIX#*.dkr.ecr.}"
REGION="${REGION%%.*}"

# ---------------------------------------------------------------------------
# Official image → ECR repo:tag mapping
# Keep in sync with nextflow/nextflow.config
# ---------------------------------------------------------------------------
declare -A IMAGES=(
    # official upstream URI                                                                              ecr-repo:tag
    ["quay.io/biocontainers/mulled-v2-e5d375990341c5aef3c9aff74f96f66f65375ef6:2cdf6bf1e92acbeb9b2834b1c58754167173a410-0"]="bwa-mem2:2.2.1"
    ["quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"]="fastqc:0.12.1"
    ["quay.io/biocontainers/multiqc:1.21--pyhdfd78af_0"]="multiqc:1.21"
    ["broadinstitute/gatk:4.5.0.0"]="gatk:4.5.0.0"
)

echo "==> Authenticating to ECR (${REGION})"
aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${ECR_PREFIX}"

echo ""
for upstream in "${!IMAGES[@]}"; do
    ecr_tag="${IMAGES[$upstream]}"
    repo_name="${ecr_tag%%:*}"
    ecr_uri="${ECR_PREFIX}/${ecr_tag}"

    echo "--- ${repo_name} ---"
    echo "    upstream : ${upstream}"
    echo "    ecr uri  : ${ecr_uri}"

    echo "==> Pulling ${upstream}"
    docker pull "${upstream}"

    echo "==> Creating ECR repo (if not exists): ${repo_name}"
    aws ecr create-repository \
        --repository-name "${repo_name}" \
        --region "${REGION}" \
        --image-scanning-configuration scanOnPush=true \
        2>/dev/null || true

    echo "==> Tagging and pushing -> ${ecr_uri}"
    docker tag "${upstream}" "${ecr_uri}"
    docker push "${ecr_uri}"
    echo ""
done

echo "All images pushed to ECR."
echo ""
echo "Update nextflow/nextflow.config — set ECR prefix to:"
echo "  ${ECR_PREFIX}"
