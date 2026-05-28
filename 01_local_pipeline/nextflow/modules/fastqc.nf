process FASTQC {
    tag "${meta.id}"
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.html"), emit: html
    tuple val(meta), path("*.zip"),  emit: zip

    script:
    def prefix = meta.id
    """
    fastqc \\
        --outdir . \\
        --threads ${task.cpus} \\
        ${reads}
    """
}

process MULTIQC {
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    path(reports)

    output:
    path("multiqc_report.html"),      emit: report
    path("multiqc_report_data/"),     emit: data

    script:
    """
    multiqc . --outdir . --filename multiqc_report.html
    """
}
