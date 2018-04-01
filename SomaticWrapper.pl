######### Song Cao and Matt Wyczalkowski ###########
## pipeline for somatic variant calling ##

# TODO: implement full command line argument parsing instead of configuration file
# see: https://perlmaven.com/how-to-process-command-line-arguments-in-perl

# TODO: how are paths handled in CGC?  Do we need so pass output paths individually?

# OUTPUT PORT: 
#   results/runtime/* - job scripts

#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

#use POSIX;
my $version = 3.0;

# submodule information
# https://stackoverflow.com/questions/1712016/how-do-i-include-functions-from-another-file-in-my-perl-script
require('src/run_strelka.pl');
require("src/run_varscan.pl");
require("src/parse_strelka.pl");
require("src/parse_varscan.pl");
require("src/run_pindel.pl");
require("src/parse_pindel.pl");
require("src/merge_vcf.pl");
require("src/annotate_vcf.pl");

(my $usage = <<OUT) =~ s/\t+//g;
This script will evaluate variants for WGS and WXS data
Pipeline version: $version
Usage: perl $0 [options] step_number 

step_number executes given step of pipeline:
* [1 or run_strelka]  Run streka
* [2 or run_varscan]  Run Varscan
* [3 or parse_strelka]  Parse streka result
* [4 or parse_varscan]  Parse VarScan result
* [5 or run_pindel]  Run Pindel
* [7 or parse_pindel]  Parse Pindel
* [8 or merge_vcf]  Merge vcf files 
* [10 or annotate_vcf]  Run VEP annotation on a given file

Configuration file parameters [defaults]
    --tumor_bam s:  path to tumor BAM.  Required for all runs
    --normal_bam s: path to normal BAM.  Required for all runs
    --reference_fasta s: path to reference
    --assembly s: either "GRCh37" or "GRCh38", used for VEP [GRCh37]
    --reference_dict s: path to reference dict file.  Default is reference_fasta with ".dict" appended
    --sw_dir s: Somatic Wrapper installation directory [/usr/local/somaticwrapper]
    --results_dir s: Per-sample analysis results written here [.]
    --use_vep_db : if 1, use online VEP database lookups ("db mode") [0]
          db mode a) uses online database (so cache isn't installed) b) does not use tmp files
          It is meant to be used for testing and lightweight applications.  Use the cache (default)
          for better performance.
          See discussion: https://www.ensembl.org/info/docs/tools/vep/script/vep_cache.html 
    --vep_cache_dir s: VEP cache directory, if not doing online VEP db lookups.  [/data/D_VEP]
    --output_vep : if 1, write final annotated merged file in VEP rather than VCF format [0]
    --strelka_config s: path to strelka.ini file, required for strelka run
    --varscan_config s: path to varscan.ini file, required for varscan run
    --pindel_config s: path to pindel.ini file, required for pindel parsing
    --centromere_bed s: path to BED file describing centromere regions to exclude for pindel analysis.  See C_Centromeres for discussion
    --gatk_jar s: path to GATK Jar file.  [/usr/local/GenomeAnalysisTK-3.8-0-ge9d806836/GenomeAnalysisTK.jar]
    --perl s: path to PERL executable.  [/usr/bin/perl]
    --strelka_dir s: path to strelka installation dir.  [/usr/local/strelka]
    --vep_cmd s: path to ensembl vep executable.  [/usr/local/ensembl-vep/vep]
    --pindel_dir s: path to Pindel installation dir.  [/usr/local/pindel]
    --snpsift_jar s: [/usr/local/snpEff/SnpSift.jar]
    --varscan_jar s: [/usr/local/VarScan.jar]
    --dbsnp_db s: database for dbSNP filtering [none]
    --strelka_snv_raw: SNV output file generated by Stelka run.  Required for parse_strelka
    --varscan_indel_raw: Indel output file generated by varscan run.  Required for parse_varscan
    --varscan_snv_raw: SNV output file generated by varscan run.  Required for parse_varscan
    --pindel_raw: raw output file generated by pindel run.  Required for parse_pindel
    --strelka_snv_vcf: output file generated by parse_strelka.  Required for merge_vcf
    --varscan_snv_vcf: output file generated by parse_varscan.  Required for merge_vcf
    --varscan_indel_vcf: output file generated by parse_varscan.  Required for merge_vcf
    --pindel_vcf: output file generated by parse_pindel.  Required for merge_vcf
    --input_vcf: VCF file to be annotated with annotate_vcf
    --output_vcf: filename of output vcf [output.vcf (or output.vep if --output_vep)]
OUT

# OLD:
# my $centromere_bed="$sw_dir/image.setup/C_Centromeres/pindel-centromere-exclude.bed";

# Argument parsing reference: http://perldoc.perl.org/Getopt/Long.html
# https://perlmaven.com/how-to-process-command-line-arguments-in-perl
my $tumor_bam;
my $normal_bam;
my $assembly;
my $reference_fasta;
my $reference_dict;  # default mapping occurs after reference_fasta known
my $sw_dir = "/usr/local/somaticwrapper";
my $results_dir = ".";  
my $use_vep_db = 0; 
my $vep_cache_dir = "/data/D_VEP";
my $output_vep = 0;
my $strelka_config; 
my $varscan_config; 
my $pindel_config; 
my $centromere_bed; 
my $gatk_jar = "/usr/local/GenomeAnalysisTK-3.8-0-ge9d806836/GenomeAnalysisTK.jar";
my $perl = "/usr/bin/perl";
my $strelka_dir = "/usr/local/strelka";
my $vep_cmd = "/usr/local/ensembl-vep/vep";
my $pindel_dir = "/usr/local/pindel";
my $snpsift_jar = "/usr/local/snpEff/SnpSift.jar";
my $varscan_jar = "/usr/local/VarScan.jar";
my $dbsnp_db = "none";
my $strelka_snv_raw;
my $varscan_indel_raw;
my $varscan_snv_raw;
my $pindel_raw;
my $strelka_snv_vcf;
my $varscan_snv_vcf;
my $varscan_indel_vcf;
my $pindel_vcf;
my $input_vcf;
my $output_vcf = "output.vcf";

GetOptions(
    'tumor_bam=s' => \$tumor_bam,
    'normal_bam=s' => \$normal_bam,
    'reference_fasta=s' => \$reference_fasta,
    'assembly=s' => \$assembly,
    'reference_dict=s' => \$reference_dict,
    'sw_dir=s' => \$sw_dir,
    'results_dir=s' => \$results_dir,
    'use_vep_db=s' => \$use_vep_db,
    'vep_cache_dir=s' => \$vep_cache_dir,
    'output_vep=s' => \$output_vep,
    'strelka_config=s' => \$strelka_config,
    'varscan_config=s' => \$varscan_config,
    'pindel_config=s' => \$pindel_config,
    'centromere_bed=s' => \$centromere_bed,
    'gatk_jar=s' => \$gatk_jar,
    'perl=s' => \$perl,
    'strelka_dir=s' => \$strelka_dir,
    'vep_cmd=s' => \$vep_cmd,
    'pindel_dir=s' => \$pindel_dir,
    'snpsift_jar=s' => \$snpsift_jar,
    'varscan_jar=s' => \$varscan_jar,
    'dbsnp_db=s' => \$dbsnp_db,
    'strelka_snv_raw=s' => \$strelka_snv_raw,
    'varscan_indel_raw=s' => \$varscan_indel_raw,
    'varscan_snv_raw=s' => \$varscan_snv_raw,
    'pindel_raw=s' => \$pindel_raw,
    'strelka_snv_vcf=s' => \$strelka_snv_vcf,
    'varscan_snv_vcf=s' => \$varscan_snv_vcf,
    'pindel_vcf=s' => \$pindel_vcf,
    'varscan_indel_vcf=s' => \$varscan_indel_vcf,
    'input_vcf=s' => \$input_vcf,
    'output_vcf=s' => \$output_vcf,
) or die "Error parsing command line args.\n$usage\n";

die $usage unless @ARGV >= 1;
my ( $step_number ) = @ARGV;

# Distinguising between location of modules of somatic wrapper and GenomeVIP
# GenomeVIP is not distributed separately so hard code the path
my $gvip_dir="$sw_dir/GenomeVIP";

# automatically generated scripts in runtime
my $job_files_dir="$results_dir/runtime";  # OUTPUT PORT
system("mkdir -p $job_files_dir");

#print("Using reference $reference_fasta\n");
print("SomaticWrapper dir: $sw_dir \n");
print("Analysis dir: $results_dir\n");
print("Run script dir: $job_files_dir\n");

# Not clear when this would be needed...
#if ( not $reference_dict ) { $reference_dict = "$reference_fasta.dict";}

if (($step_number eq '1') || ($step_number eq 'run_strelka')) {
    die("tumor_bam undefined \n") unless $tumor_bam;
    die("normal_bam undefined \n") unless $normal_bam;
    die("strelka_config undefined \n") unless $strelka_config;
    die("reference_fasta undefined \n") unless $reference_fasta;
    run_strelka($tumor_bam, $normal_bam, $results_dir, $job_files_dir, $strelka_dir, $reference_fasta, $strelka_config);
} elsif (($step_number eq '2') || ($step_number eq 'run_varscan')) {
    die("tumor_bam undefined \n") unless $tumor_bam;
    die("normal_bam undefined \n") unless $normal_bam;
    die("varscan_config undefined \n") unless $varscan_config;
    die("reference_fasta undefined \n") unless $reference_fasta;
    run_varscan($tumor_bam, $normal_bam, $results_dir, $job_files_dir, $reference_fasta, $varscan_config, $varscan_jar);
} elsif (($step_number eq '3') || ($step_number eq 'parse_strelka')) {
    die("Strelka SNV Raw input file not specified \n") unless $strelka_snv_raw;
    parse_strelka($results_dir, $job_files_dir, $perl, $gvip_dir, $dbsnp_db, $snpsift_jar, $strelka_snv_raw);
} elsif (($step_number eq '4') || ($step_number eq 'parse_varscan')) {
    die("Varscan Indel Raw input file not specified \n") unless $varscan_indel_raw;
    die("Varscan SNV Raw input file not specified \n") unless $varscan_snv_raw;
    parse_varscan($results_dir, $job_files_dir, $perl, $gvip_dir, $dbsnp_db, $snpsift_jar, $varscan_jar, $varscan_indel_raw, $varscan_snv_raw);
} elsif (($step_number eq '5') || ($step_number eq 'run_pindel')) {
    die("tumor_bam undefined \n") unless $tumor_bam;
    die("normal_bam undefined \n") unless $normal_bam;
    die("reference_fasta undefined \n") unless $reference_fasta;
    run_pindel($tumor_bam, $normal_bam, $results_dir, $job_files_dir, $reference_fasta, $pindel_dir, $centromere_bed);
} elsif (($step_number eq '7') || ($step_number eq 'parse_pindel')) {
    die("pindel_config undefined \n") unless $pindel_config;
    die("pindel raw input file not specified \n") unless $pindel_raw;
    die("reference_fasta undefined \n") unless $reference_fasta;
    parse_pindel($results_dir, $job_files_dir, $reference_fasta, $perl, $gvip_dir, $pindel_dir, $dbsnp_db, $snpsift_jar, $pindel_config, $pindel_raw);
} elsif (($step_number eq '8') || ($step_number eq 'merge_vcf')) {
    die("strelka_snv_vcf undefined \n") unless $strelka_snv_vcf;
    die("varscan_snv_vcf undefined \n") unless $varscan_snv_vcf;
    die("pindel_vcf undefined \n") unless $pindel_vcf;
    die("varscan_indel_vcf undefined \n") unless $varscan_indel_vcf;
    die("reference_fasta undefined \n") unless $reference_fasta;

    merge_vcf($results_dir, $job_files_dir, $reference_fasta, $gatk_jar, $strelka_snv_vcf, $varscan_indel_vcf, $varscan_snv_vcf, $pindel_vcf);
} elsif (($step_number eq '10') || ($step_number eq 'annotate_vcf')) {

    die("assembly undefined \n") unless $assembly;
    die("input_vcf undefined \n") unless $input_vcf;
    die("output_vcf undefined \n") unless $output_vcf;
    die("reference_fasta undefined \n") unless $reference_fasta;

    annotate_vcf($results_dir, $job_files_dir, $reference_fasta, $gvip_dir, $vep_cmd, $assembly, $vep_cache_dir, $use_vep_db, $output_vep, $input_vcf, $output_vcf)
} else {
    die("Unknown step number $step_number\n");
}
