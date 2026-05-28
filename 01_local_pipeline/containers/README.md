# Pipeline Containers

All pipeline stages use **official, community-maintained images** instead of custom
Dockerfiles. The table below maps each tool to its upstream image. For local runs
Nextflow pulls them automatically; for AWS HealthOmics they must be in ECR — use
`build_and_push.sh --push` to retag and push.

| Process(es) | Official Image | Source | Notes |
|---|---|---|---|
| `BWA_MEM2` | `quay.io/biocontainers/mulled-v2-e5d375990341c5aef3c9aff74f96f66f65375ef6:2cdf6bf1e92acbeb9b2834b1c58754167173a410-0` | BioContainers | bwa-mem2 2.2.1 + samtools 1.17; same image used by nf-core/sarek |
| `FASTQC` | `quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0` | BioContainers | |
| `MULTIQC` | `quay.io/biocontainers/multiqc:1.21--pyhdfd78af_0` | BioContainers | |
| `MARK_DUPLICATES`, `BQSR`, `HAPLOTYPECALLER`, `GENOTYPE_GVCFS`, `FILTER_VARIANTS` | `broadinstitute/gatk:4.5.0.0` | Broad Institute | Includes GATK4, Picard, samtools, Python 3, R |

## Why official images?

* **No maintenance burden** — version bumps are one-line changes.
* **Trusted provenance** — BioContainers images are auto-built from Bioconda packages
  and pinned by SHA; Broad's GATK image is the canonical reference for the tool.
* **Identical path to ECR** — `build_and_push.sh` pulls and retags; the Nextflow
  workflow doesn't change between local and cloud profiles.

## GATK Dockerfile

The `gatk/Dockerfile` is a thin `FROM broadinstitute/gatk:4.5.0.0` wrapper kept for
completeness. It satisfies `build_and_push.sh`'s image-discovery loop and serves as
an explicit record of which upstream tag is pinned.

## Adding a new tool

1. Find the BioContainers tag at <https://quay.io/repository/biocontainers/TOOLNAME>.
2. Add an entry to the table above.
3. Add the image to `nextflow/nextflow.config` under both `local` and `healthomics`
   profiles.
4. The ECR push is handled automatically by `build_and_push.sh`.
