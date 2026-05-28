# AWS HealthOmics Study

Personal study repo covering a complete WGS germline variant calling pipeline — first locally with Docker + Nextflow, then deployed to AWS HealthOmics.

## Learning Path

```
Phase 1 (Local)               Phase 2 (Cloud)
─────────────────             ─────────────────────────────────
FASTQ → BWA-MEM2              HealthOmics Reference Store (hg38)
     → MarkDuplicates         HealthOmics Sequence Store (FASTQs)
     → BQSR (GATK)       →   HealthOmics Workflows (Nextflow)
     → HaplotypeCaller        HealthOmics Variant Store
     → VCF filtering          Query via API / Athena
```

The same Docker images used locally are pushed to ECR and referenced in the HealthOmics workflow — the only change is the Nextflow profile.

## Repo Structure

```
01_local_pipeline/
├── containers/          Official image references + ECR push script (no custom builds)
├── data/                Test data download scripts (GIAB NA12878 chr20)
├── scripts/             Step-by-step bash scripts (one per pipeline stage)
└── nextflow/            DSL2 Nextflow pipeline (main.nf + modules/)

02_aws_healthomics/
├── setup/               boto3 scripts for Reference Store, Sequence Store, ECR
├── workflows/           Register, run, and monitor HealthOmics workflow runs
└── analytics/           Variant Store creation and querying

03_notebooks/
├── 01_file_formats.ipynb   FASTQ, BAM, VCF, h5ad — structure and parsing
├── 02_bam_qc.ipynb         Coverage, mapping rate, insert size (pysam)
└── 03_vcf_analysis.ipynb   Variant filtering, Ti/Tv, annotation (cyvcf2)

docs/
├── tools_cheatsheet.md     Quick-reference commands for all tools
└── healthomics_concepts.md AWS HealthOmics service map and architecture
```

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker >= 24 | All tools run in containers |
| Nextflow >= 24 | Install via `curl -s https://get.nextflow.io \| bash` |
| AWS CLI v2 | `aws configure` with a profile that has HealthOmics + ECR + S3 permissions |
| Python >= 3.11 | For boto3 scripts and notebooks (`pip install boto3 pysam cyvcf2 biopython`) |

## Quick Start — Phase 1 (Local)

```bash
# 1. No build step needed — Nextflow pulls official images automatically.
#    See 01_local_pipeline/containers/README.md for the image registry.

# 2. Download test data (GIAB NA12878 chr20 subset, ~500 MB)
cd 01_local_pipeline/data
bash download_test_data.sh

# 3. Run step-by-step scripts (educational)
cd ../scripts
bash 01_qc_fastqc.sh
bash 02_align_bwa_mem2.sh
# ... continue through 06

# 4. Or run the full Nextflow pipeline
cd ../nextflow
nextflow run main.nf -profile local \
  --reads "../data/reads/*_R{1,2}.fastq.gz" \
  --reference "../data/reference/chr20.fa" \
  --known_sites "../data/reference/known_sites_chr20.vcf.gz"
```

## Quick Start — Phase 2 (AWS HealthOmics)

```bash
# 1. Pull official images and push to ECR (one-time setup)
cd 01_local_pipeline/containers
bash build_and_push.sh --ecr-prefix 123456789.dkr.ecr.us-east-1.amazonaws.com

# 2. Create HealthOmics stores
cd ../../02_aws_healthomics/setup
python 01_reference_store.py
python 02_sequence_store.py

# 3. Register and run the workflow
cd ../workflows
python register_workflow.py
python start_run.py
python monitor_run.py
```

## Tools Covered

| Tool | Version | Purpose |
|---|---|---|
| BWA-MEM2 | 2.2.1 | Fast read alignment to reference genome |
| SAMtools | 1.19 | BAM sorting, indexing, stats |
| GATK | 4.5.0.0 | MarkDuplicates, BQSR, HaplotypeCaller |
| FastQC | 0.12.1 | Per-read quality metrics |
| MultiQC | 1.21 | Aggregate QC reports |
| Nextflow | 24.x | Pipeline orchestration |
| AWS HealthOmics | — | Cloud-native genomics platform |
