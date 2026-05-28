#!/usr/bin/env bash
# Download and prepare WGS test data for the germline variant calling pipeline.
#
# What you get:
#   reads/NA12878_chr20_R1.fastq.gz   paired-end reads for chr20 (~150 MB)
#   reads/NA12878_chr20_R2.fastq.gz   (~150 MB)
#   reference/chr20.fa                hg38 chromosome 20 FASTA (~63 MB)
#   reference/chr20.fa.fai            samtools FASTA index
#   reference/chr20.dict              GATK sequence dictionary
#   reference/chr20.fa.*              bwa-mem2 alignment index files
#   reference/known_sites_chr20.vcf.gz  1000G hg38 chr20 variants for BQSR
#   reference/known_sites_chr20.vcf.gz.tbi  tabix index
#
# Data sources (all public, no authentication required):
#   Reads       : 1000 Genomes phase3 chr20-only BAM for NA12878 (EBI FTP)
#   Reference   : UCSC hg38 chr20 FASTA
#   Known sites : 1000 Genomes high-coverage hg38 phased panel, chr20
#
# Requirements:
#   curl, Docker (images pulled automatically on first run)
#
# Expected total download: ~2 GB  (BAM streamed and discarded, ~350 MB net)
# Expected run time      : 15-30 min depending on connection speed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READS_DIR="${SCRIPT_DIR}/reads"
REF_DIR="${SCRIPT_DIR}/reference"

# Official BioContainers image with bwa-mem2 2.2.1 + samtools 1.17
# Same image used by the Nextflow pipeline (see nextflow/nextflow.config)
MULLED_IMAGE="quay.io/biocontainers/mulled-v2-e5d375990341c5aef3c9aff74f96f66f65375ef6:2cdf6bf1e92acbeb9b2834b1c58754167173a410-0"

mkdir -p "${READS_DIR}" "${REF_DIR}"

# ---------------------------------------------------------------------------
# 1. Reference genome — hg38 chr20 from UCSC
# ---------------------------------------------------------------------------
if [[ -f "${REF_DIR}/chr20.fa" ]]; then
    echo "==> chr20.fa already exists, skipping download."
else
    echo "==> Downloading hg38 chr20 reference (UCSC)"
    curl -fsSL --retry 3 \
        "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/chromosomes/chr20.fa.gz" \
        | zcat > "${REF_DIR}/chr20.fa"
    echo "    chr20.fa downloaded ($(du -sh "${REF_DIR}/chr20.fa" | cut -f1))."
fi

# ---------------------------------------------------------------------------
# 2. Reference indexes — bwa-mem2, samtools faidx, samtools dict
#    Runs inside Docker so no local tool installs are needed.
# ---------------------------------------------------------------------------
if [[ -f "${REF_DIR}/chr20.fa.fai" && -f "${REF_DIR}/chr20.dict" ]]; then
    echo "==> Reference indexes already exist, skipping."
else
    echo "==> Pulling BioContainers image (first run only — ~900 MB)"
    docker pull "${MULLED_IMAGE}"

    echo "==> Generating reference indexes (bwa-mem2 + samtools)"
    docker run --rm \
        -v "${REF_DIR}:/ref" \
        "${MULLED_IMAGE}" \
        bash -c "
            bwa-mem2 index /ref/chr20.fa
            samtools faidx  /ref/chr20.fa
            samtools dict   /ref/chr20.fa -o /ref/chr20.dict
        "
    echo "    Indexes generated:"
    ls -lh "${REF_DIR}/"
fi

# ---------------------------------------------------------------------------
# 3. NA12878 chr20 reads — 1000 Genomes phase3 chr20 BAM → FASTQ
#
#    Source:  1000 Genomes Project, EBI FTP
#    Sample:  NA12878 (the canonical GIAB reference sample)
#    File:    NA12878.chrom20.ILLUMINA.bwa.CEU.low_coverage.20121211.bam
#             ↑ already chr20-only (~1.4 GB), ~4-6x coverage
#
#    Original alignment: GRCh37 (hg19).  That's fine — we extract the raw
#    read sequences as FASTQ (coordinates are discarded) and re-align to hg38
#    in the pipeline.  The read sequences are the same; only coordinates differ
#    between genome builds.
# ---------------------------------------------------------------------------
if [[ -f "${READS_DIR}/NA12878_chr20_R1.fastq.gz" && \
      -f "${READS_DIR}/NA12878_chr20_R2.fastq.gz" ]]; then
    echo "==> FASTQ reads already exist, skipping download."
else
    echo "==> Downloading 1000G chr20 BAM for NA12878 (~1.4 GB)"
    BAM_URL="https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA12878/alignment/NA12878.chrom20.ILLUMINA.bwa.CEU.low_coverage.20121211.bam"
    curl -fsSL --retry 3 --retry-delay 5 "${BAM_URL}" \
        -o "${READS_DIR}/NA12878_chr20_tmp.bam"

    echo "==> Converting BAM → paired FASTQ (name-sort then fastq)"
    # samtools sort -n : sort by query name so read pairs are adjacent
    # samtools fastq   : split into R1 / R2 / unpaired / singletons
    docker run --rm \
        -v "${READS_DIR}:/data" \
        "${MULLED_IMAGE}" \
        bash -c "
            samtools sort -n -@ 4 -m 2G /data/NA12878_chr20_tmp.bam \
            | samtools fastq \
                -@ 4 \
                -1 /data/NA12878_chr20_R1.fastq.gz \
                -2 /data/NA12878_chr20_R2.fastq.gz \
                -0 /dev/null \
                -s /dev/null
        "

    rm "${READS_DIR}/NA12878_chr20_tmp.bam"
    echo "    FASTQs written:"
    ls -lh "${READS_DIR}/"
fi

# ---------------------------------------------------------------------------
# 4. Known variant sites for BQSR — 1000G hg38 phased panel, chr20
#
#    GATK BaseRecalibrator needs a VCF of known germline variants so it can
#    distinguish real variants from sequencing errors when recalibrating
#    base quality scores.  We use the 1000 Genomes high-coverage hg38 phased
#    SNP/INDEL panel for chr20 — publicly available on EBI FTP.
#    Chromosome names match our hg38 UCSC reference ("chr20").
# ---------------------------------------------------------------------------
if [[ -f "${REF_DIR}/known_sites_chr20.vcf.gz" && \
      -f "${REF_DIR}/known_sites_chr20.vcf.gz.tbi" ]]; then
    echo "==> Known sites VCF already exists, skipping."
else
    echo "==> Downloading 1000G hg38 chr20 phased panel (known sites for BQSR)"
    VCF_BASE="https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/data_collections/1000G_2504_high_coverage/working/20220422_3202_phased_SNV_INDEL_SV"
    VCF_FILE="1kGP_high_coverage_Illumina.chr20.filtered.SNV_INDEL_SV_phased_panel.vcf.gz"
    GATK_IMG="broadinstitute/gatk:4.5.0.0"

    curl -fsSL --retry 3 --retry-delay 5 \
        "${VCF_BASE}/${VCF_FILE}" \
        -o "${REF_DIR}/known_sites_chr20_raw.vcf.gz"

    curl -fsSL --retry 3 --retry-delay 5 \
        "${VCF_BASE}/${VCF_FILE}.tbi" \
        -o "${REF_DIR}/known_sites_chr20_raw.vcf.gz.tbi"

    echo "    Downloaded ($(du -sh "${REF_DIR}/known_sites_chr20_raw.vcf.gz" | cut -f1))."

    # The 1000G phased panel contains SVs whose VCF header fields use non-standard
    # attribute ordering (Type before Number). GATK/HTSJDK rejects such headers.
    # Step 1: filter to SNPs+indels (removes SV records).
    # Step 2: strip the one remaining malformed INFO header line (END2) via reheader.
    echo "==> Filtering to SNPs+indels and fixing VCF header (GATK compatibility)"
    docker run --rm \
        -v "${REF_DIR}:/ref" \
        "${GATK_IMG}" \
        bash -c "
            bcftools view -v snps,indels -O z -o /ref/known_sites_chr20_snv.vcf.gz /ref/known_sites_chr20_raw.vcf.gz
            bcftools view -h /ref/known_sites_chr20_snv.vcf.gz \
                | grep -v ',Type=.*,Number=' > /ref/header_fixed.txt
            bcftools reheader -h /ref/header_fixed.txt \
                -o /ref/known_sites_chr20.vcf.gz /ref/known_sites_chr20_snv.vcf.gz
            tabix -p vcf /ref/known_sites_chr20.vcf.gz
            rm /ref/known_sites_chr20_snv.vcf.gz /ref/header_fixed.txt
        "

    rm "${REF_DIR}/known_sites_chr20_raw.vcf.gz" "${REF_DIR}/known_sites_chr20_raw.vcf.gz.tbi"
    echo "    Known sites ready ($(du -sh "${REF_DIR}/known_sites_chr20.vcf.gz" | cut -f1))."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "All test data ready:"
echo ""
echo "  Reads (FASTQ):"
ls -lh "${READS_DIR}/"
echo ""
echo "  Reference + indexes:"
ls -lh "${REF_DIR}/"
echo ""
echo "Run the pipeline with:"
echo "  cd ../nextflow"
echo "  nextflow run main.nf -profile local \\"
echo "    --reads  \"../data/reads/NA12878_chr20_*_R{1,2}.fastq.gz\" \\"
echo "    --reference   \"../data/reference/chr20.fa\" \\"
echo "    --known_sites \"../data/reference/known_sites_chr20.vcf.gz\""
