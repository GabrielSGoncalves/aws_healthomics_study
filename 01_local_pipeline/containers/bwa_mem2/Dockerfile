FROM ubuntu:22.04

ARG BWA_MEM2_VERSION=2.2.1
ARG SAMTOOLS_VERSION=1.19

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libncurses5-dev \
    libbz2-dev \
    liblzma-dev \
    zlib1g-dev \
    libcurl4-openssl-dev \
    make \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install bwa-mem2
RUN curl -fsSL "https://github.com/bwa-mem2/bwa-mem2/releases/download/v${BWA_MEM2_VERSION}/bwa-mem2-${BWA_MEM2_VERSION}_x64-linux.tar.bz2" \
    | tar -xj -C /usr/local/bin --strip-components=1 "bwa-mem2-${BWA_MEM2_VERSION}_x64-linux/bwa-mem2"

# Install samtools
RUN curl -fsSL "https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2" \
    | tar -xj && \
    cd samtools-${SAMTOOLS_VERSION} && \
    ./configure --prefix=/usr/local && make -j$(nproc) && make install && \
    cd .. && rm -rf samtools-${SAMTOOLS_VERSION}

WORKDIR /data
