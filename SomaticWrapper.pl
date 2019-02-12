######### Song Cao and Matt Wyczalkowski ###########
## pipeline for somatic variant calling ##

#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use File::Basename;

# All paths are defined in SWpaths.pm
# They are accessed as, e.g., $SWpaths::sw_dir
use SWpaths;

require('src/run_strelka.pl');
require('src/run_strelka2.pl');
require("src/run_varscan.pl");
require("src/parse_varscan_snv.pl");
require("src/parse_varscan_indel.pl");
require("src/run_pindel.pl");
require("src/parse_pindel.pl");
require("src/merge_vcf.pl");
require("src/vep_annotate.pl");
require("src/vep_filter.pl");
require("src/vcf_2_maf.pl");
require("src/dbsnp_filter_sw.pl");
require("src/vaf_length_depth_filters.pl");


(my $usage = <<OUT) =~ s/\t+//g;
This script will evaluate variants for WGS and WXS data
Usage: perl $0 [options] step_number 

step_number executes given step of pipeline:
* [run_strelka]  Run streka
* [run_strelka2]  Run streka2
* [run_varscan]  Run Varscan
* [run_pindel]  Run Pindel
* [parse_varscan_snv]  Parse VarScan snv result
* [parse_varscan_indel]  Parse VarScan indel result
* [parse_pindel]  Parse Pindel
* [vaf_length_depth_filters]  Filter VCF based on variant length, VAF, and read depth
* [merge_vcf]  Merge vcf files 
* [dbsnp_filter]  Remove dbSnP variants from VCF
* [vep_annotate]  Run VEP annotation on a given file
* [vcf_2_maf]  Run vcf_2_maf on VCF

Required and optional arguments per step

All steps:
    --results_dir s: Per-sample analysis results location. Often same as sample name [.] 
    --skip s: If defined, skip this step and print argument as reason for skipping.  Helpful for interaction with CWL workflow.

run_strelka:
    --tumor_bam s:  path to tumor BAM.  Required
    --normal_bam s: path to normal BAM.  Required
    --reference_fasta s: path to reference.  Required
    --strelka_config s: path to strelka.ini file.  Required
run_strelka2:
    --tumor_bam s:  path to tumor BAM.  Required
    --normal_bam s: path to normal BAM.  Required
    --reference_fasta s: path to reference.  Required
    --strelka_config s: path to strelka.ini file.  Required
    --manta_vcf: pass Manta VCF calls to Strelka2 as input.  Optional
run_varscan:
    --tumor_bam s:  path to tumor BAM.  Required
    --normal_bam s: path to normal BAM.  Required
    --reference_fasta s: path to reference.  Required
    --varscan_config s: path to varscan.ini file.  Required
run_pindel:
    --tumor_bam s:  path to tumor BAM.  Required
    --normal_bam s: path to normal BAM.  Required
    --reference_fasta s: path to reference.  Required
    --pindel_config s: path to pindel.ini file.  Required
    --no_delete_temp : if defined, do not delete temp files
    --centromere_bed s: path to BED file describing centromere regions to exclude for pindel analysis. Optional
    --pindel_chrom c: defines which chrom to process; default is to process all of them.  Optional
parse_varscan_snv:
    --varscan_snv_raw s: Path to SNV output file generated by varscan run.  Required.
    --varscan_indel_raw s: Indel output file generated by varscan run.  Used for varscan somaticFilter.  Required
    --varscan_config s: path to varscan.ini file.  Required
parse_varscan_indel:
    --varscan_indel_raw s: Indel output file generated by varscan run.  Required
    --varscan_config s: path to varscan.ini file.  Required
parse_pindel:
    --pindel_config s: path to pindel.ini file.  Required
    --pindel_raw s: raw output file generated by pindel run.  Required 
    --reference_fasta s: path to reference.  Required
    --no_delete_temp : if defined, do not delete temp files
    --bypass_cvs : skip filtering for CvgVafStrand in pindel_filter
    --bypass_homopolymer : skip filtering for Homopolymer in pindel_filter
    --bypass : bypass all filters
    --debug: print out processing details to STDERR
vaf_length_depth_filters: apply VAF, indel length, and read depth filters to a VCF
    --input_vcf s: VCF file to process.  Required
    --output_vcf s: Name of output VCF file (written to results_dir/vaf_length_depth_filters/output_vcf).  Required.
    --caller s: one of strelka, pindel, varscan.  May be defined here or in config file
    --vcf_filter_config: Configuration file for VCF filtering (depth, VAF, read count).  Required
    --bypass_vaf: skip VAF filter
    --bypass_length: skip length filter
    --bypass_depth: skip depth filter
    --bypass: skip all filters
    --debug: print out processing details to STDERR
merge_vcf:
    --strelka_snv_vcf s: output file generated by parse_strelka.  Required
    --strelka_indel_vcf s: output file generated by parse_strelka.  Required
    --varscan_snv_vcf s: output file generated by parse_varscan.  Required
    --varscan_indel_vcf s: output file generated by parse_varscan.  Required
    --mutect_vcf s: output file generated by mutect_tool (not part of TinDaisy-Core).  Required
    --pindel_vcf s: output file generated by parse_pindel.  Required
    --reference_fasta s: path to reference.  Required
    --bypass_merge: Bypass filter by retaining all reads
    --bypass: Same as --bypass_merge
    --debug: print out processing details to STDERR
dbsnp_filter:
    --dbsnp_db s: database for dbSNP filtering.  Step will be skipped if not defined
    --input_vcf s: VCF file to process.  Required
    --bypass_dbsnp: Apply dbSnP annotation to VCF with no further filtering
    --bypass: Same as --bypass_dbsnp
    --debug: print out processing details to STDERR
vep_annotate:  
    --input_vcf s: VCF file to be annotated with vep_annotate.  Required
    --reference_fasta s: path to reference.  Required
    --assembly s: either "GRCh37" or "GRCh38", used to identify cache file. Optional if not ambigous 
    --vep_cache_version s: Cache version, e.g. '90', used to identify cache file.  Optional if not ambiguous
    --vep_cache_gz: is a file ending in .tar.gz containing VEP cache tarball
    --vep_opts s: string with additional arguments to vep_annotate tool.
    --vep_cache_dir s: location of VEP cache directory
        VEP Cache logic:
        * If vep_cache_dir is defined, it indicates location of VEP cache 
        * if vep_cache_dir is not defined, and vep_cache_gz is defined, extract vep_cache_gz contents into "./vep-cache" and use VEP cache
        * if neither vep_cache_dir nor vep_cache_gz defined, will perform online VEP DB lookups
        NOTE: Online VEP database lookups a) uses online database (so cache isn't installed) b) does not use tmp files
          It is meant to be used for testing and lightweight applications.  Use the cache for better performance.
          See discussion: https://www.ensembl.org/info/docs/tools/vep/script/vep_cache.html 
vep_filter:  
    --input_vcf s: VCF file to be annotated with vep_annotate.  Required
    --af_filter_config s: configuration file for af (allele frequency) filter.  Required.
    --classification_filter_config s: configuration file for classification filter.  Required.
    --bypass_af: Bypass AF filter by retaining all reads
    --bypass_classification: Bypass Classification filter by retaining all reads
    --bypass: Bypass all filters
    --debug: print out processing details to STDERR
vcf_2_maf:
    --input_vcf s: VCF file to be annotated with vep_annotate.  Required
    --reference_fasta s: path to reference.  Required
    --assembly s: either "GRCh37" or "GRCh38", used to identify cache file. Optional if not ambigous 
    --vep_cache_version s: Cache version, e.g. '90', used to identify cache file.  Optional if not ambiguous
    --vep_cache_gz: is a file ending in .tar.gz containing VEP cache tarball
    --vep_cache_dir s: location of VEP cache directory
        VEP Cache logic:
        * If vep_cache_dir is defined, it indicates location of VEP cache 
        * if vep_cache_dir is not defined, and vep_cache_gz is defined, extract vep_cache_gz contents into "./vep-cache" and use VEP cache
        * if neither vep_cache_dir nor vep_cache_gz defined, error.  vcf_2_maf does not support online vep_cache lookups
    --exac:  ExAC database to pass to vcf_2_maf.pl as --filter-vcf for custom annotation

OUT

# Argument parsing reference: http://perldoc.perl.org/Getopt/Long.html
# https://perlmaven.com/how-to-process-command-line-arguments-in-perl
my $tumor_bam;
my $normal_bam;
my $assembly;
my $vep_cache_version;
my $reference_fasta;
my $results_dir = ".";  
my $vep_cache_dir;
my $vep_cache_gz;
my $vep_opts;
my $bypass_vaf;    # Boolean
my $bypass_length;    # Boolean
my $bypass_depth;    # Boolean
my $bypass_merge;    # Boolean
my $bypass_af;    # Boolean
my $bypass_classification;    # Boolean
my $bypass_dbsnp;    # Boolean
my $bypass_cvs;    # Boolean
my $bypass;    # Boolean
my $debug;    # Boolean
my $bypass_homopolymer;    # Boolean
my $no_delete_temp; # Boolean
my $strelka_config; 
my $varscan_config; 
my $pindel_config; 
my $centromere_bed; 
my $dbsnp_db;
my $strelka_snv_raw;
my $varscan_indel_raw;
my $varscan_snv_raw;
my $pindel_raw;
my $strelka_snv_vcf;
my $strelka_indel_vcf;
my $varscan_snv_vcf;
my $varscan_indel_vcf;
my $mutect_vcf;
my $pindel_vcf;
my $input_vcf;
my $output_vcf;
my $caller;
my $vcf_filter_config;
my $af_filter_config;
my $classification_filter_config;
my $exac;
my $skip;
my $pindel_chrom;
my $manta_vcf;


GetOptions(
    'tumor_bam=s' => \$tumor_bam,
    'normal_bam=s' => \$normal_bam,
    'reference_fasta=s' => \$reference_fasta,
    'assembly=s' => \$assembly,
    'vep_cache_version=s' => \$vep_cache_version,
    'results_dir=s' => \$results_dir,
    'vep_cache_dir=s' => \$vep_cache_dir,
    'vep_cache_gz=s' => \$vep_cache_gz,
    'vep_opts=s' => \$vep_opts,
    'strelka_config=s' => \$strelka_config,
    'varscan_config=s' => \$varscan_config,
    'pindel_config=s' => \$pindel_config,
    'centromere_bed=s' => \$centromere_bed,
    'dbsnp_db=s' => \$dbsnp_db,
    'strelka_snv_raw=s' => \$strelka_snv_raw,
    'varscan_indel_raw=s' => \$varscan_indel_raw,
    'varscan_snv_raw=s' => \$varscan_snv_raw,
    'pindel_raw=s' => \$pindel_raw,

    'strelka_snv_vcf=s' => \$strelka_snv_vcf,
    'strelka_indel_vcf=s' => \$strelka_indel_vcf,
    'varscan_snv_vcf=s' => \$varscan_snv_vcf,
    'varscan_indel_vcf=s' => \$varscan_indel_vcf,
    'mutect_vcf=s' => \$mutect_vcf,
    'pindel_vcf=s' => \$pindel_vcf,
    'input_vcf=s' => \$input_vcf,
    'output_vcf=s' => \$output_vcf,
    'caller=s' => \$caller,
    'no_delete_temp!' => \$no_delete_temp,
    'bypass_vaf!' => \$bypass_vaf,
    'bypass_length!' => \$bypass_length,
    'bypass_depth!' => \$bypass_depth,
    'bypass_merge!' => \$bypass_merge,
    'bypass_af!' => \$bypass_af,
    'bypass_classification!' => \$bypass_classification,
    'bypass_dbsnp!' => \$bypass_dbsnp,
    'bypass_cvs!' => \$bypass_cvs,
    'bypass!' => \$bypass,
    'debug!' => \$debug,
    'bypass_homopolymer!' => \$bypass_homopolymer,
    'vcf_filter_config=s' => \$vcf_filter_config,
    'af_filter_config=s' => \$af_filter_config,
    'classification_filter_config=s' => \$classification_filter_config,
    'exac=s' => \$exac,
    'skip=s' => \$skip,
    'pindel_chrom=s' => \$pindel_chrom,
    'manta_vcf=s' => \$manta_vcf,
) or die "Error parsing command line args.\n$usage\n";

die $usage unless @ARGV >= 1;
my ( $step_number ) = @ARGV;

# automatically generated scripts in runtime
my $job_files_dir="$results_dir/runtime";  # OUTPUT PORT
system("mkdir -p $job_files_dir");

print STDERR "\nRunning SomaticWrapper step $step_number \n";
print STDERR `git -C $SWpaths::sw_dir log --pretty="commit %H on %ai %d" -1`; # https://git-scm.com/docs/pretty-formats
print STDERR ": \n";
print STDERR "\nSomaticWrapper dir: $SWpaths::sw_dir \n";
print STDERR "Analysis dir: $results_dir\n";
print STDERR "Run script dir: $job_files_dir\n";

# Defining skip allows for optional skipping of steps in CWL workflow.
# Does not generate an error
if ($skip) {
    print STDERR "Step $step_number is skipped: $skip\n";
    print STDERR "Stopping\n";
    exit 0;
}

# numeric step numbers are depricated, but not deleting them for now
if (($step_number eq '1') || ($step_number eq 'run_strelka')) {
    die("tumor_bam undefined \n") unless $tumor_bam;
    die("normal_bam undefined \n") unless $normal_bam;
    die("strelka_config undefined \n") unless $strelka_config;
    die("reference_fasta undefined \n") unless $reference_fasta;
    run_strelka($tumor_bam, $normal_bam, $results_dir, $job_files_dir, $reference_fasta, $strelka_config);

} elsif ($step_number eq 'run_strelka2') {
    die("tumor_bam undefined \n") unless $tumor_bam;
    die("normal_bam undefined \n") unless $normal_bam;
    die("strelka_config undefined \n") unless $strelka_config;
    die("reference_fasta undefined \n") unless $reference_fasta;
    run_strelka2($tumor_bam, $normal_bam, $results_dir, $job_files_dir, $reference_fasta, $strelka_config, $manta_vcf);

} elsif (($step_number eq '2') || ($step_number eq 'run_varscan')) {
    die("tumor_bam undefined \n") unless $tumor_bam;
    die("normal_bam undefined \n") unless $normal_bam;
    die("varscan_config undefined \n") unless $varscan_config;
    die("reference_fasta undefined \n") unless $reference_fasta;
    run_varscan($tumor_bam, $normal_bam, $results_dir, $job_files_dir, $reference_fasta, $varscan_config);

} elsif (($step_number eq '5') || ($step_number eq 'run_pindel')) {
    die("tumor_bam undefined \n") unless $tumor_bam;
    die("normal_bam undefined \n") unless $normal_bam;
    die("reference_fasta undefined \n") unless $reference_fasta;
    run_pindel($tumor_bam, $normal_bam, $results_dir, $job_files_dir, $reference_fasta, $centromere_bed, $no_delete_temp, $pindel_chrom);

} elsif (($step_number eq '4a') || ($step_number eq 'parse_varscan_snv')) {
    die("Varscan Indel Raw input file not specified \n") unless $varscan_indel_raw;
    die("Varscan SNV Raw input file not specified \n") unless $varscan_snv_raw;
    die("varscan_config undefined \n") unless $varscan_config;
    parse_varscan_snv($results_dir, $job_files_dir, $varscan_indel_raw, $varscan_snv_raw, $varscan_config);

} elsif (($step_number eq '4b') || ($step_number eq 'parse_varscan_indel')) {
    die("Varscan Indel Raw input file not specified \n") unless $varscan_indel_raw;
    die("varscan_config undefined \n") unless $varscan_config;
    parse_varscan_indel($results_dir, $job_files_dir, $varscan_indel_raw, $varscan_config);

} elsif (($step_number eq '7') || ($step_number eq 'parse_pindel')) {
    die("pindel_config undefined \n") unless $pindel_config;
    die("pindel raw input file not specified \n") unless $pindel_raw;
    die("reference_fasta undefined \n") unless $reference_fasta;
    parse_pindel($results_dir, $job_files_dir, $reference_fasta, $pindel_config, $pindel_raw, $no_delete_temp, $bypass_cvs, $bypass_homopolymer, $bypass, $debug);

} elsif ($step_number eq 'vaf_length_depth_filters') {
    die("input_vcf undefined \n") unless $input_vcf;
    die("output_vcf undefined \n") unless $output_vcf;
    die("vcf_filter_config undefined \n") unless $vcf_filter_config;
    vaf_length_depth_filters($results_dir, $job_files_dir, $input_vcf, $output_vcf, $caller, $vcf_filter_config, $bypass_vaf, $bypass_length, $bypass_depth, $bypass, $debug);

} elsif (($step_number eq '8') || ($step_number eq 'merge_vcf')) {
    die("strelka_snv_vcf undefined \n") unless $strelka_snv_vcf;
    die("strelka_indel_vcf undefined \n") unless $strelka_indel_vcf;
    die("varscan_snv_vcf undefined \n") unless $varscan_snv_vcf;
    die("varscan_indel_vcf undefined \n") unless $varscan_indel_vcf;
    die("mutect_vcf undefined \n") unless $mutect_vcf;
    die("pindel_vcf undefined \n") unless $pindel_vcf;
    die("reference_fasta undefined \n") unless $reference_fasta;
    if ($bypass) { $bypass_merge = 1; }
    merge_vcf($results_dir, $job_files_dir, $reference_fasta, $strelka_snv_vcf, $strelka_indel_vcf, $varscan_snv_vcf, $varscan_indel_vcf, $mutect_vcf, $pindel_vcf, $bypass_merge, $debug);

#    my $strelka_snv_vcf = shift;
#    my $strelka_indel_vcf = shift; # new
#    my $varscan_snv_vcf = shift;
#    my $varscan_indel_vcf = shift;
#    my $mutect_vcf = shift; # new
#    my $pindel_vcf = shift;

} elsif ($step_number eq 'dbsnp_filter') {
    die("input_vcf undefined \n") unless $input_vcf;
    if ($bypass) { $bypass_dbsnp = 1; } 
    dbsnp_filter($results_dir, $job_files_dir, $dbsnp_db, $input_vcf, $bypass_dbsnp, $debug);

} elsif (($step_number eq '9') || ($step_number eq 'vep_annotate')) {
    die("input_vcf undefined \n") unless $input_vcf;
    die("reference_fasta undefined \n") unless $reference_fasta;
    my $preserve_cache_gz = 0;  # get rid of uncompressed cache directory if expanded from .tar.gz
    vep_annotate($results_dir, $job_files_dir, $reference_fasta, $assembly, $vep_cache_version, $vep_cache_dir, $vep_cache_gz, $preserve_cache_gz, $input_vcf, $vep_opts);

} elsif ($step_number eq 'vep_filter') {
    die("input_vcf undefined \n") unless $input_vcf;
    vep_filter($results_dir, $job_files_dir, $input_vcf, $af_filter_config, $classification_filter_config, $bypass_af, $bypass_classification, $bypass, $debug);

} elsif (($step_number eq '10') || ($step_number eq 'vcf_2_maf')) {
    die("input_vcf undefined \n") unless $input_vcf;
    die("reference_fasta undefined \n") unless $reference_fasta;
    vcf_2_maf($results_dir, $job_files_dir, $reference_fasta, $assembly, $vep_cache_version, $vep_cache_dir, $vep_cache_gz, $input_vcf, $exac);

} else {
    die("Unknown step number $step_number\n");
}
