rule CUTADAPT_Trim1:
	input:
		FWD="FastQ/{sample}_R1.fastq.gz",
		REV="FastQ/{sample}_R2.fastq.gz"
	output:
		FWD_TRIM="CallVars_Output/TrimmedReads/{sample}_Trimmed_R1.fastq.gz",
		REV_TRIM="CallVars_Output/TrimmedReads/{sample}_Trimmed_R2.fastq.gz"	
	log:
		"CallVars_Output/Logs/{sample}_CUTADAPT-Trimming.log"
	shell:
		"cutadapt -q 20,20 --trim-n -a AGATCGGAAGAGC -A AGATCGGAAGAGC -o {output.FWD_TRIM} -p {output.REV_TRIM}  {input} -j 6 &>{log}"
		#"cutadapt -q 20,20 --trim-n -a AGATCGGAAGAGC -A AGATCGGAAGAGC -o {output.FWD_TRIM} -p {output.REV_TRIM}  {input} &>{log}"

rule CUTADAPT_Trim2:
	input:
		FWD="FastQ/{sample}_R1.fastq",
		REV="FastQ/{sample}_R2.fastq"
	output:
		FWD_TRIM="CallVars_Output/TrimmedReads/{sample}_Trimmed_R1.fastq.gz",
		REV_TRIM="CallVars_Output/TrimmedReads/{sample}_Trimmed_R2.fastq.gz"
	log:
		"CallVars_Output/Logs/{sample}_CUTADAPT-Trimming.log"
	shell:
		"cutadapt -q 20,20 --trim-n -a AGATCGGAAGAGC -A AGATCGGAAGAGC -o {output.FWD_TRIM} -p {output.REV_TRIM}  {input} -j 6 &>{log}"
		#"cutadapt -q 20,20 --trim-n -a AGATCGGAAGAGC -A AGATCGGAAGAGC -o {output.FWD_TRIM} -p {output.REV_TRIM}  {input} &>{log}"

rule BWA_Mapping:
	input:
		REF="UCSCWholeGenomeFasta/genome.fa",
		FWD_TRIM="CallVars_Output/TrimmedReads/{sample}_Trimmed_R1.fastq.gz",
		REV_TRIM="CallVars_Output/TrimmedReads/{sample}_Trimmed_R2.fastq.gz"
	output:
		"CallVars_Output/MappedReads/{sample}.bam"
	params:
		rg=r"@RG\tID:{sample}\tLB:TS1E\tPL:Illumina\tPU=NextSeq550\tSM:{sample}"
	log:
		"CallVars_Output/Logs/{sample}_BWA-Mapping.log"
	shell:
		"bwa mem -R '{params.rg}' -t 6  {input.REF} {input.FWD_TRIM} {input.REV_TRIM} | samtools view -Sb - > {output} -@ 6 2>{log}"
		#"bwa mem -R '{params.rg}' -t 6  {input.REF} {input.FWD_TRIM} {input.REV_TRIM} | samtools view -Sb - > {output} 2>{log}"

rule SAMTOOLS_Sort:
	input:
		"CallVars_Output/MappedReads/{sample}.bam"
	output:
		"CallVars_Output/SortedReads/{sample}.bam"
	log:
		"CallVars_Output/Logs/{sample}_SAMTOOLS-sort.log"
	shell:
		"samtools sort -T CallVars_Output/SortedReads/{wildcards.sample} "
		"-O bam {input} > {output} -@ 6 2>{log}"
		#"samtools sort -T CallVars_Output/SortedReads/{wildcards.sample} "
		#"-O bam {input} > {output} 2>{log}"
rule GATK_MarkDuplicates:
	input:
		"CallVars_Output/SortedReads/{sample}.bam"
	output:
		first="CallVars_Output/NoDupReads/{sample}.bam",
		second="/home/amit/Desktop/Shared/BWA-GATK/CallVars_Output/NoDupReads/{sample}_marked_dup_metrics.txt"
	log:
		"CallVars_Output/Logs/{sample}_GATK-MarkDuplicates.log"
	shell:
		"gatk MarkDuplicates --REMOVE_DUPLICATES -I={input} -O={output.first} -M={output.second} --VALIDATION_STRINGENCY=SILENT &>{log}"

rule SAMTOOLS_Index:
	input:
		"CallVars_Output/NoDupReads/{sample}.bam"
	output:
		"CallVars_Output/NoDupReads/{sample}.bam.bai"
	#conda:
	#	"config/Config_BWA-Samtools-Cutadapt.yml"
	shell:
		"samtools index {input} -@ 6"
		#"samtools index {input}"

rule GATK_BaseRecalibrator:
	input:
		BAM="CallVars_Output/NoDupReads/{sample}.bam",
		REF="UCSCWholeGenomeFasta/genome.fa",
		SNP="dbSNP_20180423.vcf",
		MILLS="Mills_and_1000G_gold_standard.indels.hg19.sites.vcf",
		GNOM="1000G_phase1.indels.hg19.sites.vcf"
	output:
		"CallVars_Output/BQSR/{sample}_recal_data.table"
	log:
		"CallVars_Output/Logs/{sample}_GATK-BaseRecalibrator.log"
	shell:
		"gatk BaseRecalibrator -I {input.BAM} -R {input.REF} --known-sites {input.SNP} --known-sites {input.MILLS} --known-sites {input.GNOM} -O {output} &>{log}"

rule GATK_BQSR:
	input:
		BAM="CallVars_Output/NoDupReads/{sample}.bam",
		REF="UCSCWholeGenomeFasta/genome.fa",
		RECAL="CallVars_Output/BQSR/{sample}_recal_data.table"
	output:
		"CallVars_Output/BQSR/{sample}.bam"
	log:
		"CallVars_Output/Logs/{sample}_GATK-BQSR.log"
	params:
		 mem="-Xmx30g -Xmx20g"	
	shell:
		"gatk --java-options '{params.mem}' ApplyBQSR -R {input.REF} -I {input.BAM} --bqsr-recal-file {input.RECAL} -O {output} &>{log}"

rule GATK_HaplotypeCaller:
	input:
		BAM="CallVars_Output/BQSR/{sample}.bam",
		REF="UCSCWholeGenomeFasta/genome.fa",
		SNP="dbSNP_20180423.vcf",
		MICANC="MICANC.bed"
	output:
		"CallVars_Output/VCF/{sample}_germline.vcf"
	log:
		"CallVars_Output/Logs/{sample}_GATK-HaplotypeCaller.log"
	params:
		 mem="-Xmx30g -Xmx20g"
	shell:
		#"gatk --java-options '{params.mem}' HaplotypeCaller -R {input.REF} -I {input.BAM} --dbsnp {input.SNP} -O {output} &>{log}"
		"gatk --java-options '{params.mem}' HaplotypeCaller -R {input.REF} -I {input.BAM} --dbsnp {input.SNP} -L {input.MICANC} -O {output} &>{log}"
		
rule GATK_Mutect2:
	input:
		BAM="CallVars_Output/BQSR/{sample}.bam",
		REF="UCSCWholeGenomeFasta/genome.fa",
		GNOMAD="GNOMAD_hg19.vcf",
		MICANC="MICANC.bed"
	output:
		"CallVars_Output/VCF/{sample}_somatic.vcf"
	log:
		"CallVars_Output/Logs/{sample}_GATK-Mutect2.log"
	params:
		 mem="-Xmx30g -Xmx20g"
	run:
		#shell("gatk --java-options '{params.mem}' Mutect2 -R {input.REF} -I {input.BAM} -tumor {wildcards.sample} --germline-resource {input.GNOMAD} -O {output} &>{log}")
		shell("gatk --java-options '{params.mem}' Mutect2 -R {input.REF} -I {input.BAM} -L {input.MICANC} -tumor {wildcards.sample} --germline-resource {input.GNOMAD} -O {output} &>{log}")	
		#shell("rm -r CallVars_Output/TrimmedReads/ CallVars_Output/MappedReads/ CallVars_Output/SortedReads/ CallVars_Output/NoDupReads/")
		
rule GATK_Funcotator_Germline:
	input:
		REF="UCSCWholeGenomeFasta/genome.fa",
		VCF="CallVars_Output/VCF/{sample}_germline.vcf"
	output:
		"CallVars_Output/VCF/{sample}_germline_func.vcf"
	log:
		"CallVars_Output/Logs/{sample}_GATK-Funcotator_Germline.log"
	params:
		 mem="-Xmx30g -Xmx20g"
	run:
		shell("gatk --java-options '{params.mem}' Funcotator -R {input.REF} -V {input.VCF} -O {output} --output-file-format VCF --data-sources-path dataSourcesFolder/ --ref-version hg19 &>{log}")

rule GATK_Funcotator_Somatic:
	input:
		REF="UCSCWholeGenomeFasta/genome.fa",
		VCF="CallVars_Output/VCF/{sample}_somatic.vcf"
	output:
		"CallVars_Output/VCF/{sample}_somatic_func.vcf"
	log:
		"CallVars_Output/Logs/{sample}_GATK-Funcotator_Somatic.log"
	params:
		 mem="-Xmx30g -Xmx20g"
	run:
		shell("gatk --java-options '{params.mem}' Funcotator -R {input.REF} -V {input.VCF} -O {output} --output-file-format VCF --data-sources-path dataSourcesFolder/ --ref-version hg19 &>{log}")


rule GATK_VariantFiltration_Germline:
	input:
		REF="UCSCWholeGenomeFasta/genome.fa",
		VCF="CallVars_Output/VCF/{sample}_germline_func.vcf"
	output:
		FILTER="CallVars_Output/VCF/{sample}_germline_func_filter.vcf",
		ONE="CallVars_Output/TEMPFILES/{sample}_CallVars_Germline_TempOne.txt",
		TWO="CallVars_Output/TEMPFILES/{sample}_CallVars_Germline_TempTwo.txt",
		THREE="CallVars_Output/TEMPFILES/{sample}_CallVars_Germline_TempThree.txt",
		FINALTEMP="CallVars_Output/TEMPFILES/{sample}_CallVars_Germline_FinalTemp.txt",
		FINAL="CallVars_Output/Results/{sample}_CallVars_Germline.txt"
	log:
		"CallVars_Output/Logs/{sample}_GATK-VariantFiltration_Germline.log"
	params:
		 mem="-Xmx30g -Xmx20g"
	shell:
		"""
		gatk VariantFiltration -R {input.REF} -O {output.FILTER} -V {input.VCF} --filter-expression \"(QD < 2.0) || (FS > 60.0) || (MQ < 40.0) || (MQRankSum < -12.5) || (ReadPosRankSum < -8.0) || (SOR > 3.0)\" --filter-name \"Fail\"
		cat {output.FILTER}| cut -f1-7 | tail -n +60 > {output.ONE} || true
		cat {output.FILTER}| cut -f8 | awk -F"FUNCOTATION\=\["  '{{ print $2 }}'  | awk -F"|" '{{ print $1"\t"$6"\t"$14"\t"$17"\t"$19"\t"$27"\t"$28*100"\t"$68*100}}' | tail -n +60 > {output.TWO} ||true
		cat {output.FILTER}| cut -f9,10 | tail -n +60 > {output.THREE} || true
		paste {output.ONE} {output.TWO} {output.THREE} > {output.FINALTEMP} || true
		awk -F"\\t" '{{ if ($14 <= 0.5 || $15 <= 0.5) {{print}}}}' {output.FINALTEMP} > {output.FINAL} || true
		"""

rule GATK_VariantFiltration_Somatic:
	input:
		REF="UCSCWholeGenomeFasta/genome.fa",
		VCF="CallVars_Output/VCF/{sample}_somatic_func.vcf"
	output:
		FILTER="CallVars_Output/VCF/{sample}_somatic_func_filter.vcf",
		ONE="CallVars_Output/TEMPFILES/{sample}_CallVars_Somatic_TempOne.txt",
		TWO="CallVars_Output/TEMPFILES/{sample}_CallVars_Somatic_TempTwo.txt",
		THREE="CallVars_Output/TEMPFILES/{sample}_CallVars_Somatic_TempThree.txt",
		FINALTEMP="CallVars_Output/TEMPFILES/{sample}_CallVars_Somatic_FinalTemp.txt",
		FINAL="CallVars_Output/Results/{sample}_CallVars_Somatic.txt"
	log:
		"CallVars_Output/Logs/{sample}_GATK-Funcotator_Somatic.log"
	params:
		 mem="-Xmx30g -Xmx20g"
	shell:
		"""
		gatk VariantFiltration -R {input.REF} -O {output.FILTER} -V {input.VCF} --filter-expression \"(QD < 2.0) || (FS > 60.0) || (MQ < 40.0) || (MQRankSum < -12.5) || (ReadPosRankSum < -8.0) || (SOR > 3.0)\" --filter-name \"Fail\"
		cat {output.FILTER}| cut -f1-7 | tail -n +71 > {output.ONE} || true
		cat {output.FILTER}| cut -f8 | awk -F"FUNCOTATION\=\["  '{{ print $2 }}'  | awk -F"|" '{{ print $1"\t"$6"\t"$14"\t"$17"\t"$19"\t"$27"\t"$28*100"\t"$68*100}}' | tail -n +71 > {output.TWO} ||true
		cat {output.FILTER}| cut -f9,10 | tail -n +71 > {output.THREE} || true
		paste {output.ONE} {output.TWO} {output.THREE} > {output.FINALTEMP} || true
		awk -F"\\t" '{{ if ($14 <= 0.5 || $15 <= 0.5) {{print}}}}' {output.FINALTEMP} > {output.FINAL} || true
		"""
