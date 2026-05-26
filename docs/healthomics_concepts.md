# AWS HealthOmics — Concepts and Architecture

## Service Overview

AWS HealthOmics is a fully managed service for storing, processing, and querying genomic and multimodal health data. It removes the need to manage compute infrastructure, reference data servers, or variant databases.

## Core Components

```
┌──────────────────────────────────────────────────────────────────────┐
│                        AWS HealthOmics                               │
│                                                                      │
│  ┌────────────────────┐   ┌────────────────────┐                   │
│  │   Reference Store  │   │   Sequence Store   │                   │
│  │                    │   │                    │                   │
│  │  • hg38, hg19,     │   │  • FASTQs, BAMs,   │                   │
│  │    custom genomes  │   │    CRAMs stored    │                   │
│  │  • ORAv2 compressed│   │    as ReadSets     │                   │
│  │  • Indexed for fast│   │  • Quality-checked │                   │
│  │    random access   │   │    on import       │                   │
│  └─────────┬──────────┘   └──────────┬─────────┘                   │
│            │                         │                              │
│            └────────────┬────────────┘                              │
│                         │                                           │
│              ┌──────────▼──────────┐                                │
│              │   Workflow Engine   │                                 │
│              │                     │                                │
│              │  • Nextflow (DSL2)  │ ← ECR containers               │
│              │  • WDL              │ ← IAM role                     │
│              │  • Managed compute  │ ← S3 outputs                  │
│              │  • Auto-scaling     │                                │
│              └──────────┬──────────┘                                │
│                         │                                           │
│            ┌────────────┴───────────────────┐                       │
│            │                                │                       │
│  ┌─────────▼──────────┐       ┌─────────────▼──────────┐           │
│  │   S3 (raw outputs) │       │    Variant Store        │           │
│  │   BAM, VCF, QC     │       │                        │           │
│  └────────────────────┘       │  • Parquet columnar     │           │
│                               │  • Athena queryable     │           │
│                               │  • Lake Formation auth  │           │
│                               └────────────────────────┘           │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Reference Store

**What it does:**  
Stores reference genomes in ORAv2 (Optimal Reference Compression) format — a compression standard purpose-built for reference sequences. The store handles indexing (no .fai or .dict files to manage).

**Key concepts:**
- One Reference Store per region (regional resource)
- References are immutable once imported — version by creating new references
- Workflows reference genomes via `omics://` URIs, not S3 paths
- Supports FASTA input; compressed and indexed on import

**When to use:**  
Import hg38 once, reference it from all workflow runs. No need to re-stage reference to S3 per run.

```
omics://<account-id>/referencestore/<store-id>/source/<reference-id>
```

---

## Sequence Store

**What it does:**  
Stores raw sequencing data (FASTQ, BAM, CRAM) as versioned, immutable **ReadSets**. Validates file format on import and computes checksums.

**Key concepts:**
- ReadSet = one logical sequencing unit (e.g., one paired-end FASTQ pair for a sample)
- Supports multi-part upload for large files
- Each ReadSet has a subject ID and sample ID for data model tracking
- Access via ReadSet URI or direct file export to S3

**Metadata fields:**
| Field | Purpose |
|---|---|
| `name` | Human-readable name |
| `sampleId` | Links to your LIMS sample record |
| `subjectId` | Links to patient / participant |
| `referenceArn` | Optional: reference this ReadSet was originally aligned to |

---

## Workflow Engine

**What it does:**  
Runs Nextflow or WDL pipelines on fully managed, auto-scaling compute — no EC2 instances to manage.

**Supported engines:**
- `NEXTFLOW` — DSL2 supported; nf-core pipelines run with minimal changes
- `WDL` — WDL 1.0 and 1.1

**Container requirement:**  
All containers must be in **Amazon ECR** (not Docker Hub). This is the main change from running locally.

**Run storage types:**
| Type | Behavior | Use when |
|---|---|---|
| `STATIC` | Fixed storage allocated upfront | Predictable input sizes |
| `DYNAMIC` | Scales with actual usage | Variable-size inputs |

**Run lifecycle:**
```
PENDING → STARTING → RUNNING → COMPLETED
                            ↘ FAILED
                            ↘ CANCELLED
```

**Key parameters for `start_run`:**
- `workflowId` — registered workflow
- `roleArn` — IAM role HealthOmics assumes (must have S3, ECR, CloudWatch permissions)
- `outputUri` — S3 prefix for results
- `parameters` — JSON matching the workflow's parameter template

---

## Variant Store

**What it does:**  
Ingests VCF/BCF files and stores them in an Apache Parquet-backed columnar format, automatically linked to a reference genome. Queryable via Amazon Athena or the HealthOmics API.

**Key concepts:**
- Schema is derived from VCF INFO and FORMAT fields on import
- Variants are normalized against the reference (left-aligned, split multi-allelic)
- Each variant store maps to an Athena database and table automatically
- Access control via Lake Formation (column-level permissions possible)

**Supported query patterns:**
```sql
-- Count variants by type
SELECT variant_type, COUNT(*) FROM "store"."variants"
WHERE filter = 'PASS' GROUP BY 1;

-- Region-based lookup
SELECT * FROM "store"."variants"
WHERE contig = 'chr20' AND start BETWEEN 1000000 AND 2000000;

-- Sample-level genotype query
SELECT sample_id, genotype FROM "store"."variant_calls"
WHERE variant_id = 'rs12345';
```

---

## IAM Role Requirements

The `HealthOmicsWorkflowRole` (assumed by HealthOmics during workflow runs) needs:

| Permission | Why |
|---|---|
| `omics:*` | Access Reference/Sequence stores |
| `s3:GetObject`, `s3:PutObject` | Read inputs, write outputs |
| `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage` | Pull container images |
| `ecr:GetAuthorizationToken` | Authenticate to ECR |
| `logs:*` on `/aws/omics/*` | Write CloudWatch logs |

The trust policy must allow `omics.amazonaws.com` to assume the role.

---

## Local → HealthOmics Migration Checklist

- [ ] Docker images built and pushed to ECR
- [ ] `nextflow.config` `healthomics` profile has correct ECR URIs
- [ ] Reference FASTA imported into Reference Store
- [ ] FASTQ files imported into Sequence Store as ReadSets
- [ ] IAM role created with correct trust policy and permissions
- [ ] Workflow registered (`create_workflow`)
- [ ] Output S3 bucket exists with correct permissions
- [ ] `start_run` parameters use `omics://` and `s3://` URIs (not local file paths)

---

## Useful AWS CLI Commands

```bash
# Get HealthOmics service quotas
aws service-quotas list-service-quotas --service-code omics

# View workflow run logs
aws logs tail /aws/omics/WorkflowLog --follow

# Export a ReadSet to S3
aws omics start-read-set-export-job \
    --sequence-store-id STORE_ID \
    --destination s3://bucket/export/ \
    --role-arn arn:... \
    --sources '[{"readSetId": "READ_SET_ID"}]'

# Get Variant Store Athena details
aws omics get-variant-store --name my-store \
    --query 'storeOptions.tsvStoreOptions'
```
