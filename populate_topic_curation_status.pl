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


o $flag_mapping - standard mapping hash obtained from &get_flag_mapping, contains relevant mapping information and metadata for triage flags that we DO want to submit to the Alliance. This hash is structured from the point of view of the FB triage flags, and is used to build the $curation_status_topics hash detailed below.


o $curation_status_topics - mapping hash of topics that we want to submit curation status information for to the Alliance. This hash is structured from the point of view of the relevant ATP topics, to make processing easier. This hash is built using the information in the $flag_mapping hash, and more than one FB triage flag can collapse down to a single ATP topic for curation status tracking.


o $flag_suffix_mapping - mapping of FB triage flag suffixes to:

  o either the appropriate ATP term describing curation status; terms are children of the 'curation' (ATP:0000230) - workflow tag.
  o or 'undef' if the suffix is not relevant to curation status (so that these irrelevant suffixes can be ignored later on in the script).

1. Uses mapping information 



Script logic:

1. Builds the $curation_status_topics hash to build a list of the ATP topics topics for which we want to export curation status information to the Alliance.

2. For each ATP topic in the $curation_status_topics hash:

2a. makes a list ($flags_with_suffix) of all pub_id that have any of the relevant FB triage flags for that ATP topic, where the FB triage flag has a suffix. The list stores the FB suffix(es) along with timestamp information for each pub_id.

2b. If relevant for the topic (when the ATP topic has a 'get_curated_data' key in $curation_status_topics), makes a list ($has_curated_data) of all pub_id that have curated data corresponding to the ATP topic (this allows QA/QC later).

2c. If relevant for the topic (when the ATP topic has a 'use_filename' key in $curation_status_topics), makes a list ($currecs_by_timestamp) of all pub_id that are *expected* to contain curated data corresponding to the ATP topic because they have a curation record with the standard filename format for that topic (this allows QA/QC later, and also allows additional information to be exported to the Alliance for those publications that were curated *before* we started using triage flags in FB).

3. Goes through the $flags_with_suffix list of publications made in 2a. and for those suffixes that we want to map to an ATP curation status, stores the ATP curation status and timestamp information for each pub_id.

3a. As part of this process, for those FB suffixes that we want to map to ATP 'curated' (i.e. the curation has been 'done'), additional QA/QC is done where possible to check that the publication DOES have the relevant kind of curated data before storing the ATP curation status and timestamp information for each pub_id. This is done using either the list made in 2b. of pulications that have the relevant curated data, and/or the list in 2c. of publications that have a curation record with the standard filename format for that topic. This is necessary because for some FB triage flags, the suffix '::DONE' has been used in the past to mean two different things:

o there is data for that triage flag and the relevant curation has been 'done' - the information for this type IS stored as it is this case that we we want to map to ATP 'curated' in the Alliance.

o the FB triage flag was incorrect and that there is therefore nothing to curate for that particular triage flag - the information for this type is NOT stored in this script as it is not relevant to curation status. Note that no error message is printed in this script for this case as it will instead be dealt with in the separate ticket_scrum-3147-topic-entity-tag.pl script that adds topics to the Alliance, where it will be submitted as an incorrect flag [this is not yet implemented].


4. If appropriate for the ATP topic, goes though the $currecs_by_timestamp list made in 2c. of publications that have a curation record with the standard filename format, and for those publications that have not already been taken care of in 3., for those suffixes that we want to map to an ATP curation status, stores the ATP curation status and timestamp information for each pub_id. This is needed to add curation status for publications where the curation topic was done in FB before we started using triage flags. [this is not yet implemented]


5. Converts the stored list ATP curation status and timestamp information for each pub_id into json format for submission to the ABC. [this is not yet implemented]


NOTE: The script uses the above more complicated logic rather than only using the list made in 2b. of publications that that have curated data corresponding to the ATP topic data because the presence of data in the database does not give any indication of how *complete* the curation is for a given topic, but that detail can be mapped from the FB flag suffixes and standard curation record filename information.



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

		'curation_status' => 'ATP:0000236', # 'curation blocked' - not sure this is the right status
		'note' => 'No response to author query.',
	},

# suffixes that do not add information about the curation status of the topic to which the suffix is attached
	'Inappropriate use of flag' => undef, # this suffix is not related to *curation status* of the topic - will instead need to be used (in different script) to prevent adding the relevant topic
	'Needs cam curation' => undef, # this suffix is not related to curation status of the topic it is attached to - will instead need to be used to flag that a paper needs manual indexing

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

		if (exists $flag_mapping->{$flag_type}->{$flag}->{'use_suffix_for_curation_status'}) {

			my $ATP = $flag_mapping->{$flag_type}->{$flag}->{ATP_topic};

			$curation_status_topics->{$ATP}->{'flag_type_list'}->{$flag_type}++;

			push @{$curation_status_topics->{$ATP}->{'flags'}}, $flag;


		}
	}

}

# 1b. check that each ATP term maps to FB triage flags that are in a single flag_type slot (e.g. harv_flag) in chado
foreach my $ATP (sort keys %{$curation_status_topics}) {

	if (exists $curation_status_topics->{$ATP}->{flag_type_list}) {

		if (scalar keys %{$curation_status_topics->{$ATP}->{flag_type_list}} == 1) {

			my $flag_type = join '', keys %{$curation_status_topics->{$ATP}->{flag_type_list}};

			$curation_status_topics->{$ATP}->{'flag_type'} = $flag_type;

		} else {

			warn "the ATP term: $ATP is being used for triage flags in different flag_type slots in chado - cannot process this.\n";

		}
	}
}

#print Dumper ($curation_status_topics);


# add mapping that will be used to get lists of papers containing the curated datatype for that topic, where appropriate
# 'get_curated_data' - queries the database directly for the datatype
# 'use_filename' - gets curation record filenames that are expected to contain the datatype, based on the filename
my $get_curated_data_mapping = {

	'ATP:0000008' => {
		'get_curated_data' => 'cell_line',
		'use_filename' => 'cell_line',

	},
	'ATP:0000069' => {
		'get_curated_data' => 'phys_int',
		'use_filename' => 'phys_int',

	},

	'ATP:0000151' => {
		'get_curated_data' => 'DO_annotation',
		'use_filename' => 'DO',

	},


};

# add the additional information in $get_curated_data_mapping
foreach my $ATP (sort keys %{$get_curated_data_mapping}) {

	if (exists $curation_status_topics->{$ATP}) {

		foreach my $key (keys %{$get_curated_data_mapping->{$ATP}}) {

			my $value = $get_curated_data_mapping->{$ATP}->{$key};

			$curation_status_topics->{$ATP}->{$key} = "$get_curated_data_mapping->{$ATP}->{$key}";
		}
	} else {

		warn "the ATP term: $ATP is in the \$get_curated_data_mapping hash, but not in the \$curation_status_topics hash.\n";

	}

}



# 2. go through each topic in the $curation_status_topics hash, determine and store curation status, using relevant information for that flag (this is specified in the $curation_status_topics hash).


foreach my $ATP (sort keys %{$curation_status_topics}) {

	my $curation_status_data = {};

	# get relevant info for the topic
	# get references with triage flag(s) with suffixes for the flag(s) that correspond to the ATP topic
	my $flags_with_suffix = &get_timestamps_for_flaglist_with_suffix($dbh,$curation_status_topics->{$ATP}->{'flag_type'},$curation_status_topics->{$ATP}->{'flags'});
#	print Dumper ($flags_with_suffix);

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


	# assign curation status based on flag suffixes, double-checking that there is curated data of the relevant type, if that is appropriate for the particular flag
	foreach my $pub_id (sort keys %{$flags_with_suffix}) {

		if (scalar keys %{$flags_with_suffix->{$pub_id}} == 1) {

			my $suffix = join '', keys %{$flags_with_suffix->{$pub_id}};

			if (exists $flag_suffix_mapping->{$suffix}) {

				# only consider suffixes that are relevant to curation status
				if (defined $flag_suffix_mapping->{$suffix}) {

					my $flag_timestamp = $flags_with_suffix->{$pub_id}->{$suffix}->{'timestamp'}[-1];

					# DESCRIPTION, Script logic: 3a
					if (defined $has_curated_data) {
						if (exists $has_curated_data->{$pub_id}) {

							$curation_status_data->{$pub_id}->{$suffix} = $flag_timestamp;
						} else {

							# only add curation status for FB triage flags that map to 'curated' when there is curation of the corresponding datatype in the db
							unless (exists $flag_suffix_mapping->{$suffix}->{'curation_status'} && $flag_suffix_mapping->{$suffix}->{'curation_status'} eq 'ATP:0000239') {

								$curation_status_data->{$pub_id}->{$suffix} = $flag_timestamp;

							} else {
								# this represents '::DONE' flags where a curator checked the paper but the flag was incorrect
								# this is not dealt with here as not relevant to curation status - will be dealt with in ticket_scrum-3147-topic-entity-tag.pl script
								# print "WARNING: no data despite curated flag suffix: topic: $ATP, pub_id: $pub_id, suffix: $suffix\n";

							}
						}

					} else {

						$curation_status_data->{$pub_id}->{$suffix} = $flag_timestamp;

					}
				}
			} else {

				print "ERROR: unknown suffix type: topic: $ATP, pub_id: $pub_id, suffix: $suffix\n";
			}
		} else {
			print "ERROR: more than one suffix type for single topic: topic: $ATP, pub_id: $pub_id\n";
		}

	}
	print "$ATP\n";
	print Dumper ($curation_status_data);

}
