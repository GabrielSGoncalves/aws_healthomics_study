# Phase 1: Local WGS Germline Variant Calling Pipeline

Full FASTQ-to-VCF pipeline for a single WGS sample, running entirely in Docker.

## Pipeline Overview

```
FASTQ (paired-end)
  │
  ├─ FastQC + MultiQC      → QC reports (scripts/01)
  │
  ▼
BWA-MEM2 alignment         → sorted BAM (scripts/02)
  │
  ▼
GATK MarkDuplicates        → markdup BAM + metrics (scripts/03)
  │
  ▼
GATK BQSR                  → recalibrated BAM (scripts/04)
  │
  ▼
GATK HaplotypeCaller       → GVCF (scripts/05)
  │
  ▼
GenotypeGVCFs + Filtration → final filtered VCF (scripts/06)
```

## Prerequisites

```bash
# Docker (all tools run in containers — no conda required)
docker --version    # >= 24.0

# Nextflow (for the automated pipeline)
curl -s https://get.nextflow.io | bash
nextflow -version   # >= 24.0

# Build Docker images first
cd containers && bash build_and_push.sh --build-only
```

## Option A: Step-by-Step Scripts (recommended for learning)

Run each script sequentially to understand what each tool does:

```bash
cd scripts
bash 01_qc_fastqc.sh           # FastQC quality reports
bash 02_align_bwa_mem2.sh      # Alignment → sorted BAM
bash 03_sort_markdup_samtools.sh  # Mark PCR duplicates
bash 04_bqsr_gatk.sh           # Base quality recalibration
bash 05_haplotypecaller_gatk.sh   # Variant calling → GVCF
bash 06_filter_vcf_gatk.sh     # Genotyping + hard filtering → VCF
```

Each script has inline comments explaining the tool's algorithm, key parameters,
and what to look for in the output.

## Option B: Full Nextflow Pipeline

Runs all steps automatically with parallelism, caching, and retry logic:

```bash
cd nextflow
nextflow run main.nf -profile local \
  --reads "../data/reads/*_R{1,2}.fastq.gz" \
  --reference "../data/reference/chr20.fa" \
  --known_sites "../data/reference/dbsnp_chr20.vcf.gz" \
  --outdir "../../results"
```

Add `-resume` to restart from the last successful step after a failure.

## Output Structure

```
results/
├── qc/
│   ├── NA12878_R1_fastqc.html
│   ├── NA12878_R2_fastqc.html
│   └── multiqc_report.html
├── alignment/
│   ├── NA12878.sorted.bam
│   ├── NA12878.markdup.bam
│   ├── NA12878.markdup_metrics.txt
│   └── NA12878.bqsr.bam
└── variants/
    ├── NA12878.g.vcf.gz        (GVCF — input for joint calling)
    ├── NA12878.raw.vcf.gz
    └── NA12878.final.vcf.gz    (filtered — use this for analysis)
```
