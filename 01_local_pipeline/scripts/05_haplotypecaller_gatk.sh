#!/usr/bin/env bash
# Step 5: Germline Variant Calling with GATK HaplotypeCaller
#
# HaplotypeCaller calls SNPs and indels simultaneously using a local de novo
# assembly approach:
#   1. Identifies ActiveRegions — genomic windows with evidence of variation
#      (soft-clipped reads, mismatches above a threshold).
#   2. Performs local assembly of reads in each ActiveRegion using a De Bruijn
#      graph to reconstruct haplotypes.
#   3. Re-aligns reads to each candidate haplotype (not the reference) to
#      avoid reference bias.
#   4. Computes per-sample genotype likelihoods (PL field in VCF) using the
#      Pair HMM model.
#   5. Calls genotypes via Bayes' theorem: GT, GQ fields.
#
# GVCF mode (--emit-ref-confidence GVCF):
#   Emits a record for EVERY site, not just variants. Non-variant sites get a
#   <NON_REF> symbolic allele and are block-compressed by GQ band. This is the
#   recommended mode for joint genotyping across many samples with
#   GenomicsDBImport + GenotypeGVCFs.
#
# For this tutorial (single sample), we call directly to VCF.

set -euo pipefail

REF="../data/reference/chr20.fa"
RESULTS_DIR="../../results"
ALIGNMENT_DIR="${RESULTS_DIR}/alignment"
VARIANTS_DIR="${RESULTS_DIR}/variants"
SAMPLE="NA12878"

mkdir -p "${VARIANTS_DIR}"

echo "==> Calling variants with HaplotypeCaller"
docker run --rm \
    -v "$(realpath "$(dirname "${REF}")"):/ref:ro" \
    -v "$(realpath "${ALIGNMENT_DIR}"):/bam:ro" \
    -v "$(realpath "${VARIANTS_DIR}"):/out" \
    broadinstitute/gatk:4.5.0.0 \
    gatk HaplotypeCaller \
        --reference /ref/$(basename "${REF}") \
        --input /bam/${SAMPLE}.bqsr.bam \
        --output /out/${SAMPLE}.g.vcf.gz \
        --emit-ref-confidence GVCF \
        --native-pair-hmm-threads 4

echo ""
echo "Output: ${VARIANTS_DIR}/${SAMPLE}.g.vcf.gz"
echo "Next: Run GenotypeGVCFs for single-sample genotyping, or"
echo "      GenomicsDBImport + GenotypeGVCFs for multi-sample joint calling."
