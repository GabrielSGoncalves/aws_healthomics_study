#!/usr/bin/env bash
# Step 4: Base Quality Score Recalibration (BQSR) with GATK
#
# Sequencers report per-base quality scores (Phred), but these scores are
# systematically biased — they vary by cycle position, dinucleotide context,
# and machine tile. BQSR corrects this bias using known variant sites as a
# calibration set (sites that differ from the reference for REAL biological
# reasons, not sequencing error).
#
# Two-step process:
#   1. BaseRecalibrator: Scans the BAM and builds a recalibration table by
#      comparing observed vs. expected error rates at known-variant sites.
#      Known sites (dbSNP, Mills indels) are EXCLUDED from error counting.
#   2. ApplyBQSR: Rewrites base quality scores in the BAM using the table.
#
# After BQSR, downstream GATK variant callers trust the quality scores and
# make better likelihood calculations. The effect is most visible at:
#   - Low-coverage positions where a single miscalled base matters
#   - Strand-specific error patterns (e.g., OxoG artifacts)

set -euo pipefail

REF="../data/reference/chr20.fa"
DBSNP="../data/reference/dbsnp_chr20.vcf.gz"
RESULTS_DIR="../../results/alignment"
SAMPLE="NA12878"

echo "==> Building recalibration table (BaseRecalibrator)"
docker run --rm \
    -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
    -v "$(realpath "$(dirname "${DBSNP}")"):/ref:ro" \
    -v "$(realpath "${RESULTS_DIR}"):/data" \
    gatk:4.5.0.0 \
    gatk BaseRecalibrator \
        --input /data/${SAMPLE}.markdup.bam \
        --reference /ref/$(basename "${REF}") \
        --known-sites /ref/$(basename "${DBSNP}") \
        --output /data/${SAMPLE}.recal.table

echo "==> Applying recalibration (ApplyBQSR)"
docker run --rm \
    -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
    -v "$(realpath "${RESULTS_DIR}"):/data" \
    gatk:4.5.0.0 \
    gatk ApplyBQSR \
        --input /data/${SAMPLE}.markdup.bam \
        --reference /ref/$(basename "${REF}") \
        --bqsr-recal-file /data/${SAMPLE}.recal.table \
        --output /data/${SAMPLE}.bqsr.bam

echo ""
echo "Output: ${RESULTS_DIR}/${SAMPLE}.bqsr.bam"
echo "Tip: Run AnalyzeCovariates to visualise the recalibration effect."
