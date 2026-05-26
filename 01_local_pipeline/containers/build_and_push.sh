#!/usr/bin/env bash
# Build all pipeline Docker images locally and optionally push to ECR.
#
# Usage:
#   bash build_and_push.sh --build-only
#   bash build_and_push.sh --push --ecr-prefix 123456789.dkr.ecr.us-east-1.amazonaws.com
#
# After pushing, update nextflow/nextflow.config's healthomics profile to use
# the ECR URIs printed at the end of this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUILD_ONLY=false
PUSH=false
ECR_PREFIX=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-only) BUILD_ONLY=true; shift ;;
        --push)       PUSH=true; shift ;;
        --ecr-prefix) ECR_PREFIX="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

declare -A IMAGES=(
    ["bwa_mem2"]="bwa-mem2:2.2.1"
    ["gatk"]="gatk:4.5.0.0"
    ["fastqc"]="fastqc-multiqc:0.12.1"
)

for dir in "${!IMAGES[@]}"; do
    tag="${IMAGES[$dir]}"
    echo "==> Building ${tag} from ${dir}/"
    docker build -t "${tag}" "${SCRIPT_DIR}/${dir}"
done

echo ""
echo "All images built successfully:"
for dir in "${!IMAGES[@]}"; do
    echo "  ${IMAGES[$dir]}"
done

if [[ "${PUSH}" == true ]]; then
    if [[ -z "${ECR_PREFIX}" ]]; then
        echo "ERROR: --ecr-prefix is required when using --push"
        exit 1
    fi

    REGION="${ECR_PREFIX#*.dkr.ecr.}"
    REGION="${REGION%%.*}"
    ACCOUNT_ID="${ECR_PREFIX%%.*}"

    echo ""
    echo "==> Authenticating to ECR"
    aws ecr get-login-password --region "${REGION}" \
        | docker login --username AWS --password-stdin "${ECR_PREFIX}"

    echo ""
    for dir in "${!IMAGES[@]}"; do
        local_tag="${IMAGES[$dir]}"
        repo_name="${local_tag%%:*}"
        image_tag="${local_tag##*:}"
        ecr_uri="${ECR_PREFIX}/${repo_name}:${image_tag}"

        echo "==> Creating ECR repo (if not exists): ${repo_name}"
        aws ecr create-repository --repository-name "${repo_name}" \
            --region "${REGION}" 2>/dev/null || true

        echo "==> Pushing ${local_tag} -> ${ecr_uri}"
        docker tag "${local_tag}" "${ecr_uri}"
        docker push "${ecr_uri}"
    done

    echo ""
    echo "ECR URIs for nextflow.config healthomics profile:"
    for dir in "${!IMAGES[@]}"; do
        local_tag="${IMAGES[$dir]}"
        repo_name="${local_tag%%:*}"
        image_tag="${local_tag##*:}"
        echo "  ${repo_name}: ${ECR_PREFIX}/${repo_name}:${image_tag}"
    done
fi
