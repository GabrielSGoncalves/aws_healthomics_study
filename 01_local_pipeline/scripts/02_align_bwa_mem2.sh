#!/usr/bin/env bash
# Step 2: Read Alignment with BWA-MEM2
#
# BWA-MEM2 is the successor to BWA-MEM with ~2x speed improvement via SIMD
# vectorization. It implements the seeding-and-extension alignment strategy:
#   1. Build a suffix array index of the reference (bwa-mem2 index)
#   2. Find maximal exact matches (MEMs) of query reads in the index
#   3. Extend seeds with Smith-Waterman to produce full alignments
#
# Read Group (@RG) tag is critical for downstream GATK steps:
#   - ID: unique run identifier (often flowcell + lane)
#   - SM: sample name — must match across all BAMs for the same sample
#   - LB: library — used by MarkDuplicates to distinguish optical from PCR dups
#   - PL: platform (ILLUMINA)
#   - PU: platform unit (flowcell barcode) — uniquely identifies sequencing run
#
# Output is piped directly to samtools sort to avoid writing an unsorted BAM.

set -euo pipefail

REF="../data/reference/chr20.fa"
R1="../data/reads/NA12878_chr20_R1.fastq.gz"
R2="../data/reads/NA12878_chr20_R2.fastq.gz"
RESULTS_DIR="../../results/alignment"
SAMPLE="NA12878"
THREADS=8

mkdir -p "${RESULTS_DIR}"

READ_GROUP="@RG\tID:ERR194147\tSM:${SAMPLE}\tLB:lib1\tPL:ILLUMINA\tPU:ERR194147"

echo "==> Aligning reads and sorting output BAM"
docker run --rm \
    -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
    -v "$(realpath "$(dirname "${R1}")"):/reads:ro" \
    -v "$(realpath "${RESULTS_DIR}"):/out" \
    bwa-mem2:2.2.1 \
    bash -c "
        bwa-mem2 mem \
            -t ${THREADS} \
            -R '${READ_GROUP}' \
            /ref/$(basename "${REF}") \
            /reads/$(basename "${R1}") \
            /reads/$(basename "${R2}") \
        | samtools sort \
            -@ ${THREADS} \
            -o /out/${SAMPLE}.sorted.bam
        samtools index /out/${SAMPLE}.sorted.bam
    "

echo "==> Alignment stats"
docker run --rm \
    -v "$(realpath "${RESULTS_DIR}"):/out" \
    bwa-mem2:2.2.1 \
    samtools flagstat /out/${SAMPLE}.sorted.bam

echo ""
echo "Output: ${RESULTS_DIR}/${SAMPLE}.sorted.bam"
