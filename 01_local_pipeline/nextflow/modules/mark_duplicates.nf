process MARK_DUPLICATES {
    tag "${meta.id}"
    publishDir "${params.outdir}/alignment", mode: 'copy', pattern: "*.txt"

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("${meta.id}.markdup.bam"), path("${meta.id}.markdup.bam.bai"), emit: bam
    path("${meta.id}.markdup_metrics.txt"), emit: metrics

    script:
    """
    gatk MarkDuplicates \\
        --INPUT ${bam} \\
        --OUTPUT ${meta.id}.markdup.bam \\
        --METRICS_FILE ${meta.id}.markdup_metrics.txt \\
        --OPTICAL_DUPLICATE_PIXEL_DISTANCE 2500 \\
        --CREATE_INDEX true \\
        --VALIDATION_STRINGENCY SILENT

    # MarkDuplicates creates .bai, rename to .bam.bai for samtools compatibility
    mv ${meta.id}.markdup.bai ${meta.id}.markdup.bam.bai
    """
}
