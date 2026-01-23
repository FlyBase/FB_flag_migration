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
		'relevant_record_type' => ['user'],
	},

	# first pass curation
	'1_skim' => {
		'finished_status' => 'ATP:0000330', # first pass curation finished
		'relevant_record_type' => ['skim'],

	},

	# manual indexing
	'2_manual_indexing' => {
		'finished_status' => 'ATP:0000275', # manual indexing complete
		'relevant_record_type' => ['thin', 'cam_full', 'gene_full', 'cam_no_suffix'], # use an array so can go through the types in this order when assigning manual indexing status
		'nocur_override' => 'ATP:0000343', # won't manually index
		'pubtype_filter' => {
			'cam_no_suffix' => {
				'review' => '1',
			},
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

my $all_curation_record_data = &get_all_currec_data($dbh);


## 1. get relevant data for deciding curation status for the various type of workflow_tag curation

my $fb_data = {};

foreach my $workflow_type (sort keys %{$workflow_tag_mapping}) {

	foreach my $relevant_record_type (@{$workflow_tag_mapping->{$workflow_type}->{'relevant_record_type'}}) {

		($fb_data->{"$relevant_record_type"}->{"by_timestamp"}, $fb_data->{"$relevant_record_type"}->{"by_curator"}) = &get_relevant_currec_for_datatype($dbh,$relevant_record_type);

	}
}


#print Dumper ($fb_data);


# 2. get data to assign 'no genetic data' curation tag and associated 'won't curate' workflow_tag term
my $nocur_flags = &get_matching_pubprop_value_with_timestamps($dbh,'cam_flag','^nocur|nocur_abs$');

# get publications that *do* have links to genetic objects (used for validation)
my $has_genetic_data = &pub_has_curated_data($dbh, 'genetic_data');

## 3. Get list of publications: restrict to the type of pubs where it is useful to export workflow status info (same types as used in populate_topic_curation_status.pl)
my $pub_id_to_FBrf = {};
my $sql_query = sprintf("select p.uniquename, p.pub_id, cvt.name from pub p, cvterm cvt where p.is_obsolete = 'f' and p.type_id = cvt.cvterm_id and cvt.is_obsolete = '0' and cvt.name in ('paper', 'erratum', 'letter', 'note', 'teaching note', 'supplementary material', 'retraction', 'personal communication to FlyBase', 'review') and p.uniquename ~'%s'", $test_FBrf);

my $db_query= $dbh->prepare  ($sql_query);
$db_query->execute or die" CAN'T GET FBrf FROM CHADO:\n$sql_query)\n";
while (my ($uniquename, $pub_id, $pub_type) = $db_query->fetchrow_array()) {
  $pub_id_to_FBrf->{$pub_id}->{'FBrf'} = $uniquename;
  $pub_id_to_FBrf->{$pub_id}->{'type'} = $pub_type;
}


my $complete_data = {};
my @debugging_output;

foreach my $pub_id (sort keys %{$pub_id_to_FBrf}) {

	my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
	my $pub_type = $pub_id_to_FBrf->{$pub_id}->{'type'};

	# maybe do nocur validation and record status - need to make new subroutine
	my ($nocur_status, $nocur_timestamp, $nocur_note) = &check_and_validate_nocur($nocur_flags, $has_genetic_data, $pub_id);
#	my ($nocur_status, $nocur_timestamp, $nocur_note) = '';


	# switch for tracking whether have set the status of each workflow type already
	my $switch = {

		'0_user' => 0,
		'1_skim' => 0,
		'2_manual_indexing' => 0,


	};

	foreach my $workflow_type (sort keys %{$workflow_tag_mapping}) {


		foreach my $relevant_record_type (@{$workflow_tag_mapping->{$workflow_type}->{'relevant_record_type'}}) {

			if (exists $workflow_tag_mapping->{$workflow_type}->{'pubtype_filter'} && exists $workflow_tag_mapping->{$workflow_type}->{'pubtype_filter'}->{$relevant_record_type}) {


 				unless (exists $workflow_tag_mapping->{$workflow_type}->{'pubtype_filter'}->{$relevant_record_type}->{$pub_type}) {

					next;

				}
			}

			unless ($switch->{"$workflow_type"}) {

				# make new subroutine to get relevant curator and timestamp from $fb_data
				my $curator_details = &get_relevant_curator_from_candidate_list($fb_data->{"$relevant_record_type"}, $pub_id);

				# if there is a matching record for the workflow type, make a json structure for submitting data to the Alliance
				if (defined $curator_details) {


					my $ATP = $workflow_tag_mapping->{$workflow_type}->{'finished_status'};
					my $curation_tag = '';
					my $note = '';
					# set values based on matching record (overriden in a few edge cases below)
					my $curator = "$curator_details->{curator}";
					my $timestamp = "$curator_details->{timestamp}";
					my $curation_records = "$curator_details->{currecs}";
					my $debugging_note = '';

					# for manual indexing, use any nocur information to override the workflow type (to the 'won't curate' style term)
					# and add the appropriate 'no genetic data' curation_tag where appropriate
					if (exists $workflow_tag_mapping->{$workflow_type}->{'nocur_override'}) {

						if ($nocur_status == 1) {
							$ATP = $workflow_tag_mapping->{$workflow_type}->{'nocur_override'};
							$curation_tag = "ATP:0000207"; # no genetic data
							$note = "$nocur_note";

							unless ($timestamp eq $nocur_timestamp) {
								$timestamp = "$nocur_timestamp";
								$debugging_note = "timestamp mismatch: curation record info overwritten by nocur flag info";

								my $nocur_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id, $timestamp);

								if (defined $nocur_details) {

									$curator = "$nocur_details->{curator}";
									$curation_records = "$nocur_details->{currecs}";

								} else {
									$curator = 'FB_curator';
									$curation_records = "WARNING: unable to get curator details for nocur flag";

								}


							}

						}


					}

					# build reference with information for this publication+workflow type combination
					my $data = {};

					my $FBrf_with_prefix="FB:".$FBrf;
					$data->{date_created} = $timestamp;
					$data->{date_updated} = $timestamp;
					$data->{created_by} = $curator;
					$data->{updated_by} = $curator;
					$data->{mod_abbreviation} = "FB";
					$data->{reference_curie} = $FBrf_with_prefix;
					$data->{workflow_tag_id} = $ATP;

					if ($curation_tag) {
						$data->{curation_tag} = $curation_tag;
					}


					if ($note) {
						$data->{note} = $note;
					}



					push @{$complete_data->{data}}, $data;

					my $debugging_output = "DATA:$pub_id\t$FBrf\t$pub_type\t$relevant_record_type\t$curator\t$curation_records\t$ATP\t$curation_tag\t$timestamp\t$note\t$debugging_note";
					push @debugging_output, $debugging_output;

					# set the switch to indicate have set the status for this particular workflow type 
					$switch->{"$workflow_type"}++;


				}

			}
		}

		# once been through all the curation record types for each worfklow_type, see if there is additional information that can be added via nocur flag
		if (exists $workflow_tag_mapping->{$workflow_type}->{'nocur_override'}) {

			unless ($switch->{"$workflow_type"}) {

				if ($nocur_status == 1) {

					my $curator = 'FB_curator'; # default that is overriden with more specific data later where possible
					my $timestamp = "$nocur_timestamp";
					my $curation_records = 'WARNING: unable to get curator details for nocur flag'; # default that is overriden with more specific data later where possible
					my $ATP = $workflow_tag_mapping->{$workflow_type}->{'nocur_override'};
					my $curation_tag = "ATP:0000207"; # no genetic data
					my $note = "$nocur_note";
					my $debugging_note = '';

					# get curator details for the nocur flag and use to override defaults where possible
					my $nocur_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id,$timestamp);

					if (defined $nocur_details) {

						$curator = "$nocur_details->{curator}";
						$curation_records = "$nocur_details->{currecs}";

					}


					# build reference with information for this publication+workflow type combination
					my $data = {};

					my $FBrf_with_prefix="FB:".$FBrf;
					$data->{date_created} = $timestamp;
					$data->{date_updated} = $timestamp;
					$data->{created_by} = $curator;
					$data->{updated_by} = $curator;
					$data->{mod_abbreviation} = "FB";
					$data->{reference_curie} = $FBrf_with_prefix;
					$data->{workflow_tag_id} = $ATP;

					if ($curation_tag) {
						$data->{curation_tag} = $curation_tag;
					}


					if ($note) {
						$data->{note} = $note;
					}

					push @{$complete_data->{data}}, $data;
					my $debugging_output = "DATA:$pub_id\t$FBrf\t$pub_type\tvia flag\t$curator\t$curation_records\t$ATP\t$curation_tag\t$timestamp\t$note\t$debugging_note";
					push @debugging_output, $debugging_output;

					# set the switch to indicate have set the status for this particular workflow type - not sure need this
					$switch->{"$workflow_type"}++;
				}
			}

		}


	}


}

foreach my $line (sort @debugging_output) {

	print "$line\n";


}

print Dumper ($complete_data);

#close $json_output_file;
#close $data_error_file;
#close $process_error_file;
#close $plain_output_file;

print STDERR "##Ended processing: " . (scalar localtime) . "\n";



##############################


sub get_relevant_curator_from_candidate_list {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_relevant_curator_from_candidate_list
	Usage:    get_relevant_curator_from_candidate_list(candidate_list,pub_id);
	Function: Gets relevant curator details for a pub_id specified in the second argument, from the candidate_list provided in the first argument.
	Example:  my $curator_details = &get_relevant_curator_from_candidate_list($fb_data->{"$relevant_record_type"}, $pub_id);

Arguments:

candidate_list contains timestamp, curator name and curation record information for curation records of a particular type, keyed on pub_ids.

candidate_list needs to be a data structure with the following general format, which can be generated by using the get_relevant_currec_for_datatype subroutine (this returns two references that can first be put into the candidate_list->{"by_timestamp"} and candidate_list->{"by_curator"} halves of the data structure before it is passed to get_relevant_curator_from_candidate_list.

o $candidate_list->{"by_timestamp"}->{pub_id}

    o each pub_id refers to an array of the timestamps associated with the pub_id for the curation records, ordered by date.

o $candidate_list->{"by_curator"}->{pub_id}->{curator}->{timestamp}->{record_number}



pub_id is the pub_id of a single reference.

Returns:


o if the pub_id is NOT a key in $candidate_list->{"by_timestamp"}, returns undef (i.e. there is NO curation of this particular curation type for this pub_id).

o if the pub_id IS a key in $candidate_list->{"by_timestamp"}, returns information for the *earliest* curation record from the candidate list (getting the relevant details from $candidate_list->{"by_curator"}).


   o $curator_details->{curator} = curator name
   o $curator_details->{timestamp} = timestamp
   o $curator_details->{currecs} = curation record filename - useful for debugging

If there is more than one 'relevant' curator for the *earliest* timestamp (i.e. if multiple curation records of the same type of curation were submitted for the same pub_id in the same data load) then:

o curator is set as follows:

   o if any of the relevant curators are FB curators - set to 'FB_curator'

   o otherwise, if any of the relevant curators are community curation - set to 'User Submission'

   o otherwise - set to 'ERROR:unable to reconcile curator' so can easily be identified as an error.

o currecs is set to 'multiple curators for same timestamp'


=cut


	unless (@_ == 2) {

		die "Wrong number of parameters passed to the get_relevant_curator_from_candidate_list subroutine\n";
	}


	my ($data, $pub_id) = @_;

	my $curator_details = undef;



	if (exists $data->{"by_timestamp"}->{$pub_id}) {


		# get the timestamp of the *earliest* matching curation record
		my $timestamp = $data->{"by_timestamp"}->{$pub_id}[0];

		# try to determine the relevant curator if appropriate for the topic
		my $relevant_curator = '';
		my $relevant_records = '';


		if (exists $data->{"by_curator"}->{$pub_id}) {

			if (scalar keys %{$data->{"by_curator"}->{$pub_id}} == 1) {
				my $curator_candidate = join '', keys %{$data->{"by_curator"}->{$pub_id}};

				if (exists $data->{"by_curator"}->{$pub_id}->{$curator_candidate}->{$timestamp}) {
					$relevant_curator = $curator_candidate;
					$relevant_records = join ' ', sort keys %{$data->{"by_curator"}->{$pub_id}->{$curator_candidate}->{$timestamp}};

				}
			} else {

				my $count = 0;
				my $curator_count = 0;
				my $community_curation_count = 0;
				foreach my $curator_candidate (sort keys %{$data->{"by_curator"}->{$pub_id}}) {

					foreach my $candidate_timestamp (sort keys %{$data->{"by_curator"}->{$pub_id}->{$curator_candidate}}) {

						if ($candidate_timestamp eq $timestamp) {

							$relevant_curator = $curator_candidate;
							$relevant_records = join ' ', sort keys %{$data->{"by_curator"}->{$pub_id}->{$curator_candidate}->{$candidate_timestamp}};

							unless ($relevant_curator eq 'Author Submission' || $relevant_curator eq 'User Submission' || $relevant_curator eq 'UniProtKB') {

								$curator_count++;
							}

							if ($relevant_curator eq 'Author Submission' || $relevant_curator eq 'User Submission') {

								$community_curation_count++;
							}
							$count++;

						}
					}
				}

				unless ($count == 1) {
					if ($curator_count) {
						$relevant_curator = 'FB_curator';

					} elsif ($community_curation_count) {

						$relevant_curator = 'User Submission';

					} else {

						$relevant_curator = 'ERROR:unable to reconcile curator';
					}
					$relevant_records = 'multiple curators for same timestamp';

				}
			}
		}

		if ($relevant_curator) {

			$curator_details->{curator} = $relevant_curator;
			$curator_details->{timestamp} = $timestamp;
			$curator_details->{currecs} = $relevant_records; # useful for debugging

		}


	}

	return $curator_details;
}



