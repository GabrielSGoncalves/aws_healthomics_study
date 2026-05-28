#!/usr/bin/env bash
# Step 1: Quality Control with FastQC + MultiQC
#
# FastQC evaluates each FASTQ file and produces an HTML report per sample.
# MultiQC aggregates multiple reports into a single summary — essential when
# you have dozens of samples.
#
# Key metrics to review in the FastQC report:
#   - Per base sequence quality: Phred scores should be >Q28 for most positions.
#     Scores drop at the 3' end — trim if they fall below Q20.
#   - Sequence duplication levels: >50% duplication is normal for WGS; flagged
#     as "WARN" but expected. MarkDuplicates (step 3) handles this.
#   - Adapter content: Should be near zero after sequencer demuxing. If adapters
#     are present, trim with Trimmomatic or Trim Galore before aligning.
#   - GC content: Should match the species GC% (~41% for human). Bimodal
#     distribution can indicate contamination.

set -euo pipefail

READS_DIR="../data/reads"
RESULTS_DIR="../../results/qc"
THREADS=4

mkdir -p "${RESULTS_DIR}"

echo "==> Running FastQC on all FASTQ files"
docker run --rm \
    -v "$(realpath "${READS_DIR}"):/reads:ro" \
    -v "$(realpath "${RESULTS_DIR}"):/out" \
    quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0 \
    bash -c "fastqc --outdir /out --threads ${THREADS} /reads/*.fastq.gz"

echo "==> Aggregating reports with MultiQC"
docker run --rm \
    -v "$(realpath "${RESULTS_DIR}"):/data" \
    quay.io/biocontainers/multiqc:1.21--pyhdfd78af_0 \
    multiqc /data --outdir /data --filename multiqc_report.html

echo ""
echo "Reports written to: ${RESULTS_DIR}/"
echo "Open ${RESULTS_DIR}/multiqc_report.html in your browser."
