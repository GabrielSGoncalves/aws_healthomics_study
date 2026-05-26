process HAPLOTYPECALLER {
    tag "${meta.id}"
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path(fasta)
    path(fasta_fai)
    path(fasta_dict)

    output:
    tuple val(meta), path("${meta.id}.g.vcf.gz"), path("${meta.id}.g.vcf.gz.tbi"), emit: gvcf

    script:
    """
    gatk HaplotypeCaller \\
        --reference ${fasta} \\
        --input ${bam} \\
        --output ${meta.id}.g.vcf.gz \\
        --emit-ref-confidence GVCF \\
        --native-pair-hmm-threads ${task.cpus}
    """
}

process GENOTYPE_GVCFS {
    tag "${meta.id}"
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(meta), path(gvcf), path(tbi)
    path(fasta)
    path(fasta_fai)
    path(fasta_dict)

    output:
    tuple val(meta), path("${meta.id}.raw.vcf.gz"), path("${meta.id}.raw.vcf.gz.tbi"), emit: vcf

    script:
    """
    gatk GenotypeGVCFs \\
        --reference ${fasta} \\
        --variant ${gvcf} \\
        --output ${meta.id}.raw.vcf.gz
    """
}

process FILTER_VARIANTS {
    tag "${meta.id}"
    publishDir "${params.outdir}/variants", mode: 'copy'

    input:
    tuple val(meta), path(vcf), path(tbi)
    path(fasta)
    path(fasta_fai)
    path(fasta_dict)

    output:
    tuple val(meta), path("${meta.id}.final.vcf.gz"), path("${meta.id}.final.vcf.gz.tbi"), emit: vcf

    script:
    """
    # Split SNPs and apply hard filters
    gatk SelectVariants --variant ${vcf} --reference ${fasta} \\
        --select-type-to-include SNP --output snps.vcf.gz

    gatk VariantFiltration --variant snps.vcf.gz --reference ${fasta} \\
        --filter-expression "QD < 2.0"             --filter-name "QD2" \\
        --filter-expression "MQ < 40.0"            --filter-name "MQ40" \\
        --filter-expression "FS > 60.0"            --filter-name "FS60" \\
        --filter-expression "SOR > 3.0"            --filter-name "SOR3" \\
        --filter-expression "MQRankSum < -12.5"    --filter-name "MQRankSum-12.5" \\
        --filter-expression "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8" \\
        --output snps.filtered.vcf.gz

    # Split indels and apply hard filters
    gatk SelectVariants --variant ${vcf} --reference ${fasta} \\
        --select-type-to-include INDEL --output indels.vcf.gz

    gatk VariantFiltration --variant indels.vcf.gz --reference ${fasta} \\
        --filter-expression "QD < 2.0"   --filter-name "QD2" \\
        --filter-expression "FS > 200.0" --filter-name "FS200" \\
        --filter-expression "SOR > 10.0" --filter-name "SOR10" \\
        --output indels.filtered.vcf.gz

    # Merge back
    gatk MergeVcfs \\
        --INPUT snps.filtered.vcf.gz \\
        --INPUT indels.filtered.vcf.gz \\
        --OUTPUT ${meta.id}.final.vcf.gz
    """
}
