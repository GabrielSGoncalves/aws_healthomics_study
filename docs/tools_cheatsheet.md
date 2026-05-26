# Bioinformatics Tools Quick Reference

## BWA-MEM2

```bash
# Index a reference genome (required once before alignment)
bwa-mem2 index reference.fa

# Align paired-end reads; pipe to samtools sort in one step
bwa-mem2 mem -t 8 \
    -R "@RG\tID:sample1\tSM:sample1\tLB:lib1\tPL:ILLUMINA" \
    reference.fa R1.fastq.gz R2.fastq.gz \
  | samtools sort -@ 8 -o sample.sorted.bam

# Check alignment stats
samtools flagstat sample.sorted.bam
samtools idxstats sample.sorted.bam    # reads per chromosome
```

**Key flags:**
- `-t` — threads
- `-R` — read group tag (required for GATK)
- `-a` — output all alignments (multi-mappers)

---

## SAMtools

```bash
# Sort BAM
samtools sort -@ 8 -o out.sorted.bam in.bam

# Index BAM (creates .bai)
samtools index sample.bam

# View alignments in a region
samtools view -h sample.bam chr20:1000000-2000000 | head -50

# Coverage stats (per chromosome)
samtools coverage sample.bam

# Depth at specific positions
samtools depth -r chr20:1000000-1010000 sample.bam

# Stats summary
samtools stats sample.bam | grep "^SN"

# Extract only properly paired, non-duplicate reads
samtools view -b -F 1804 -f 2 sample.bam > clean.bam
```

**FLAG values** (additive):
| Bit | Decimal | Meaning |
|---|---|---|
| 0x1 | 1 | Read is paired |
| 0x2 | 2 | Read mapped in proper pair |
| 0x4 | 4 | Read is unmapped |
| 0x10 | 16 | Read on reverse strand |
| 0x400 | 1024 | PCR or optical duplicate |

---

## GATK4

### MarkDuplicates
```bash
gatk MarkDuplicates \
    -I input.bam -O markdup.bam \
    -M markdup_metrics.txt \
    --OPTICAL_DUPLICATE_PIXEL_DISTANCE 2500   # 2500 for NovaSeq, 100 for HiSeq
```

### BQSR (2 steps)
```bash
# Step 1: Build recalibration table
gatk BaseRecalibrator \
    -I markdup.bam -R ref.fa \
    --known-sites dbsnp.vcf.gz \
    -O recal.table

# Step 2: Apply recalibration
gatk ApplyBQSR \
    -I markdup.bam -R ref.fa \
    --bqsr-recal-file recal.table \
    -O bqsr.bam
```

### HaplotypeCaller
```bash
# Single-sample GVCF mode (recommended)
gatk HaplotypeCaller \
    -R ref.fa -I bqsr.bam \
    -O sample.g.vcf.gz \
    --emit-ref-confidence GVCF

# Joint genotyping from multiple GVCFs
gatk GenomicsDBImport \
    -V sample1.g.vcf.gz -V sample2.g.vcf.gz \
    --genomicsdb-workspace-path gendb://chr20 \
    -L chr20

gatk GenotypeGVCFs \
    -R ref.fa -V gendb://chr20 \
    -O cohort.vcf.gz
```

### Variant Filtration (hard filters)
```bash
# Select SNPs only
gatk SelectVariants -V raw.vcf.gz --select-type SNP -O snps.vcf.gz

# Apply hard filters to SNPs
gatk VariantFiltration -V snps.vcf.gz -R ref.fa \
    --filter-expression "QD < 2.0"  --filter-name "QD2" \
    --filter-expression "FS > 60.0" --filter-name "FS60" \
    --filter-expression "MQ < 40.0" --filter-name "MQ40" \
    -O snps.filtered.vcf.gz
```

### Useful GATK commands
```bash
# Count variants by filter
gatk CountVariants -V sample.vcf.gz

# Validate a VCF
gatk ValidateVariants -V sample.vcf.gz -R ref.fa

# Variant stats
gatk CollectVariantCallingMetrics \
    -I sample.vcf.gz --DBSNP dbsnp.vcf.gz \
    -O metrics
```

---

## Nextflow

```bash
# Run a pipeline
nextflow run main.nf -profile local

# Resume from last successful step (uses cached results)
nextflow run main.nf -profile local -resume

# Run with custom parameters
nextflow run main.nf -profile local \
    --reads "data/*_R{1,2}.fastq.gz" \
    --reference data/ref.fa \
    --outdir my_results

# List cached runs
nextflow log

# Show process timeline for a run
nextflow log <run-name> -f process,status,duration

# Clean cached work
nextflow clean -f

# Test a pipeline without running (dry-run concept)
nextflow run main.nf -preview

# Pull a pipeline from nf-core
nextflow pull nf-core/sarek
```

**Common issues:**
- `Process exceeded memory limit` → increase memory in `nextflow.config` with `memory = '16.GB'`
- `Cannot find path` → check that file globs are quoted and `checkIfExists: true`
- Container issues → verify Docker daemon is running and image exists locally

---

## AWS HealthOmics CLI

```bash
# List Reference Stores
aws omics list-reference-stores --region us-east-1

# List references in a store
aws omics list-references --reference-store-id STORE_ID

# List Sequence Stores
aws omics list-sequence-stores

# List read sets
aws omics list-read-sets --sequence-store-id STORE_ID

# List registered workflows
aws omics list-workflows --type PRIVATE

# Get workflow details
aws omics get-workflow --id WORKFLOW_ID --type PRIVATE

# List workflow runs
aws omics list-runs

# Get run details and status
aws omics get-run --id RUN_ID

# List tasks within a run
aws omics list-run-tasks --id RUN_ID

# Get task details and logs
aws omics get-run-task --id RUN_ID --task-id TASK_ID

# Cancel a run
aws omics cancel-run --id RUN_ID
```

---

## BCFtools (VCF manipulation)

```bash
# View VCF stats
bcftools stats input.vcf.gz | grep "^SN"

# Filter to PASS variants only
bcftools view -f PASS input.vcf.gz -o pass.vcf.gz -O z

# Extract specific samples
bcftools view -s NA12878,NA12879 cohort.vcf.gz

# Annotate with dbSNP IDs
bcftools annotate -a dbsnp.vcf.gz -c ID input.vcf.gz

# Merge two VCFs
bcftools merge sample1.vcf.gz sample2.vcf.gz -O z -o merged.vcf.gz

# Ti/Tv ratio
bcftools stats input.vcf.gz | grep "Ts/Tv"
```
