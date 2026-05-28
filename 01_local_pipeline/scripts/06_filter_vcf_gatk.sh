#!/usr/bin/env bash
# Step 6: Variant Filtering with GATK
#
# Raw variant calls contain false positives. Two filtering strategies:
#
# 1. VQSR (Variant Quality Score Recalibration) — RECOMMENDED for large cohorts
#    Trains a Gaussian mixture model on true-positive variants (from HapMap,
#    1000G, Omni, dbSNP) to assign a recalibration score (VQSLOD) to each
#    variant. Requires >30 WGS samples to have enough data for model training.
#    Separate models for SNPs and indels.
#
# 2. Hard Filtering — used here because we have a single sample
#    Apply fixed JEXL filter expressions on INFO field annotations:
#    For SNPs:
#      - QD < 2.0   : Low quality-by-depth (weak evidence)
#      - MQ < 40.0  : Low mapping quality of supporting reads
#      - FS > 60.0  : High FisherStrand bias (strand-specific error)
#      - SOR > 3.0  : High StrandOddsRatio (strand imbalance)
#      - MQRankSum < -12.5 : Mapping quality difference ref vs alt reads
#      - ReadPosRankSum < -8.0 : Alt alleles near read ends (artifact signal)
#    For INDELs:
#      - QD < 2.0, FS > 200, SOR > 10 (less strict than SNPs)
#
# Filtered variants get FILTER != PASS — they are NOT removed.

set -euo pipefail

REF="../data/reference/chr20.fa"
RESULTS_DIR="../../results"
VARIANTS_DIR="${RESULTS_DIR}/variants"
SAMPLE="NA12878"

echo "==> Genotyping GVCFs (single-sample joint genotyping)"
docker run --rm \
    -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
    -v "$(realpath "${VARIANTS_DIR}"):/out" \
    broadinstitute/gatk:4.5.0.0 \
    gatk GenotypeGVCFs \
        --reference /ref/$(basename "${REF}") \
        --variant /out/${SAMPLE}.g.vcf.gz \
        --output /out/${SAMPLE}.raw.vcf.gz

echo "==> Separating SNPs and indels (SelectVariants)"
for TYPE in SNP INDEL; do
    docker run --rm \
        -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
        -v "$(realpath "${VARIANTS_DIR}"):/out" \
        broadinstitute/gatk:4.5.0.0 \
        gatk SelectVariants \
            --reference /ref/$(basename "${REF}") \
            --variant /out/${SAMPLE}.raw.vcf.gz \
            --select-type-to-include "${TYPE}" \
            --output /out/${SAMPLE}.raw.$(echo "${TYPE}" | tr '[:upper:]' '[:lower:]').vcf.gz
done

echo "==> Hard filtering SNPs"
docker run --rm \
    -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
    -v "$(realpath "${VARIANTS_DIR}"):/out" \
    broadinstitute/gatk:4.5.0.0 \
    gatk VariantFiltration \
        --reference /ref/$(basename "${REF}") \
        --variant /out/${SAMPLE}.raw.snp.vcf.gz \
        --filter-expression "QD < 2.0"            --filter-name "QD2" \
        --filter-expression "MQ < 40.0"           --filter-name "MQ40" \
        --filter-expression "FS > 60.0"           --filter-name "FS60" \
        --filter-expression "SOR > 3.0"           --filter-name "SOR3" \
        --filter-expression "MQRankSum < -12.5"   --filter-name "MQRankSum-12.5" \
        --filter-expression "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8" \
        --output /out/${SAMPLE}.filtered.snp.vcf.gz

echo "==> Hard filtering indels"
docker run --rm \
    -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
    -v "$(realpath "${VARIANTS_DIR}"):/out" \
    broadinstitute/gatk:4.5.0.0 \
    gatk VariantFiltration \
        --reference /ref/$(basename "${REF}") \
        --variant /out/${SAMPLE}.raw.indel.vcf.gz \
        --filter-expression "QD < 2.0"    --filter-name "QD2" \
        --filter-expression "FS > 200.0"  --filter-name "FS200" \
        --filter-expression "SOR > 10.0"  --filter-name "SOR10" \
        --output /out/${SAMPLE}.filtered.indel.vcf.gz

echo "==> Merging filtered SNPs + indels"
docker run --rm \
    -v "$(realpath "${VARIANTS_DIR}"):/out" \
    broadinstitute/gatk:4.5.0.0 \
    gatk MergeVcfs \
        --INPUT /out/${SAMPLE}.filtered.snp.vcf.gz \
        --INPUT /out/${SAMPLE}.filtered.indel.vcf.gz \
        --OUTPUT /out/${SAMPLE}.final.vcf.gz

echo ""
echo "Final VCF: ${VARIANTS_DIR}/${SAMPLE}.final.vcf.gz"
echo "PASS variants only:"
docker run --rm \
    -v "$(realpath "${VARIANTS_DIR}"):/out" \
    broadinstitute/gatk:4.5.0.0 \
    bash -c "zcat /out/${SAMPLE}.final.vcf.gz | grep -v '^#' | awk '\$7==\"PASS\"' | wc -l"
