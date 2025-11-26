#!/usr/bin/env perl

use strict;
use warnings;
use DBI;

use JSON::PP;

use File::Basename;
use File::Spec;

# add lib sub-folder containing modules into @INC
# has to be done this way - cannot assign  File::Basename::dirname(File::Spec->rel2abs($0) (which is directory script lives in) to a variable and then put that in the 'use lib' line, because the use lib line is done at compile time, not run time
use lib File::Spec->catdir(File::Basename::dirname(File::Spec->rel2abs($0)), 'lib');

# add modules from lib-subfolder
use AuditTable;
use ABCInfo;
use Util;
use Mappings;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;


use constant FALSE => \0;
use constant TRUE => \1;

=head1 NAME ticket_scrum-3147-topic-entity-tag.pl


=head1 SYNOPSIS

Used to load FlyBase triage flag information into the Alliance ABC literature database. Generates a json object for each FBrf+triage flag combination which is then submitted using POST to the appropriate ABC server, depending on the script mode provided as one of the arguments.

=cut

=head1 USAGE

USAGE: perl ticket_scrum-3147-topic-entity-tag.pl pg_server db_name pg_username pg_password dev|test|stage|production okta_token


=cut

=head1 DESCRIPTION

Script has four modes:

o dev mode

  o single FBrf mode: asks user for FBrf number (can also use a regular expression to test multiple FBrfs in this mode).

  o makes a json output file (FB_topic_data.stage.json) containing a single json structure for all the data (topic data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source).
  o makes error files (see below) to record any errors.


o test mode

  o single FBrf mode: asks user for FBrf number (must be a single FBrf number, regular expression *not* allowed in this mode).

  o uses curl to try to POST data to the Alliance ABC stage server (so asks user for okta token for Alliance ABC stage server).

  o makes a txt output file (FB_topic_data.stage.txt) - prints a 'DATA:' tsv row for each FBrf+topic combination. For each successful curl POST event, the successfully loaded json element is printed in this file.
  o also makes error files (see below) to record any errors.

o stage mode

  o makes data for all FBrfs in chado, with source ids correct for the ABC *stage* database.

  o makes a json output file (FB_topic_data.stage.json) containing a single json structure for all the data (topic data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source).
  o also makes error files (see below) to record any errors.

o production mode

  o makes data for all FBrfs in chado, with source ids correct for the ABC *production* database.

  o makes a json output file (FB_topic_data.production.json) containing a single json structure for all the data (topic data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source).
  o also makes error files (see below) to record any errors.

o error files (made for all modes)

  o file names include the intended "destination" ABC database - this is 'production' for production mode, and 'stage' for all other modes (this is needed because the id for source information for the topics can be different in production vs stage ABC).

  o FB_topic_data_errors.<destination>.err - errors in mapping FlyBase data to appropriate Alliance json are printed in this file.

  o FB_topic_process_errors.<processing>.err - processing errors - if a curl POST fails in test mode, the failed json element and the reason for the failure are printed in this file. Expected to be empty for all other modes.


Mapping hashes:

o $flags_to_ignore - triage flags that we do not want to submit to the Alliance

o $flag_mapping - triage flags that we DO want to submit to the Alliance, with key value pairs specifying the relevant mapping information and metadata



Script logic:

1. gets FBrf and pub_id of all current publications that have triage flag information.

2. For each pub_id:

2a. gets triage flag details, including the 'I' timestamp from audit_chado (which indicates when the flag was added).

2b. splits the 'raw' triage flag into the flag part and the suffix part (splits on ::) (e.g. disease::DONE -> flag = disease, suffix = DONE).

3. For each triage flag,

3a. the flag is ignored if it is in the $flags_to_ignore hash or it has a suffix and the suffix is 'Inappropriate use of flag' (which indicates the flag is incorrect).

3b. For the remaining flags, the script tries to find the matching curator from the 'curated_by' pubprop for that pub_id by comparing audit_chado timestamps.

- the AuditTable::get_relevant_curator subroutine first gets all matching 'curated_by' pubprops with the same audit_chado 'I' timestamp as the triage flag and then:

- if a single match is found, that curator is used.

- if multiple or no curator matches are found, the flag properties are used to try to determine if it must have been a FB curator that added the flag (rather than community curation) - if that is the case, the curator is set to 'FB_curator'.

3c. If a matching curator was successfully identified, a data structure with the relevant information is made for that flag+FBrf combination, using the flag timestamp from audit_chado and mapping information in the $flag_mapping hash to fill out the data structure.


4. gets internal notes that contain 'Dataset: pheno' information, tries to identify the relevant curator (using same logic as for triage flags in 3.) and if a matching curator is successfully identified, adds the relevant information for each flag+FBrf combination to the same data structure used to store triage flag information in 3.

5. the data structure containing triage flag and 'Dataset: pheno' information is then converted to json, and either submitted to the appropriate ABC server using POST (test mode) or printed (all other modes).


=cut


if (@ARGV != 6) {
    warn "Wrong number of arguments, should be 6!\n";
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|stage|production okta_token\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|stage|production ABCD1234\n\n";
    exit;
}

my $server = shift(@ARGV);
my $db = shift(@ARGV);
my $user = shift(@ARGV);
my $pwd = shift(@ARGV);
my $ENV_STATE = shift(@ARGV);
my $okta_token = shift(@ARGV);


my @STATE = ("dev", "test", "stage", "production");
if (! grep( /^$ENV_STATE$/, @STATE ) ) {
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|stage|production okta_token\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|stage|production ABCD1234\n\n";
    exit;
}

# Sanity check if state is not test, make sure the user wants to
# save the data to the database
unless ($ENV_STATE eq "dev") {
	print STDERR "You are about to write data to $ENV_STATE Alliance literature server\n";
	print STDERR "Type y to continue else anything else to stop:\n";
	my $continue = <STDIN>;
	chomp $continue;
	if (($continue eq 'y') || ($continue eq 'Y')) {
		print STDERR "Processing will continue.";
	} else{
		die "Processing has been cancelled.";
	}
}

my $dsource = sprintf("dbi:Pg:dbname=%s;host=%s;port=5432",$db,$server);
my $dbh = DBI->connect($dsource,$user,$pwd) or die "cannot connect to $dsource\n";


my $json_encoder = JSON::PP->new()->pretty(1)->canonical(1);


# information that depends on the $ENV_STATE chosen
# topic_entity_tag_source from relevant ABC database - this is not always in sync between production vs stage ABC databases, so get the current correct data using an API call when run script, rather than hard-coding 
my $author_source_data = {};
my $curator_source_data = {};

if ($ENV_STATE eq "dev" || $ENV_STATE eq "test") {

	$author_source_data = &get_topic_entity_tag_source_data('stage', 'author');
	$curator_source_data = &get_topic_entity_tag_source_data('stage', 'curator');

} else {

	$author_source_data = &get_topic_entity_tag_source_data($ENV_STATE, 'author');
	$curator_source_data = &get_topic_entity_tag_source_data($ENV_STATE, 'curator');

}




my $test_FBrf = '';

if ($ENV_STATE eq "dev" || $ENV_STATE eq "test") {

	print STDERR "FBrf to test:";
	$test_FBrf = <STDIN>;
	chomp $test_FBrf;

	if ($ENV_STATE eq "test") {

		unless ($test_FBrf =~ m/^FBrf[0-9]{7}$/) {

			die "Only a single FBrf is allowed in test mode."

		}
	}

}

# make list of all publications that have triage flags
my $pub_id_to_FBrf = {};

my $sql_query;

unless ($ENV_STATE eq 'test' || $ENV_STATE eq 'dev') {

	$sql_query = sprintf("select distinct p.uniquename, p.pub_id from pub p, pubprop pp, cvterm c  where p.pub_id=pp.pub_id and c.cvterm_id=pp.type_id and p.is_obsolete='false' and c.name in ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag')");


} else {


	$sql_query = sprintf("select distinct p.uniquename, p.pub_id from pub p, pubprop pp, cvterm c  where p.pub_id=pp.pub_id and c.cvterm_id=pp.type_id and p.is_obsolete='false' and c.name in ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag') and p.uniquename ~'%s'", $test_FBrf);


}

my $db_query= $dbh->prepare  ($sql_query);
$db_query->execute or die" CAN'T GET FBrf FROM CHADO:\n$sql_query)\n";
while (my ($uniquename, $pub_id) = $db_query->fetchrow_array()) {
  $pub_id_to_FBrf->{$pub_id}->{'FBrf'} = $uniquename;
}


# open output and error logging files

# variable to set which Alliance ABC database the output is designed for
my $destination = 'stage';
if ($ENV_STATE eq 'production') {

	$destination = 'production';

}

my $output_file_type = 'json';
if ($ENV_STATE eq 'test') {

	$output_file_type = 'txt';

}

open my $output_file, '>', "FB_topic_data.${destination}.${output_file_type}"
	or die "Can't open output file ($!)\n";


open my $data_error_file, '>', "FB_topic_data_errors.${destination}.err"
	or die "Can't open data error logging file ($!)\n";

open my $process_error_file, '>', "FB_topic_process_errors.${destination}.err"
	or die "Can't open processing error logging file ($!)\n";


# data structures for how/whether to map FB triage flags to corresponding ABC topic info
my $flag_mapping = &get_flag_mapping();
my $flags_to_ignore = &get_flags_to_ignore();


# get all triage flag info
my $flag_info = &get_all_flag_info_with_timestamps($dbh);

my $complete_data = {};



foreach my $pub_id (sort keys %{$flag_info}) {

	if (exists $pub_id_to_FBrf->{$pub_id}) {

		my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};


		foreach my $flag_type (sort keys %{$flag_info->{$pub_id}}) {

			foreach my $flag (sort keys %{$flag_info->{$pub_id}->{$flag_type}}) {

				# 1. only process flags that we want to submit the FB flag to the Alliance
				unless (exists $flags_to_ignore->{$flag_type} && exists $flags_to_ignore->{$flag_type}->{$flag}) {

					if (exists $flag_mapping->{$flag_type} && exists $flag_mapping->{$flag_type}->{$flag}) {


						if (exists $flag_info->{$pub_id}->{$flag_type}->{$flag}->{'Inappropriate use of flag'}) {
							next;
						}


						my $flag_audit_timestamp;
						my $flag_suffix = '';
						if (scalar keys %{$flag_info->{$pub_id}->{$flag_type}->{$flag}} == 1) {

							$flag_suffix = join '', keys %{$flag_info->{$pub_id}->{$flag_type}->{$flag}};
						} else {

							if (exists $flag_info->{$pub_id}->{$flag_type}->{$flag}->{'NO_SUFFIX'}) {
								$flag_suffix = 'NO_SUFFIX';

							}
						}

						if ($flag_suffix ne '') {



							# get the earliest timestamp for when the flag was inserted into chado
							my $flag_audit_timestamp = $flag_info->{$pub_id}->{$flag_type}->{$flag}->{$flag_suffix}->{'I'}[0];


							# 2. try to find the relevant curator (from curated_by pubprop) using audit table timestamp information
							my $curator_data = &get_relevant_curator($dbh, $pub_id, $flag_audit_timestamp);


							my $curator = ''; # this will be the relevant curator with a matching timestamp.
							my $file = ''; # this will be the relevant curation record. Not submitted to the Alliance, but useful for plain text output (DATA: lines) when testing.

###

							if (defined $curator_data) {

								# simple case, only one matching curated_by pubprop
								if ($curator_data->{count} == 1) {

									$curator = $curator_data->{relevant_curator};
									$file = $curator_data->{relevant_record};

								} else {

									# multiple records for same FBrf submitted in same week by same curator
									if (scalar keys %{$curator_data->{curator}} == 1) {

										$curator = join '', keys %{$curator_data->{curator}};
										$file = join ', ', sort keys %{$curator_data->{curator}->{$curator}};

									} else {

										# flag info must have been submitted/looked at by a curator rather than just multiple user curation, so set curator to the generic 'FB_curator'
										if (exists $flag_mapping->{$flag_type}->{$flag}->{curator_only} || $flag_suffix ne '' || (exists $curator_data->{FB_curator_count} && !exists $curator_data->{community_curation_count})) {
											$curator = 'FB_curator';

										} else {
											print $data_error_file "ERROR: multiple different curators that cannot reconcile, not adding: $FBrf\t$flag_type\t$flag\t" . (join ', ', keys %{$curator_data->{curator}}) . "\t" . (join ', ', keys %{$curator_data->{curator}->{$curator}}) . "\t$flag_audit_timestamp\n";

										}

									}

								}

								# convert all unknown style curators to the same 'FB_curator' name that is used for persistent store submissions
								if ($curator eq 'Unknown' || $curator eq 'Unknown Curator' || $curator eq 'Generic Curator' || $curator eq 'P. Leyland') {
									$curator = 'FB_curator';
								}

							} else {

								# flag info must have been submitted/looked at by a curator rather than just user curation, so set curator to the generic 'FB_curator'
								if (exists $flag_mapping->{$flag_type}->{$flag}->{curator_only} || $flag_suffix ne 'NO_SUFFIX') {
									$curator = 'FB_curator';

								} else {

									print $data_error_file "ERROR: unable to find who curated for $flag_type $flag $FBrf\n";
								}
							}



###

####
							# 3. if a curator has been assigned, make a json structure and (unless in dev mode) submit to alliance.

							if ($curator ne '') {


								# first store variables in a $data hash so it is easy to convert to correct json format later (and to add/change json structure if Alliance model changes)
								my $data = {};

								# set basic information for this particular flag and FBrf combination
								my $FBrf_with_prefix="FB:".$FBrf;
								$data->{reference_curie} = $FBrf_with_prefix;

								$data->{created_by} = $curator;
								$data->{date_created} = $flag_audit_timestamp;
								$data->{date_updated} = $flag_audit_timestamp;


								# set other parameters for the flag based on $flag_mapping hash or set the relevant default if the key does not exist in the mapping hash for that flag
								$data->{topic} = $flag_mapping->{$flag_type}->{$flag}->{ATP_topic};

								$data->{species} = exists $flag_mapping->{$flag_type}->{$flag}->{species} ? $flag_mapping->{$flag_type}->{$flag}->{species} : 'NCBITaxon:7227';
								$data->{negated} = exists $flag_mapping->{$flag_type}->{$flag}->{negated} ? TRUE : FALSE;

								$data->{data_novelty} = exists $flag_mapping->{$flag_type}->{$flag}->{data_novelty} ? $flag_mapping->{$flag_type}->{$flag}->{data_novelty} : 'ATP:0000335'; # if the mapping hash has no specific data novelty term set, the parent term (ATP:0000335 = 'data novelty') must be added for ABC validation purposes

								#choose different topic_entity_tag_source_id based on ENV_STATE and 'created_by' value
								if ($curator eq "Author Submission" || $curator eq "User Submission"){
									$data->{topic_entity_tag_source_id} = $author_source_data->{topic_entity_tag_source_id};
								} else {
									$data->{topic_entity_tag_source_id} = $curator_source_data->{topic_entity_tag_source_id};
								}


								my $json_data = $json_encoder->encode($data);


								unless ($ENV_STATE eq "test") {
									push @{$complete_data->{data}}, $data;

								} else {
									my $cmd="curl -X 'POST' 'https://stage-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$json_data'";
									my $raw_result = `$cmd`;
									my $result = $json_encoder->decode($raw_result);


									# plain text output useful for testing
									print $output_file "DATA: $FBrf\t$flag_type\t$flag\t$curator\t$file;\t$flag_audit_timestamp\n";

									if (exists $result->{'status'} && $result->{'status'} eq 'success') {
							
										print $output_file "json post success\nJSON:\n$json_data\n\n";

									} else {

										print $process_error_file "json post failed\nJSON:\n$json_data\nREASON:\n$raw_result\n#################################\n\n";

									}
						
						
								}


							}


####

						} else {

							print $data_error_file "ERROR: more than one suffix type and no 'NO_SUFFIX' for single flag: $pub_id, $flag_type\n";


						}

					} else {

						print $data_error_file "ERROR: no mapping in the the flag_mapping hash for this flag_type:$flag from $flag_type\n";
					}
				}

			}

		}
	}
}

# add data for 'Dataset: pheno' topic
my $dataset_pheno_flag = 'Dataset: pheno';
my $dataset_pheno_note = &get_matching_pubprop_value_with_timestamps($dbh,'internalnotes',$dataset_pheno_flag);


# get relevant data for 'Dataset: pheno'
my $dataset_pheno_data = {};

foreach my $pub_id (sort keys %{$dataset_pheno_note}) {


	# loop to ensure
	# 1. that when in test/dev mode, only get the 'Dataset: pheno' data for the FBrf(s) being tested ($test_FBrf)
	# 2. if NOT in test/dev mode, add any missing pub_id/FBrf mapping (for current publications) to the $pub_id_to_FBrf hash so can be used later when the json data is printed
	unless (exists $pub_id_to_FBrf->{$pub_id}) {

		if ($test_FBrf) {
			next;
		} else {

			my $sql_query = sprintf("select p.uniquename from pub p where p.pub_id='%s' and p.is_obsolete='false'", $pub_id);
			my $db_query= $dbh->prepare($sql_query);
			$db_query->execute or die "CAN'T GET missing 'Dataset: pheno' FBrf FROM CHADO:\n$sql_query)\n";
			while (my ($uniquename) = $db_query->fetchrow_array()) {
				$pub_id_to_FBrf->{$pub_id}->{'FBrf'} = $uniquename;
			}

			# skip if the missing pub_id was not a valid publication
			unless (exists $pub_id_to_FBrf->{$pub_id}) {
				next;
			}

		}

	}

	my $flag_count = 0; # count of whether there has been a plain 'Dataset: pheno' flag (with a datestamp if it exists) for this publication


	foreach my $line (sort keys %{$dataset_pheno_note->{$pub_id}}) {

		my $line_timestamp = $dataset_pheno_note->{$pub_id}->{$line}[0];
		my $curator_data = &get_relevant_curator($dbh, $pub_id, $line_timestamp);
		my $curator = ''; # this will be the relevant curator with a matching timestamp.
		my $file = ''; # this will be the relevant curation record. Not submitted to the Alliance, but useful for plain text output (DATA: lines) when testing.

		my $note = $line;
		$note =~ s/(Author|User): .*? \<.*?\>\. ?//; # get rid of any author details that have crept in in error
		# get rid of notes that are just the Dataset: pheno flag (and a datestamp if it exists), so that only end up with anything to add to note if there is additional info
		$note =~ s/^$dataset_pheno_flag\.?$//;
		$note =~ s/^$dataset_pheno_flag\. ?-?[a-z]{1,} ?[0-9]{6}(\.)?$//;
		$note =~ s/^$dataset_pheno_flag\. [0-9]{6}[a-z]{1,}\.$//;
		$note =~ s/^ +//;


		if (defined $curator_data) {

			# simple case, only one matching curated_by pubprop
			if ($curator_data->{count} == 1) {

				$curator = $curator_data->{relevant_curator};
				$file = $curator_data->{relevant_record};

			} else {

				# multiple records for same FBrf submitted in same week by same curator
				if (scalar keys %{$curator_data->{curator}} == 1) {

					$curator = join '', keys %{$curator_data->{curator}};
					$file = join ', ', sort keys %{$curator_data->{curator}->{$curator}};

				} else {

					# flag info must have been submitted/looked at by a curator rather than just multiple user curation, so set curator to the generic 'FB_curator'
					if (exists $curator_data->{FB_curator_count} && !exists $curator_data->{community_curation_count}) {
						$curator = 'FB_curator';

					} else {
						print $data_error_file "ERROR: multiple different curators that cannot reconcile, not adding: $pub_id\t$line\t" . (join ', ', keys %{$curator_data->{curator}}) . "\t" . (join ', ', keys %{$curator_data->{curator}->{$curator}}) . "\t$line_timestamp\n";

					}

				}

			}

			# convert all unknown style curators to the same 'FB_curator' name that is used for persistent store submissions
			if ($curator eq 'Unknown' || $curator eq 'Unknown Curator' || $curator eq 'Generic Curator' || $curator eq 'P. Leyland') {
				$curator = 'FB_curator';
			}

		} else {


			print $data_error_file "ERROR: unable to find who curated for $pub_id: $line\n";
		}

		if ($curator ne '') {

			unless (exists $dataset_pheno_data->{$pub_id}) {

				$dataset_pheno_data->{$pub_id}->{created_by} = $curator;
				$dataset_pheno_data->{$pub_id}->{date_created} = $line_timestamp;
				$dataset_pheno_data->{$pub_id}->{date_updated} = $line_timestamp;

				if ($note ne '') {
					$dataset_pheno_data->{$pub_id}->{note} = $note;
				}

			} else {


				my $existing_note = exists $dataset_pheno_data->{$pub_id}->{note} ? $dataset_pheno_data->{$pub_id}->{note} : '';

				# not had an internal note that just added 'Dataset: pheno' yet, but have had some other comment
				# in this case, change the created info to the current datestamp as it should be earlier than the other comment
				# also add any additional note text
				if ($flag_count == 0) {

					$dataset_pheno_data->{$pub_id}->{date_updated} = "$dataset_pheno_data->{$pub_id}->{created_by}";
					$dataset_pheno_data->{$pub_id}->{created_by} = $curator;
					$dataset_pheno_data->{$pub_id}->{date_updated} = "$dataset_pheno_data->{$pub_id}->{date_created}";
					$dataset_pheno_data->{$pub_id}->{date_created} = $line_timestamp;

					if ($note ne '') {

						$dataset_pheno_data->{$pub_id}->{note} = ($existing_note) ? ($existing_note . " " . $note) : $note;

					}

				# have already had an internal note that just added 'Dataset: pheno' with no additional info.
				# in this case, only want to change the updated info (plus add note text) if there is additional note text to add
				} else {

					if ($note ne '') {

						$dataset_pheno_data->{$pub_id}->{updated_by} = $curator;
						$dataset_pheno_data->{$pub_id}->{date_updated} = $line_timestamp;
						$dataset_pheno_data->{$pub_id}->{note} = ($existing_note) ? ($existing_note . " " . $note) : $note;

					}

				}

			}
		}


		# add to the count if the internal note was a plain 'Dataset: pheno' flag
		if ($note eq '') {

			$flag_count++;
		}



	}


}

# add Dataset: pheno info to the $complete_data hash

foreach my $pub_id (sort keys %{$dataset_pheno_data}) {



	if (exists $pub_id_to_FBrf->{$pub_id}) {

		# build reference with information for this publication
		my $data = {};

		# set basic information for this particular flag and FBrf combination
		my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
		my $FBrf_with_prefix="FB:".$FBrf;
		$data->{reference_curie} = $FBrf_with_prefix;
		$data->{topic} = "ATP:0000085";
		$data->{species} = 'NCBITaxon:7214', # Drosophilidae
		$data->{data_novelty} = 'ATP:0000335'; # if the mapping hash has no specific data novelty term set, the parent term (ATP:0000335 = 'data novelty') must be added for ABC validation purposes
		$data->{negated} = FALSE;

		foreach my $key (keys %{$dataset_pheno_data->{$pub_id}}) {

			$data->{$key} = $dataset_pheno_data->{$pub_id}->{$key};

		}
		if ($data->{created_by} eq "Author Submission" || $data->{created_by} eq "User Submission"){
			$data->{topic_entity_tag_source_id} = $author_source_data->{topic_entity_tag_source_id};
		} else {
			$data->{topic_entity_tag_source_id} = $curator_source_data->{topic_entity_tag_source_id};
		}

		unless ($ENV_STATE eq "test") {
			push @{$complete_data->{data}}, $data;

		} else {


			my $json_data = $json_encoder->encode($data);

			my $cmd="curl -X 'POST' 'https://stage-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$json_data'";
			my $raw_result = `$cmd`;
			my $result = $json_encoder->decode($raw_result);

			# plain text output useful for testing
			print $output_file "DATA: $FBrf\tDataset: pheno information\n";

			if (exists $result->{'status'} && $result->{'status'} eq 'success') {

				print $output_file "json post success\nJSON:\n$json_data\n\n";

			} else {

				print $process_error_file "json post failed\nJSON:\n$json_data\nREASON:\n$raw_result\n#################################\n\n";

			}


		}



	} else {

		print $data_error_file "ERROR: 'Dataset: pheno '$pub_id with no FBrf in final mapping\n";

	}
}

###

unless ($ENV_STATE eq "test") {

	my $json_metadata = &make_abc_json_metadata($db);
	$complete_data->{"metaData"} = $json_metadata;
	my $complete_json_data = $json_encoder->encode($complete_data);

	print $output_file $complete_json_data;



}


close $output_file;
close $data_error_file;
close $process_error_file;
