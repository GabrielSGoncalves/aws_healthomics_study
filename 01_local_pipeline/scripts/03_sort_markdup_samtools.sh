#!/usr/bin/env bash
# Step 3: Mark PCR Duplicates with GATK MarkDuplicates
#
# PCR amplification during library preparation creates identical read copies that
# are NOT biological variants. If left unmarked, duplicate reads inflate variant
# allele frequencies and increase false positive calls.
#
# MarkDuplicates strategy:
#   1. Groups reads that map to the same (start position, strand, mate start).
#   2. Within each group, keeps the read pair with the highest base quality sum
#      as the "primary" read.
#   3. Marks all other pairs as duplicates (FLAG bit 0x400).
#   4. Optionally removes duplicates entirely (--REMOVE_DUPLICATES); for WGS,
#      it is standard practice to mark-but-keep so metrics are preserved.
#
# Optical duplicates vs PCR duplicates:
#   - Optical: Adjacent clusters on the sequencing flow cell — pixel distance
#     threshold set by --OPTICAL_DUPLICATE_PIXEL_DISTANCE (default 100 for
#     HiSeq, 2500 for NovaSeq patterned flow cells).
#   - PCR: True amplification artifacts.

set -euo pipefail

RESULTS_DIR="../../results/alignment"
SAMPLE="NA12878"

echo "==> Marking duplicates"
docker run --rm \
    -v "$(realpath "${RESULTS_DIR}"):/data" \
    gatk:4.5.0.0 \
    gatk MarkDuplicates \
        --INPUT /data/${SAMPLE}.sorted.bam \
        --OUTPUT /data/${SAMPLE}.markdup.bam \
        --METRICS_FILE /data/${SAMPLE}.markdup_metrics.txt \
        --OPTICAL_DUPLICATE_PIXEL_DISTANCE 2500 \
        --CREATE_INDEX true \
        --VALIDATION_STRINGENCY SILENT

echo ""
echo "Duplicate metrics:"
grep -A2 "ESTIMATED_LIBRARY_SIZE" "${RESULTS_DIR}/${SAMPLE}.markdup_metrics.txt"
echo ""
echo "Output: ${RESULTS_DIR}/${SAMPLE}.markdup.bam"
