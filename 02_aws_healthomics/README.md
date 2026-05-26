# Phase 2: AWS HealthOmics

Port the local WGS pipeline to AWS HealthOmics for scalable, cloud-native execution.

## AWS HealthOmics Service Map

```
┌─────────────────────────────────────────────────────────────────┐
│                       AWS HealthOmics                           │
│                                                                 │
│  ┌──────────────────┐    ┌──────────────────┐                  │
│  │  Reference Store │    │  Sequence Store  │                  │
│  │  (hg38 FASTA)    │    │  (FASTQ ReadSets)│                  │
│  └────────┬─────────┘    └────────┬─────────┘                  │
│           │                       │                            │
│           └───────────┬───────────┘                            │
│                       │                                        │
│              ┌────────▼─────────┐                              │
│              │  Workflow Engine  │  ← Nextflow / WDL           │
│              │  (Managed compute)│    Containers from ECR      │
│              └────────┬─────────┘                              │
│                       │                                        │
│              ┌────────▼─────────┐    ┌──────────────────┐     │
│              │   S3 (outputs)   │───▶│  Variant Store   │     │
│              │   VCF, BAM, QC   │    │  (Parquet/Athena)│     │
│              └──────────────────┘    └──────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

## Execution Order

```bash
# Step 0 — Push Docker images to ECR (do this once)
cd setup && bash 00_ecr_push.sh

# Step 1 — Create Reference Store and import hg38 chr20
python setup/01_reference_store.py --bucket my-bucket

# Step 2 — Create Sequence Store and import FASTQ ReadSet
python setup/02_sequence_store.py --bucket my-bucket

# Step 3 — Register the Nextflow workflow
python workflows/register_workflow.py

# Step 4 — Start a workflow run
python workflows/start_run.py \
  --workflow-id <id from step 3> \
  --role-arn arn:aws:iam::ACCOUNT:role/HealthOmicsWorkflowRole \
  --output-uri s3://my-bucket/results/ \
  --reads "s3://my-bucket/reads/*_R{1,2}.fastq.gz" \
  --reference omics://ACCOUNT/referencestore/STORE-ID/source/REF-ID \
  --known-sites s3://my-bucket/resources/dbsnp_chr20.vcf.gz

# Step 5 — Monitor the run
python workflows/monitor_run.py --run-id <run-id>

# Step 6 — Import results into Variant Store and query
python analytics/create_variant_store.py \
  --reference-arn arn:aws:omics:... \
  --vcf s3://my-bucket/results/NA12878.final.vcf.gz

python analytics/query_variants.py \
  --store-name wgs-study-variants \
  --athena-output-uri s3://my-bucket/athena-results/
```

## IAM Setup

The `HealthOmicsWorkflowRole` needs the permissions in `setup/iam_policy.json`.
Create it with:

```bash
aws iam create-role \
  --role-name HealthOmicsWorkflowRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "omics.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam put-role-policy \
  --role-name HealthOmicsWorkflowRole \
  --policy-name HealthOmicsWorkflowPolicy \
  --policy-document file://setup/iam_policy.json
```

## Key Differences: Local vs HealthOmics

| Aspect | Local | HealthOmics |
|---|---|---|
| Images | Docker Hub / local | ECR (same images) |
| Nextflow profile | `local` | `healthomics` |
| Reference | File path | `omics://` URI |
| Reads | File path | S3 URI |
| Compute | Laptop | Managed, auto-scaled |
| Cost | Free | Pay-per-compute-second |
