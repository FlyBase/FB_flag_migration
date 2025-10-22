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



use constant FALSE => \0;
use constant TRUE => \1;

=head1 NAME populate_topic_curation_status.pl


=head1 SYNOPSIS

Used to load FlyBase curation status information into the Alliance ABC literature database for individual topics (ie. triage flags). Generates an output file containing a single json structure for all the data (curation status data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source and intended destination database).

=cut

=head1 USAGE

USAGE: perl populate_topic_curation_status.pl pg_server db_name pg_username pg_password dev|test|stage|production


=cut

=head1 DESCRIPTION


Mapping hashes: 

o $curation_status_topics - mapping hash of topics that we want to submit curation status information for to the Alliance. This hash is structured from the point of view of the relevant ATP topics, to make processing easier. This hash is built using the information in the standard $flag_mapping mapping hash obtained from the &get_flag_mapping subroutine; more than one FB triage flag in the $flag_mapping mapping hash can collapse down to a single ATP topic for curation status tracking.


o $flag_suffix_mapping - mapping of FB triage flag suffixes to:

  o either the appropriate ATP term describing curation status; terms are children of the 'curation' (ATP:0000230) - workflow tag.
  o or 'undef' if the suffix is not relevant to curation status (so that these irrelevant suffixes can be ignored later on in the script).



Script logic:

1. Builds the $curation_status_topics hash to build a list of the ATP topics for which we want to export curation status information to the Alliance.

2. For each ATP topic in the $curation_status_topics hash the following data is then gathered:

2a. If relevant for the topic (when the ATP topic has a 'suffix' key in $curation_status_topics), makes a list ($flags_with_suffix) of all pub_id that have any of the relevant FB triage flags for that ATP topic, where the FB triage flag has a suffix. The list stores the ATP curation status and timestamp information for each pub_id+ATP topic combination.

2b. If relevant for the topic (when the ATP topic has a 'get_curated_data' key in $curation_status_topics), makes a list ($has_curated_data) of all pub_id that have curated data corresponding to the ATP topic (this allows QA/QC later).

2c. If relevant for the topic (when the ATP topic has a 'use_filename' key in $curation_status_topics), makes a list ($currecs_by_timestamp) of all pub_id that are *expected* to contain curated data corresponding to the ATP topic because they have a curation record with the standard filename format for that topic (this allows QA/QC later, and also allows additional information to be exported to the Alliance for those publications that were curated *before* we started using triage flags in FB).

2d. If relevant for the topic (when the ATP topic has a 'relevant_internal_note' key in $curation_status_topics), gets a list of internal notes that are relevant to determining curation status and/or need to be submitted to the Alliance as a 'note' that is appended to the curation status for that topic.

3. If the curation status in FB is recorded using a :: suffix appended to the FB triage flag, this is used first to try to determine curation status.

3a. For some topics, the triage flag suffix alone is sufficient to determine curation status without using any additional information (value of 'suffix' key is 'only').

3b. For other topics, additional QA/QC is done to determine the final curation status to submit to the Alliance.

This is necessary because for some FB triage flags, the suffix '::DONE' has been used in the past to mean two different things:

o there is data for that triage flag and the relevant curation has been 'done'.

o the FB triage flag was incorrect and that there is therefore nothing to curate for that particular datatype.

The additional QA/QC checks use the following information to determine the final curation status which is stored along with any relevant 'controlled_tag' and/or 'note' information:

- does the publication contains the curated data of the relevant datatype ?
- is there a curation record with the standard filename format expected for that datatype ?
- is there an internal note that is relevant to determining the curation status ?


4. Then, the list of publications that have a curation record with the standard filename format expected for that datatype is used to fill in curation status for any publications that have not already been taken care of in 3.


This is needed to add curation status for publications where the curation was done in FB before we started using triage flags.

Again, the curation status is stored along with any relevant 'controlled_tag' and/or 'note' information.


5. Converts the stored list ATP curation status and timestamp information for each pub_id into json format for submission to the ABC. [this is not yet implemented]


NOTE: The script uses the above more complicated logic rather than only using the list made in 2b. of publications that that have curated data corresponding to the ATP topic data because the presence of data in the database does not give any indication of how *complete* the curation is for a given topic, but that detail can be mapped from the FB flag suffixes and standard curation record filename information.

NOTE on timestamps:

o For timestamps determined from the FB triage flag suffix, the *latest* timestamp for the pub+triage flag combination in FB is used, because this should correspond to the timestamp of when the curation of the datatype occurred (the earliest timestamp can indicate the timestamp when the triage flag (without suffix) was added to the database, rather than the curation of the datatype).

o For timestamps determined from curation record(s) with the standard filename format expected for that datatype, the *earliest* timestamp for any matching records for the pub+topic combination in FB is used, because this should correspond to the first (main) curation record containing the curation for that datatype (rather than any subsequent edits).

=cut



if (@ARGV != 5) {
    warn "Wrong number of arguments, should be 5!\n";
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|stage|production\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|stage|production\n\n";
    exit;
}

my $server = shift(@ARGV);
my $db = shift(@ARGV);
my $user = shift(@ARGV);
my $pwd = shift(@ARGV);
my $ENV_STATE = shift(@ARGV);



my $dsource = sprintf("dbi:Pg:dbname=%s;host=%s;port=5432",$db,$server);
my $dbh = DBI->connect($dsource,$user,$pwd) or die "cannot connect to $dsource\n";


# map bit after :: when present in flag according to the type of information it adds wrt curation status
my $flag_suffix_mapping = {

	'DONE' => {
		'curation_status' => 'ATP:0000239', # 'curated'
	},

	'Partially done' => {

		'curation_status' => 'ATP:0000239', # 'curated'
		'note' => 'Partial curation.',
	},

	'in progress' => {

		'curation_status' => 'ATP:0000237', # 'curation in progress'
	},

	'Author query sent' => {

		'curation_status' => 'ATP:0000236', # 'curation blocked'
		'note' => 'Author query sent.',
	},

	'No response to author query' => {

		'curation_status' => 'ATP:0000236', # 'curation blocked'
		'note' => 'No response to author query.',
	},

	'Needs cam curation' => {

		'curation_status' => 'ATP:0000236', # 'curation blocked'
		'note' => 'Needs manual indexing.', # should also add a needs curating status to the manual indexing part in the Alliance
	},

# suffix that does not add information about the curation status of the topic to which the suffix is attached
# the information that the topic is incorrect will need to be used (in different script) to prevent adding the relevant topic
# need to use it here to suppress false-positive WARNING messages 
	'Inappropriate use of flag' => undef,


#	'untouched' => undef, # not sure how to deal with this yes, so commented out to find all the cases
};


# structure of the required json for each element
#{
#  "date_created": $timestamp,
#  "date_updated": $timestamp,
#  "created_by": $curator,
#  "updated_by": $curator,
#  "mod_abbreviation": "FB",
#  "reference_curie": FB:$FBrf,
#  "topic": $ATP,
#  "curation_status": $flag_suffix_mapping->{$ATP}->{'curation_status'},
#  "note": $flag_suffix_mapping->{$ATP}->{'note'}
#  "curation_tag": # this is for the 'controlled_note' - most are negative 
#}



# 1. Use the mapping information obtained from &get_flag_mapping to make a $curation_status_topics mapping hash
# from the point of view of the ATP topic term that will be used to submit curation_status info into the ABC.
my $flag_mapping = &get_flag_mapping();
my $curation_status_topics = {};


# 1a. First fill in the relevant information for FB triage flags which can have a suffix that is relevant to curation status.
foreach my $flag_type (sort keys %{$flag_mapping}) {

	foreach my $flag (sort keys %{$flag_mapping->{$flag_type}}) {

		if (exists $flag_mapping->{$flag_type}->{$flag}->{'for_curation_status'}) {

			my $ATP = $flag_mapping->{$flag_type}->{$flag}->{ATP_topic};

			$curation_status_topics->{$ATP}->{'flag_type_list'}->{$flag_type}++;

			push @{$curation_status_topics->{$ATP}->{'flags'}}, $flag;

# assign information from $flag_mapping that was originally under for_curation_status for the flag to a hash where the key has '_list' appended to the end.
# this allows for QC in 1b. below, to make sure that when multiple FB flags map to a single ATP topic all the curation_status related data for each flag is consistent
			foreach my $key (sort keys %{$flag_mapping->{$flag_type}->{$flag}->{'for_curation_status'}}) {


				my $value = $flag_mapping->{$flag_type}->{$flag}->{'for_curation_status'}->{$key};

				my $list_key = "$key" . "_list";
				
				$curation_status_topics->{$ATP}->{$list_key}->{$value}++;

			}
		}
	}

}

# 1b. check for data conflicts after populating $curation_status_topics and warn if needed.
# this checks that when multiple FB triage flags map to a single ATP topic, the curation_status related data coming from each FB triage flag is consistent.
foreach my $ATP (sort keys %{$curation_status_topics}) {

	foreach my $key (sort keys %{$curation_status_topics->{$ATP}}) {

		if ($key =~ m/_list$/) {

			if (scalar keys %{$curation_status_topics->{$ATP}->{$key}} == 1) {

				my $key_minus_list = "$key";
				$key_minus_list =~ s/_list$//;
				my $value = join '', keys %{$curation_status_topics->{$ATP}->{$key}};
				$curation_status_topics->{$ATP}->{$key_minus_list} = $value;
				delete $curation_status_topics->{$ATP}->{$key}; # remove unecessary '_list' branch if passes checks

			} else {

				my $key_minus_list = "$key";
				$key_minus_list =~ s/_list$//;

				if ($key eq 'flag_type_list') {
					warn "\$curation_status_topics: The ATP term: $ATP is being used for triage flags in different flag_type slots in chado - cannot process this.\n";

				} else {
					warn "\$curation_status_topics: $ATP has multiple values in the '$key' slot - cannot process this as it indicates a data conflict.\nValues were: " . (join ' ', (sort keys %{$curation_status_topics->{$ATP}->{$key}})). "\nFix values of the '$key_minus_list' key for flags that map to $ATP in the get_flag_mapping of Mappings.pm to remove the conflict.\n";
				}
			}
		}


	}
}




#print Dumper ($curation_status_topics);
#die;

# 2. go through each topic in the $curation_status_topics hash, determine and store curation status, using relevant information for that flag (this is specified in the $curation_status_topics hash).


foreach my $ATP (sort keys %{$curation_status_topics}) {

	my $curation_status_data = {};

	# get relevant info for the topic
	# get references with triage flag(s) with suffixes for the flag(s) that correspond to the ATP topic
	my $flags_with_suffix = undef;
	if (exists $curation_status_topics->{$ATP}->{'suffix'}) {
		$flags_with_suffix = &get_timestamps_for_flaglist_with_suffix($dbh,$curation_status_topics->{$ATP}->{'flag_type'},$curation_status_topics->{$ATP}->{'flags'});
	}
	# if appropriate, get references that have curated data corresponding to the ATP topic (identified from direct db query for references containing the datatype)
	my $has_curated_data = undef;
	if (exists $curation_status_topics->{$ATP}->{'get_curated_data'}) {
		$has_curated_data = &pub_has_curated_data($dbh,$curation_status_topics->{$ATP}->{'get_curated_data'});
	}

	# if appropriate, get references that are *expected* to contain curated data corresponding to the ATP topic, based on curation record filename.
	my $currecs_by_timestamp = undef;
	if (exists $curation_status_topics->{$ATP}->{'use_filename'}) {
		($currecs_by_timestamp, undef) = &get_relevant_currec_for_datatype($dbh,$curation_status_topics->{$ATP}->{'use_filename'});
	}

	#additional 'cam_full' curation record filename info - needed for pheno flag
	my $cam_full_by_timestamp = undef;
	if (exists $curation_status_topics->{$ATP}->{'use_cam_full_filename'}) {
		($cam_full_by_timestamp, undef) = &get_relevant_currec_for_datatype($dbh,'cam_full');
	}

	# if appropriate, get internal notes relevant to curation status for the flag
	my $relevant_internal_notes = undef;
	if (exists $curation_status_topics->{$ATP}->{'relevant_internal_note'}) {

		$relevant_internal_notes = &get_matching_pubprop_value_with_timestamps($dbh,'internalnotes',$curation_status_topics->{$ATP}->{'relevant_internal_note'});
	}

	# first assign curation status based on flag suffixes, double-checking that there is curated data of the relevant type, if that is appropriate for the particular flag
	if (defined $flags_with_suffix) {
		foreach my $pub_id (sort keys %{$flags_with_suffix}) {

			if (scalar keys %{$flags_with_suffix->{$pub_id}} == 1) {

				my $suffix = join '', keys %{$flags_with_suffix->{$pub_id}};

				if (exists $flag_suffix_mapping->{$suffix}) {

					# only consider suffixes that are relevant to curation status
					if (defined $flag_suffix_mapping->{$suffix}) {

						my $curation_status = $flag_suffix_mapping->{$suffix}->{curation_status};

						my $curation_tag = '';
						my $note = '';

						if (defined $relevant_internal_notes && exists $relevant_internal_notes->{$pub_id}) {
							$note = $note . (join ' ', sort keys %{$relevant_internal_notes->{$pub_id}});
						}

						if (exists $flag_suffix_mapping->{$suffix}->{note}) {
							$note = $note . " $flag_suffix_mapping->{$suffix}->{note}";
						}
						$note =~ s/^ //;


						my $timestamp = $flags_with_suffix->{$pub_id}->{$suffix}->{'timestamp'}[-1];

						my $store_status = 0;

						# flag suffix can be used by itself to store curation status. DESCRIPTION, Script logic: 3a.
						if (exists $curation_status_topics->{$ATP}->{'suffix'} && $curation_status_topics->{$ATP}->{'suffix'} eq 'only') {
							$store_status++;

						} else {

							# always safe to store curation status when it is something other than 'curated' regardless of whether or not FB db contains relevant data
							unless (exists $flag_suffix_mapping->{$suffix}->{'curation_status'} && $flag_suffix_mapping->{$suffix}->{'curation_status'} eq 'ATP:0000239') {
								$store_status++;
							} else {

								# when curation status is 'curated' do additional QA/QC where possible to check that database does have curated data of the relevant type
								# DESCRIPTION, Script logic: 3b.
								if (defined $has_curated_data) {
									if (exists $has_curated_data->{$pub_id}) {

										$store_status++;

									} else {

										# this represents '::DONE' flags where a curator checked the paper but the flag was incorrect
										# adding a topic with 'no data' is not done here as not relevant to curation status - will be dealt with in ticket_scrum-3147-topic-entity-tag.pl script

										# if there is no curated data but there is a relevant internal note that indicates a curator looked and there was nothing to curate, add here with a status of 'not curatable'

										# loop to deal with phys_int
										if ($ATP eq 'ATP:0000069') {

											if ($note) {
												if ($note =~ m/phys_int not curated; bad flag/ || $note =~ m/phys_int not curated; bad SVM flag/) {

													$curation_status = 'ATP:0000299'; # won't curate
													$curation_tag = 'ATP:0000226'; # no curatable data
													$store_status++;


												} elsif ($note =~ m/already curated by/) {

													$curation_status = 'ATP:0000299'; # won't curate
													$store_status++;

												} else {

													$curation_status = 'ATP:0000299'; # won't curate
													$curation_tag = 'ATP:0000208'; # not curatable
													$store_status++;

												}
											} else {
												$curation_status = 'ATP:0000299'; # won't curate
												$curation_tag = 'ATP:0000226'; # no curatable data

												$note = $note . "'$suffix' flag suffix present in FB, indicating that the publication has been looked at, but there is no curated data of the relevant type in FB, so status set to 'won't curate' with a 'no curatable data' tag.";
												$store_status++;

												#print "WARNING: no data despite curated flag suffix: topic (phys_int loop): $ATP, pub_id: $pub_id, suffix: $suffix, note: $note\n";

											}

										# loop to deal with genom_feat - flag may be on primary paper, while details are in a related pc, so add the curation status as 'done' with a warning note
										} elsif ($ATP eq 'ATP:0000056') {

											$note = $note . "'$suffix' flag suffix present in FB, indicating that the publication has been looked at, but there is no curated data of the relevant type in FB. Despite this, set status to 'curated' as attribution may be to a related personal communication (after author correspondence) instead of the original reference.";
											$store_status++;

										} else {
											$curation_status = 'ATP:0000299'; # won't curate
											$curation_tag = 'ATP:0000226'; # no curatable data

											$note = $note . "'$suffix' flag suffix present in FB, indicating that the publication has been looked at, but there is no curated data of the relevant type in FB, so status set to 'won't curate' with a 'no curatable data' tag.";
											$store_status++;

										}


									}

								} else {

									# in the absence of a check for curated data of the expected type, use presence of curation record with expected filename
									if (defined $currecs_by_timestamp) {

										if (exists $currecs_by_timestamp->{$pub_id}) {
											$note = $note . " 'curated' flag suffix confirmed by presence of currec with expected filename format.";
											$store_status++;
										} else {
											print "WARNING: DONE style flag but no corresponding currec: topic: $ATP, pub_id: $pub_id, suffix: $suffix, note: $note\n";


										}


									}

								}
							}
						}

						$note =~ s/^ //;
						$note =~ s/ $//;

						if ($store_status) {

							$curation_status_data->{$pub_id}->{$ATP}->{'curation_status'} = $curation_status;
							$curation_status_data->{$pub_id}->{$ATP}->{'date_created'} = $timestamp;
							
							if ($note) {
								$curation_status_data->{$pub_id}->{$ATP}->{'note'} = $note;
							}

							if ($curation_tag) {
								$curation_status_data->{$pub_id}->{$ATP}->{'curation_tag'} = $curation_tag;
							}

						}

					} else {

						# this loop adds an undefined 'curation_status' when the suffix is 'Inappropriate use of flag', which prevents any incorrect 'curated' status being added in the 'DESCRIPTION, Script logic: 4' loop below for these cases.
						if ($suffix eq 'Inappropriate use of flag') {
							$curation_status_data->{$pub_id}->{$ATP}->{'curation_status'} = undef;

						}

					}

				} else {

					print "ERROR: unknown suffix type: topic: $ATP, pub_id: $pub_id, suffix: $suffix\n";
				}
			} else {
				print "ERROR: more than one suffix type for single topic: topic: $ATP, pub_id: $pub_id\n";
			}

		}
	}



	#second, assign curation status based on standard record filenames, if not already assigned above (this gets data for papers curated before triage flags were used in FB).
	# DESCRIPTION, Script logic: 4
	if (defined $currecs_by_timestamp) {

		foreach my $pub_id (sort keys %{$currecs_by_timestamp}) {

			unless (exists $curation_status_data->{$pub_id} && exists $curation_status_data->{$pub_id}->{$ATP}) {

				# get the timestamp of the *earliest* matching curation record
				my $timestamp = $currecs_by_timestamp->{$pub_id}[0];

				if (defined $has_curated_data) {


					my $curation_status = '';
					my $note = '';


					if (defined $relevant_internal_notes && exists $relevant_internal_notes->{$pub_id}) {
						$note = $note . (join ' ', sort keys %{$relevant_internal_notes->{$pub_id}});

					}

					my $curation_tag = '';

					my $store_status = 0;

					if (exists $has_curated_data->{$pub_id}) {

						$curation_status = 'ATP:0000239';

						unless ($note) {
							$note = "'curated' status inferred from presence of data plus currec with expected filename format.";

						}
						$store_status++;

					} else {

						# loop to deal with phys_int
						if ($ATP eq 'ATP:0000069') {

							if ($note) {

								if ($note =~ m/phys_int not curated; bad flag/ || $note =~ m/phys_int not curated; bad SVM flag/) {

									$curation_status = 'ATP:0000299'; # won't curate
									$curation_tag = 'ATP:0000226'; # no curatable data
									$store_status++;


								} elsif ($note =~ m/already curated by/) {

									$curation_status = 'ATP:0000299'; # won't curate !! need to check this is OK !!
									$store_status++;

								} else {

									$curation_status = 'ATP:0000299'; # won't curate
									$curation_tag = 'ATP:0000208'; # not curatable
									$store_status++;

								}
							} else {

								print "no data despite standard filename (phys_int loop): topic: $ATP, pub_id: $pub_id, $timestamp\n";

							}


						# loop to deal with pheno - change $store_status switch and curation_status based on text
						} elsif ($ATP eq 'ATP:0000079') {

							if ($note) {

								if ($note =~ m/only pheno_chem data in paper/ || $note =~ m/No phenotypic data in paper/) {

									# this loop is needed to remove an incorrect 'phen_cur: CV annotations only' tag that was added automatically to some records with no phenotypic information
									if ($note =~m/phen_cur: CV annotations only. [a-z]{2}[0-9]{6}./) {
										$note =~ s/phen_cur: CV annotations only. [a-z]{2}[0-9]{6}.//;

									}

									$curation_status = 'ATP:0000299'; # won't curate
									$curation_tag = 'ATP:0000226'; # no curatable data
									$store_status++;


								}
							} else {

								print "no data despite standard filename (pheno loop): topic: $ATP, pub_id: $pub_id, $timestamp\n";

							}


						} else {


							#print "WARNING: no data despite standard filename: topic: $ATP, pub_id: $pub_id, $timestamp\n";

						}
					}

					$note =~ s/^ //;
					$note =~ s/ $//;

					if ($store_status) {

						$curation_status_data->{$pub_id}->{$ATP}->{'curation_status'} = $curation_status;
						$curation_status_data->{$pub_id}->{$ATP}->{'date_created'} = $timestamp;

						if ($note) {
							$curation_status_data->{$pub_id}->{$ATP}->{'note'} = $note;
						}

						if ($curation_tag) {
							$curation_status_data->{$pub_id}->{$ATP}->{'curation_tag'} = $curation_tag;
						}

					}


				}


			}

		}
	}

####
	#for phenotype datatype, additional check for older curation record with older filename format indicating 'full' curation by cam.
	if (defined $cam_full_by_timestamp) {

		foreach my $pub_id (sort keys %{$cam_full_by_timestamp}) {

			unless (exists $curation_status_data->{$pub_id} && exists $curation_status_data->{$pub_id}->{$ATP}) {

				# get the timestamp of the *earliest* matching curation record, so that get first relevant record and not any subsequent 'plain' format filename that represented edits, before we started using .edit format
				my $timestamp = $cam_full_by_timestamp->{$pub_id}[0];

				# add curation status if there is phenotypic data - it is expected that many of this kind of curation record will NOT contain phenotype data,
				# so no need for else loop with warning
				if (defined $has_curated_data) {

					if (exists $has_curated_data->{$pub_id}) {

						my $curation_status = 'ATP:0000239';
						my $note = '';

						if (defined $relevant_internal_notes && exists $relevant_internal_notes->{$pub_id}) {
							$note = $note . (join ' ', sort keys %{$relevant_internal_notes->{$pub_id}});

						}

						unless ($note) {
							$note = "'curated' status inferred from presence of data plus currec with expected filename format.";

						}

						$note =~ s/^ //;
						$note =~ s/ $//;

						$curation_status_data->{$pub_id}->{$ATP}->{'curation_status'} = $curation_status;
						$curation_status_data->{$pub_id}->{$ATP}->{'date_created'} = $timestamp;

						if ($note) {
							$curation_status_data->{$pub_id}->{$ATP}->{'note'} = $note;
						}


					}

				}


			}

		}
	}
####


	print "$ATP\n";
	print Dumper ($curation_status_data);

}
