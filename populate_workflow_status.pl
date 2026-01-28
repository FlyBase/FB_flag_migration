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

use Encode;
binmode(STDOUT, ":utf8");

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
		'high_priority_override' => 'ATP:0000274', # manual indexing needed

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


## get relevant data for deciding curation status for the various type of workflow_tag curation

my $fb_data = {};

foreach my $workflow_type (sort keys %{$workflow_tag_mapping}) {

	foreach my $relevant_record_type (@{$workflow_tag_mapping->{$workflow_type}->{'relevant_record_type'}}) {

		($fb_data->{"$relevant_record_type"}->{"by_timestamp"}, $fb_data->{"$relevant_record_type"}->{"by_curator"}) = &get_relevant_currec_for_datatype($dbh,$relevant_record_type);

	}
}


#print Dumper ($fb_data);


## get data to assign 'no genetic data' curation tag and associated 'won't curate' workflow_tag term
my $nocur_flags = &get_matching_pubprop_value_with_timestamps($dbh,'cam_flag','^nocur|nocur_abs$');

## get publications that *do* have links to genetic objects (used for validation)
my $has_genetic_data = &pub_has_curated_data($dbh, 'genetic_data');

## get diseaseHP flags so can assign manual indexing 'needs curation' where appropriate
my $diseaseHP_flags = {};

$diseaseHP_flags->{'dis_flag'} = &get_matching_pubprop_value_with_timestamps($dbh,'dis_flag','^diseaseHP$');

$diseaseHP_flags->{'harv_flag'} = &get_matching_pubprop_value_with_timestamps($dbh,'harv_flag','^diseaseHP$');

#print Dumper ($diseaseHP_flags);

my $additional_filters = [

	# Use simple regex to remove *all* 'Dataset:' lines - will be converted to a topic and/or associated free text note in another script
	# The commented out lines are the regexes needed to identify the 'Dataset: pheno' lines for the topic scripts
	#'^Dataset: pheno\.?$',
	#'^Dataset: pheno\. ?-?[a-z]{1,} ?[0-9]{6}(\.)?$',
	#'^Dataset: pheno\. [0-9]{6}[a-z]{1,}\.$',
	'^(D|d)ataset:.+$',

	# filters to remove lines that will be converted to a topic *status* and/or associated free text note in another script
	'^HDM flag not applicable\.?( *[a-z]{1,}[0-9]{6})?$',
	'^phen curation: only pheno_chem data in paper\.( *[a-z]{2}[0-9]{6}\.?)?$',
	'^phen curation: No phenotypic data in paper\.( *[a-z]{2}[0-9]{6}\.?)?$',
	'^phen_cur: CV annotations only(\. *[a-z]{2}[0-9]{6}\.?)?$',
	'^phys_int not curated.+$',

	# filters to remove lines that will be converted to a free text note attached to a topic in another script
	'^The phys_int flag inferred from.+$',
	'^The phys_int flag is inferred from.+$',
	'^The phys_int flag was inferred.+$',

];

## get any relevant internal notes to be added to the free text note slot of a workflow_tag element - first filtering out any internal notes that do not need to be added by this script (they will instead either be converted into an ATP term corresponding to a topic or controlled note in the Alliance, or added as a free text note to a specific topic), using the regexes specified in $additional_filters.
my $all_candidate_internal_notes = &get_all_pub_internal_notes_for_tet_wf($dbh, $additional_filters);

## then remove any internal notes that come from curation records for a particular topic - these will be added as a note to the curation status of the *topic* in another script, rather than being added to the more general workflow_tag categories in this script.
# any remaining internal notes will be those either submitted under one of the workflow_tag types for this script (identified later through matching timestamp and curation record filename information) or under an 'edit' record - the latter will be added to the most appropriate workflow_tag with a note indicating it was an edit record
my @topic_record_types = ('cell_line', 'phys_int', 'DO', 'neur_exp', 'wt_exp', 'chemical', 'args', 'phen', 'humanhealth');

foreach my $topic_record_type (@topic_record_types) {

	my (undef, $curation_record_data) = &get_relevant_currec_for_datatype($dbh,$topic_record_type);


	foreach my $pub_id (keys %{$all_candidate_internal_notes}) {

		foreach my $int_note (keys %{$all_candidate_internal_notes->{$pub_id}}) {

		foreach my $timestamp (@{$all_candidate_internal_notes->{$pub_id}->{$int_note}}) {
			my $int_note_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id, $timestamp);

			if (defined $int_note_details && $int_note_details->{currecs} ne 'multiple curators for same timestamp') {

				if (exists $curation_record_data->{$pub_id}->{"$int_note_details->{curator}"} && exists $curation_record_data->{$pub_id}->{"$int_note_details->{curator}"}->{$timestamp}->{"$int_note_details->{currecs}"}) {

					delete $all_candidate_internal_notes->{$pub_id}->{$int_note};
					next;
				}
			}


		}
	}
}



}


## Get list of publications: restrict to the type of pubs where it is useful to export workflow status info (same types as used in populate_topic_curation_status.pl)
my $pub_id_to_FBrf = {};
my $sql_query = sprintf("select p.uniquename, p.pub_id, cvt.name from pub p, cvterm cvt where p.is_obsolete = 'f' and p.type_id = cvt.cvterm_id and cvt.is_obsolete = '0' and cvt.name in ('paper', 'erratum', 'letter', 'note', 'teaching note', 'supplementary material', 'retraction', 'personal communication to FlyBase', 'review') and p.uniquename ~'%s'", $test_FBrf);

my $db_query= $dbh->prepare  ($sql_query);
$db_query->execute or die" CAN'T GET FBrf FROM CHADO:\n$sql_query)\n";
while (my ($uniquename, $pub_id, $pub_type) = $db_query->fetchrow_array()) {
  $pub_id_to_FBrf->{$pub_id}->{'FBrf'} = $uniquename;
  $pub_id_to_FBrf->{$pub_id}->{'type'} = $pub_type;
}


my $workflow_status_data = {};


foreach my $pub_id (sort keys %{$pub_id_to_FBrf}) {

	my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
	my $pub_type = $pub_id_to_FBrf->{$pub_id}->{'type'};

	# maybe do nocur validation and record status - need to make new subroutine
	my ($nocur_status, $nocur_timestamp, $nocur_note) = &check_and_validate_nocur($nocur_flags, $has_genetic_data, $pub_id);
#	my ($nocur_status, $nocur_timestamp, $nocur_note) = '';


	foreach my $workflow_type (sort keys %{$workflow_tag_mapping}) {


		foreach my $relevant_record_type (@{$workflow_tag_mapping->{$workflow_type}->{'relevant_record_type'}}) {

			if (exists $workflow_tag_mapping->{$workflow_type}->{'pubtype_filter'} && exists $workflow_tag_mapping->{$workflow_type}->{'pubtype_filter'}->{$relevant_record_type}) {


 				unless (exists $workflow_tag_mapping->{$workflow_type}->{'pubtype_filter'}->{$relevant_record_type}->{$pub_type}) {

					next;

				}
			}

			unless (exists $workflow_status_data->{$pub_id}->{$workflow_type}) {

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

					my $FBrf_with_prefix="FB:".$FBrf;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{date_created} = $timestamp;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{date_updated} = $timestamp;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{created_by} = $curator;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{updated_by} = $curator;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{mod_abbreviation} = "FB";
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{reference_curie} = $FBrf_with_prefix;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{workflow_tag_id} = $ATP;

					if ($curation_tag) {
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{curation_tag} = $curation_tag;
					}


					if ($note) {
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{note} = $note;
					}


					$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{currecs} = $curation_records;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{note} = $debugging_note;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{relevant_record_type} = $relevant_record_type;

				}

			}
		}

		# once been through all the curation record types for each workflow_type, see if there is additional information that can be added via nocur flag
		if (exists $workflow_tag_mapping->{$workflow_type}->{'nocur_override'}) {

			unless (exists $workflow_status_data->{$pub_id}->{$workflow_type}) {

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

					# override edge cases where a curator added nocur in a user record
					if ($curator eq 'Author Submission' || $curator eq 'User Submission') {
						$curator = 'FB_curator';

					}


					# build reference with information for this publication+workflow type combination

					my $FBrf_with_prefix="FB:".$FBrf;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{date_created} = $timestamp;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{date_updated} = $timestamp;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{created_by} = $curator;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{updated_by} = $curator;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{mod_abbreviation} = "FB";
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{reference_curie} = $FBrf_with_prefix;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{workflow_tag_id} = $ATP;

					#

					if ($curation_tag) {
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{curation_tag} = $curation_tag;
					}


					if ($note) {
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{note} = $note;
					}


					$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{currecs} = $curation_records;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{note} = $debugging_note;
					$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{relevant_record_type} = 'via flag';

				}
			}

		}

		# next, see if there are any non-curated papers that should be marked as 'need curation' as they are high-priority
		if (exists $workflow_tag_mapping->{$workflow_type}->{'high_priority_override'}) {

			foreach my $flag_type (sort keys %{$diseaseHP_flags}) {

				unless (exists $workflow_status_data->{$pub_id}->{$workflow_type}) {

					if (exists $diseaseHP_flags->{$flag_type}->{$pub_id}) {

						my $ATP = $workflow_tag_mapping->{$workflow_type}->{'high_priority_override'};
						my $curation_tag = "ATP:0000353"; # high priority data
						my $note = '';
						my $debugging_note = '';


						my $timestamp = $diseaseHP_flags->{$flag_type}->{$pub_id}->{diseaseHP}[0];
						# set generic defaults that are overwritten later with more specific information
						my $curator = 'FB_curator';
						my $curation_records = '';


						# get curator details for the diseaseHP flag and use to override generic defaults where possible
						my $diseaseHP_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id, $timestamp);

						if (defined $diseaseHP_details) {

							$curator = "$diseaseHP_details->{curator}";
							$curation_records = "$diseaseHP_details->{currecs}";

						}


						# build reference with information for this publication+workflow type combination

						my $FBrf_with_prefix="FB:".$FBrf;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{date_created} = $timestamp;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{date_updated} = $timestamp;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{created_by} = $curator;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{updated_by} = $curator;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{mod_abbreviation} = "FB";
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{reference_curie} = $FBrf_with_prefix;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{workflow_tag_id} = $ATP;

						if ($curation_tag) {
							$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{curation_tag} = $curation_tag;
						}


						if ($note) {
							$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{note} = $note;
						}
						$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{currecs} = $curation_records;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{note} = $debugging_note;
						$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{relevant_record_type} = 'from diseaseHP';

					}
				}

			}

		}

	}


}

# try to add relevant publication-level internal notes where appropriates

foreach my $pub_id (sort keys %{$all_candidate_internal_notes}) {

	if (exists $workflow_status_data->{$pub_id}) {

		foreach my $int_note (sort keys %{$all_candidate_internal_notes->{$pub_id}}) {

			my $switch = 0;
			my $reformatted_note = "$int_note";
			$reformatted_note =~ s/\n/ /g;

			# for internal notes with a single timestamp
			if (scalar @{$all_candidate_internal_notes->{$pub_id}->{$int_note}} == 1) {


				my $int_note_timestamp = join '', @{$all_candidate_internal_notes->{$pub_id}->{$int_note}};


				# 1. go through the different workflow_tags to find cases where both the timestamp and curation records show a match
				foreach my $workflow_type (sort keys %{$workflow_status_data->{$pub_id}}) {

					unless ($switch) {
						my $workflow_type_timestamp = "$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{date_created}";
						my $workflow_type_currecs = "$workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{currecs}";
						my $workflow_type_curator = "$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{created_by}";

						#print "HERE2: workflow: $workflow_type_currecs, $workflow_type_timestamp\n";

						# 2. if the timestamps of the workflow tag and internal note match
						if ($int_note_timestamp eq $workflow_type_timestamp) {

							my $int_note_curator_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id, $int_note_timestamp);


							# 3. get the curation record details for the internal note to check against those of workflow_tag
							if (defined $int_note_curator_details) {

								my $int_note_currecs = "$int_note_curator_details->{currecs}";
								my $int_note_curator = "$int_note_curator_details->{curator}";


								#print "HERE: internal note: $int_note_currecs, $int_note_timestamp\n";

								# 4. if the curation record for the workflow type is in the list of possibilities for the internal note
								# and there is only one curator possibility for that timestamp
								# then the internal note can be added to the entry for that workflow tag
								if ($int_note_currecs =~ m/$workflow_type_currecs/ && $int_note_currecs ne 'multiple curators for same timestamp') {

									$switch++;


									if (exists $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{note}) {


										my $note = "$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{note}";
										$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{note} = "$note||$int_note";


									} else {

										$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{note} = "$int_note";

									}
								}

							}

						}

					}
				}


			} else {

				print "WARNING: internal note(s) with MULTIPLE TIMESTAMPS: $pub_id\t$pub_id_to_FBrf->{$pub_id}->{'FBrf'}\t$pub_id_to_FBrf->{$pub_id}->{'type'}\t$reformatted_note\n";


			}

			unless ($switch) {

				print "WARNING: internal note(s) that could not match up: $pub_id\t$pub_id_to_FBrf->{$pub_id}->{'FBrf'}\t$pub_id_to_FBrf->{$pub_id}->{'type'}\t$reformatted_note\n";


			}
		}
	}
}


#print Dumper ($workflow_status_data);

my $complete_data = {};


foreach my $pub_id (sort keys %{$workflow_status_data}) {

	foreach my $workflow_type (sort keys %{$workflow_status_data->{$pub_id}}) {

		my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
		my $pub_type = $pub_id_to_FBrf->{$pub_id}->{'type'};



		#store data for making json later
		push @{$complete_data->{data}}, $workflow_status_data->{$pub_id}->{$workflow_type}->{json};

		# simple output for testing/debugging
		my $curated_by = $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'created_by'} ? "$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'created_by'}" : '';
		my $updated_by = $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'updated_by'} ? "$workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'updated_by'}" : '';


		my $workflow_tag_id = exists $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'workflow_tag_id'} ? $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'workflow_tag_id'} : '';
		my $date_created = exists $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'date_created'} ? $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'date_created'} : '';


		my $curation_tag = exists $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'curation_tag'} ? $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'curation_tag'} : '';
		my $note = exists $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'note'} ? $workflow_status_data->{$pub_id}->{$workflow_type}->{json}->{'note'} : '';
		$note =~ s/\n/ /g;

		my $curation_records = exists $workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{currecs} ? $workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{currecs} : '';
		my $debugging_note = exists $workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{note} ? $workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{note} : '';
		my $relevant_record_type = exists $workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{relevant_record_type} ? $workflow_status_data->{$pub_id}->{$workflow_type}->{debugging}->{relevant_record_type} : '';


		print "DATA:$pub_id\t$FBrf\t$pub_type\t$relevant_record_type\t$curated_by\t$curation_records\t$workflow_tag_id\t$curation_tag\t$date_created\t$note\t$debugging_note\n";
	}
}

print Dumper ($complete_data);


#close $json_output_file;
#close $data_error_file;
#close $process_error_file;
#close $plain_output_file;

print STDERR "##Ended processing: " . (scalar localtime) . "\n";


