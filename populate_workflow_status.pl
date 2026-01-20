#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use JSON::PP;

use File::Basename;
use File::Spec;

# add lib sub-folder containing modules into @INC
use lib File::Spec->catdir(File::Basename::dirname(File::Spec->rel2abs($0)), 'lib');

# add modules from lib-subfolder
use AuditTable;
use ABCInfo;
use Util;
use Mappings;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;


=head1 NAME populate_workflow_status.pl


=head1 SYNOPSIS

Used to load FlyBase curation status information into the Alliance ABC literature database for those types of curation that are stored in the ABC in the 'workflow_tag' table, because they are curation types which are relevant to the publication workflow (how a publication 'moves' through the various automated/manual curation processes at a MOD). Generates an output file containing a single json structure for all the data (the workflow_tag status data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source and the API to use to submit the data into the ABC).

=cut


=head1 USAGE

USAGE: perl populate_workflow_status.pl pg_server db_name pg_username pg_password dev|test|production


=cut



=head1 DESCRIPTION

Types of curation that are relevant to the publication workflow (and thus stored in the Alliance in 'workflow_tag') include those that are:

o important for deciding the next step in the publication workflow process (manual or automated)

  o e.g. if a paper has been community curation via FTYP, there is no need for a FB curator to do first-pass ('skim') curation.

o a type of curation that must have been completed before another type of curation can occur

  o e.g. a paper must have been 'thin' curated (Alliance name: 'manual_indexing') before curation of phenotypic or DO data can occur.

Three types of FB curation are mapped to the appropriate Alliance information by this script:

o community curation

o first pass curation by a biocurator ('skim' curation at FB)

o manual indexing ('thin' curation at FB)


(NB: In the Alliance, curation status for individual datatypes (Alliance name: 'topics') are stored in 'curation_status', NOT 'workflow_tag', so FB curation status info for these types of curation (e.g. phenotype, physical interactions) are not dealt with by this script, but instead by populate_topic_curation_status.pl).

Script has three modes:

o dev mode

  o single FBrf mode: asks user for FBrf number (can also use a regular expression to test multiple FBrfs in this mode).

  o Data is printed to both the json output and 'plain' output files.

  o makes error files (see below) to record any errors.


o test mode

  o single FBrf mode: asks user for FBrf number (must be a single FBrf number).

  o uses curl to try to POST data to the Alliance ABC stage server (so asks user for okta token for Alliance ABC stage server).

  o Data (including a record of successful curl POST events) is printed to the 'plain' output file.

  o makes error files (see below) to record any errors.


o production mode

  o makes data for all relevant FBrfs in chado.

  o Data is printed to the json output file.

  o makes error files (see below) to record any errors.


o Output files


  o json output file (FB_workflow_status_data.json) containing a single json structure for all the data (manual_indexing status data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source). Data is printed to this file in all modes except 'test'.

 o 'plain' output file (FB_workflow_status_data.txt) to aid in debugging - prints the same data as in the json file, but with a single 'DATA:' tsv row for each FBrf+topic combination. Data is printed to this file in all modes except 'production'. In 'test' mode

  o FB_workflow_status_data_errors.err - errors in mapping FlyBase data to appropriate Alliance json are printed in this file. Data is printed to this file in all modes.

  o FB_workflow_status_process_errors.err - processing errors - if a curl POST fails in test mode, the failed json element and the reason for the failure are printed in this file. Expected to be empty for all other modes.

=cut


if (@ARGV != 6) {
    warn "Wrong number of arguments, should be 6!\n";
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|production access_token\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|production ABCD1234\n\n";
    exit;
}

my $server = shift(@ARGV);
my $db = shift(@ARGV);
my $user = shift(@ARGV);
my $pwd = shift(@ARGV);
my $ENV_STATE = shift(@ARGV);
my $access_token = shift(@ARGV);

unless ($ENV_STATE eq 'dev'|| $ENV_STATE eq 'test'|| $ENV_STATE eq 'production') {

	warn "Unknown state '$ENV_STATE': must be 'dev', 'test' or 'production'\n\n";
	exit;

}

my $test_FBrf = '';

# variable that specifies the appropriate path (downstream of the base URL) to use for the Alliance Literature Service API.
# Used to add an element in the metaData object of the output json file and in the curl command used when in test mode.
my $api_endpoint = 'workflow_tag';



if ($ENV_STATE eq "test") {

	print STDERR "You are about to write data to the stage Alliance literature server\n";
	print STDERR "Type y to continue else anything else to stop:\n";

	my $continue = <STDIN>;
	chomp $continue;
	if (($continue eq 'y') || ($continue eq 'Y')) {
		print STDERR "Processing will continue.\n";
	} else {
		die "Processing has been cancelled.\n";

	}

}

if ($ENV_STATE eq "dev" || $ENV_STATE eq "test") {

	print STDERR "FBrf to test:";
	$test_FBrf = <STDIN>;
	chomp $test_FBrf;

	if ($ENV_STATE eq "test") {

		unless ($test_FBrf =~ m/^FBrf[0-9]{7}$/) {
			die "Only a single FBrf is allowed in test mode.\n";
		}
	}
} else {

	$test_FBrf = '^FBrf[0-9]+$';

}

my $dsource = sprintf("dbi:Pg:dbname=%s;host=%s;port=5432",$db,$server);
my $dbh = DBI->connect($dsource,$user,$pwd) or die "cannot connect to $dsource\n";

my $json_encoder = JSON::PP->new()->pretty(1)->canonical(1);



my $workflow_tag_mapping = {

	# community curation
	'0_user' => {
		'finished_status' => 'ATP:0000234', # community curation finished
		'relevant_currec' => ['user'],

	},

	# first pass curation
	'1_skim' => {
		'finished_status' => 'ATP:0000330', # first pass curation finished
		'relevant_currec' => ['skim'],

	},

	# manual indexing
	'2_manual_indexing' => {
		'finished_status' => 'ATP:0000275', # manual indexing complete
		'relevant_currec' => ['thin', 'cam_full', 'gene_full', 'cam_no_suffix'], # use an array so can go through in this order when assigning manual indexing status
		'nocur_override' => 'ATP:0000343', # won't manually index
		'pubtype_filter' => {
			'cam_no_suffix' => ['review'],
		},

	},

};


# structure of the required json for each workflow_tag element
#{
#  "date_created": $timestamp,
#  "date_updated": $timestamp,
#  "created_by": $curator,
#  "updated_by": $curator,
#  "mod_abbreviation": "FB",
#  "reference_curie": FB:$FBrf,
#  "workflow_tag_id": $ATP, # this is the ATP term that describes the status of the particular type of curation
#  "curation_tag": # this is an ATP ID is for the 'controlled_note' - most are negative 
#  "note": # this is a free text note
#}


# open output and error logging files

#open my $json_output_file, '>', "FB_workflow_status_data.json"
#	or die "Can't open json output file ($!)\n";

#open my $data_error_file, '>', "FB_workflow_status_data_errors.err"
#	or die "Can't open data error logging file ($!)\n";

#open my $process_error_file, '>', "FB_workflow_status_process_errors.err"
#	or die "Can't open processing error logging file ($!)\n";


#open my $plain_output_file, '>', "FB_workflow_status_data.txt"
#	or die "Can't open plain output file ($!)\n";


print STDERR "##Starting processing: " . (scalar localtime) . "\n";


## 1. get relevant data for deciding curation status for the various type of workflow_tag curation

# information for community curation status
my ($user_by_timestamp, $user_by_curator) = &get_relevant_currec_for_datatype($dbh,'user');

# information for first pass curation status
my ($skim_by_timestamp, $skim_by_curator) = &get_relevant_currec_for_datatype($dbh,'skim');

# information for manual indexing status
my ($thin_by_timestamp, $thin_by_curator) = &get_relevant_currec_for_datatype($dbh,'thin');
my ($cam_full_by_timestamp, $cam_full_by_curator) = &get_relevant_currec_for_datatype($dbh,'cam_full');
my ($gene_full_by_timestamp, $gene_full_by_curator) = &get_relevant_currec_for_datatype($dbh,'gene_full');
my $nocur_flags = &get_matching_pubprop_value_with_timestamps($dbh,'cam_flag','^nocur$');

# get publications that *do* have links to genetic objects (used for validation)
my $has_genetic_data = &pub_has_curated_data($dbh, 'genetic_data');

## 2. Get list of publications: restrict to the type of pubs where it is useful to export workflow status info (same types as used in populate_topic_curation_status.pl)
my $pub_id_to_FBrf = {};
my $sql_query = sprintf("select p.uniquename, p.pub_id, cvt.name from pub p, cvterm cvt where p.is_obsolete = 'f' and p.type_id = cvt.cvterm_id and cvt.is_obsolete = '0' and cvt.name in ('paper', 'erratum', 'letter', 'note', 'teaching note', 'supplementary material', 'retraction', 'personal communication to FlyBase', 'review') and p.uniquename ~'%s'", $test_FBrf);

my $db_query= $dbh->prepare  ($sql_query);
$db_query->execute or die" CAN'T GET FBrf FROM CHADO:\n$sql_query)\n";
while (my ($uniquename, $pub_id, $pub_type) = $db_query->fetchrow_array()) {
  $pub_id_to_FBrf->{$pub_id}->{'FBrf'} = $uniquename;
  $pub_id_to_FBrf->{$pub_id}->{'type'} = $pub_type;
}


#close $json_output_file;
#close $data_error_file;
#close $process_error_file;
#close $plain_output_file;

print STDERR "##Ended processing: " . (scalar localtime) . "\n";

