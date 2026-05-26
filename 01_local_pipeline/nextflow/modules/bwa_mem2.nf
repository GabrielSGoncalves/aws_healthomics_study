process BWA_MEM2 {
    tag "${meta.id}"
    publishDir "${params.outdir}/alignment", mode: 'copy', pattern: "*.bai"

    input:
    tuple val(meta), path(reads)
    path(fasta)
    path(fasta_index)  // .amb .ann .bwt.2bit.64 .pac .0123 files

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), path("${meta.id}.sorted.bam.bai"), emit: bam

    script:
    def read_group = "@RG\\tID:${meta.id}\\tSM:${meta.id}\\tLB:${meta.library ?: 'lib1'}\\tPL:ILLUMINA\\tPU:${meta.id}"
    """
    bwa-mem2 mem \\
        -t ${task.cpus} \\
        -R '${read_group}' \\
        ${fasta} \\
        ${reads} \\
    | samtools sort \\
        -@ ${task.cpus} \\
        -o ${meta.id}.sorted.bam

    samtools index ${meta.id}.sorted.bam
    """
}
