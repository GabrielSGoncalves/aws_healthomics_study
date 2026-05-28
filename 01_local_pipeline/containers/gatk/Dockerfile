# Official Broad Institute GATK image — no need to rebuild from scratch.
# Includes GATK4, Picard, samtools, Python 3, and R.
# Source: https://hub.docker.com/r/broadinstitute/gatk
FROM broadinstitute/gatk:4.5.0.0

# HealthOmics requires the entrypoint to be overridable; the official image
# already sets CMD [] so Nextflow can run arbitrary commands.
WORKDIR /data
