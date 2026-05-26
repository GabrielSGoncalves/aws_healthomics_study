process BQSR {
    tag "${meta.id}"

    input:
    tuple val(meta), path(bam), path(bai)
    path(fasta)
    path(fasta_fai)
    path(fasta_dict)
    path(known_sites)
    path(known_sites_tbi)

    output:
    tuple val(meta), path("${meta.id}.bqsr.bam"), path("${meta.id}.bqsr.bam.bai"), emit: bam
    path("${meta.id}.recal.table"), emit: table

    script:
    """
    gatk BaseRecalibrator \\
        --input ${bam} \\
        --reference ${fasta} \\
        --known-sites ${known_sites} \\
        --output ${meta.id}.recal.table

    gatk ApplyBQSR \\
        --input ${bam} \\
        --reference ${fasta} \\
        --bqsr-recal-file ${meta.id}.recal.table \\
        --output ${meta.id}.bqsr.bam

    samtools index ${meta.id}.bqsr.bam
    """
}
