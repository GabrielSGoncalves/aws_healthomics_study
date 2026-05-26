# Pin the official Broad GATK image — no need to rebuild from scratch.
# This image includes GATK4, Picard, Python 3, and R.
FROM broadinstitute/gatk:4.5.0.0

# HealthOmics requires the entrypoint to be overridable; the official image
# already sets CMD [] so Nextflow can run arbitrary commands.
WORKDIR /data
