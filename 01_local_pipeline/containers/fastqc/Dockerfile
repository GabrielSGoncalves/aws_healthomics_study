FROM ubuntu:22.04

ARG FASTQC_VERSION=0.12.1
ARG MULTIQC_VERSION=1.21

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    openjdk-17-jre-headless \
    python3 \
    python3-pip \
    perl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install FastQC
RUN curl -fsSL "https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v${FASTQC_VERSION}.zip" \
    -o /tmp/fastqc.zip && \
    unzip /tmp/fastqc.zip -d /opt && \
    chmod +x /opt/FastQC/fastqc && \
    ln -s /opt/FastQC/fastqc /usr/local/bin/fastqc && \
    rm /tmp/fastqc.zip

# Install MultiQC
RUN pip3 install --no-cache-dir multiqc==${MULTIQC_VERSION}

WORKDIR /data
