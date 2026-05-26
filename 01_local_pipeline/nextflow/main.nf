#!/usr/bin/env nextflow
// WGS Germline Variant Calling Pipeline (DSL2)
// FASTQ -> BWA-MEM2 -> MarkDuplicates -> BQSR -> HaplotypeCaller -> filtered VCF
//
// Run locally:
//   nextflow run main.nf -profile local \
//     --reads "data/reads/*_R{1,2}.fastq.gz" \
//     --reference data/reference/chr20.fa \
//     --known_sites data/reference/dbsnp_chr20.vcf.gz
//
// Run on AWS HealthOmics:
//   nextflow run main.nf -profile healthomics \
//     --reads "s3://my-bucket/reads/*_R{1,2}.fastq.gz" \
//     --reference "omics://123456789/referencestore/ref-id/source" \
//     --known_sites "s3://my-bucket/resources/dbsnp_chr20.vcf.gz"

nextflow.enable.dsl = 2

include { FASTQC; MULTIQC }                          from './modules/fastqc'
include { BWA_MEM2 }                                 from './modules/bwa_mem2'
include { MARK_DUPLICATES }                          from './modules/mark_duplicates'
include { BQSR }                                     from './modules/bqsr'
include { HAPLOTYPECALLER; GENOTYPE_GVCFS; FILTER_VARIANTS } from './modules/haplotypecaller'

// Validate required parameters
if (!params.reads)       error "Missing required param: --reads"
if (!params.reference)   error "Missing required param: --reference"
if (!params.known_sites) error "Missing required param: --known_sites"

workflow {

    // --- Input channels ---

    // Pair FASTQs by sample ID, derive metadata from filename
    Channel
        .fromFilePairs(params.reads, checkIfExists: true)
        .map { id, files ->
            def meta = [id: id, library: 'lib1']
            [meta, files]
        }
        .set { ch_reads }

    // Reference genome files
    ch_fasta      = file(params.reference, checkIfExists: true)
    ch_fasta_fai  = file("${params.reference}.fai")
    ch_fasta_dict = file("${params.reference.replaceAll(/\.fa(sta)?$/, '')}.dict")

    // BWA-MEM2 index files (same directory as FASTA)
    ch_fasta_index = Channel.fromPath("${params.reference}*").collect()

    // Known variant sites for BQSR
    ch_known_sites     = file(params.known_sites, checkIfExists: true)
    ch_known_sites_tbi = file("${params.known_sites}.tbi")

    // --- Pipeline steps ---

    FASTQC(ch_reads)

    MULTIQC(
        FASTQC.out.zip.map { meta, zip -> zip }.collect()
    )

    BWA_MEM2(
        ch_reads,
        ch_fasta,
        ch_fasta_index
    )

    MARK_DUPLICATES(BWA_MEM2.out.bam)

    BQSR(
        MARK_DUPLICATES.out.bam,
        ch_fasta,
        ch_fasta_fai,
        ch_fasta_dict,
        ch_known_sites,
        ch_known_sites_tbi
    )

    HAPLOTYPECALLER(
        BQSR.out.bam,
        ch_fasta,
        ch_fasta_fai,
        ch_fasta_dict
    )

    GENOTYPE_GVCFS(
        HAPLOTYPECALLER.out.gvcf,
        ch_fasta,
        ch_fasta_fai,
        ch_fasta_dict
    )

    FILTER_VARIANTS(
        GENOTYPE_GVCFS.out.vcf,
        ch_fasta,
        ch_fasta_fai,
        ch_fasta_dict
    )
}
