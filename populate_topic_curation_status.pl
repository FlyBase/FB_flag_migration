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
# Making the mapping this way around (rather than just using the original &get_flag_mapping info), because
# multiple triage flags in FlyBase can map to a single ATP term and this way around makes processing easier.
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
#		'use_filename' => 'phys_int',

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


# 2. go through each topic in the $curation_status_topics hash and determine curation status

foreach my $ATP (sort keys %{$curation_status_topics}) {


	# get relevant info for the topic
	# get references with triage flag(s) with suffixes for the flag(s) that correspond to the ATP topic
	my $flags_with_suffix = &get_timestamps_for_flaglist_with_suffix($dbh,$curation_status_topics->{$ATP}->{'flag_type'},$curation_status_topics->{$ATP}->{'flags'});
#	print Dumper ($flags_with_suffix);

	# if appropriate, get references that have curated data corresponding to the ATP topic (identified from direct db query of count of the datatype)
	my $has_curated_data = undef;
	if (exists $curation_status_topics->{$ATP}->{'get_curated_data'}) {
		$has_curated_data = &pub_has_curated_data($dbh,$curation_status_topics->{$ATP}->{'get_curated_data'});
	}

	# if appropriate, get references that are *expected* to contain curated data corresponding to the ATP topic, based on curation record filename.
	my $curator_by_timestamp = undef;
	if (exists $curation_status_topics->{$ATP}->{'use_filename'}) {
		($curator_by_timestamp, undef) = &get_relevant_currec_for_datatype($dbh,$curation_status_topics->{$ATP}->{'use_filename'});
	}

	if (defined $has_curated_data) {

#		print "BEFORE\n";
#		print Dumper ($has_curated_data);

		#go through the list of pubs with curated data and check whether there is a flag with a suffix that can be used to map curation status
		foreach my $pub_id (sort keys %{$has_curated_data}) {
			if (exists $flags_with_suffix->{$pub_id}) {

				if (scalar keys %{$flags_with_suffix->{$pub_id}} == 1) {

					my $suffix = join '', keys %{$flags_with_suffix->{$pub_id}};

					# check whether there is a flag with a suffix
					if (exists $flag_suffix_mapping->{$suffix}) {

						# only consider suffixes that are relevant to curation status of this ATP topic
						if (defined $flag_suffix_mapping->{$suffix}) {
							# get the latest timestamp for the flag
							my $flag_timestamp = $flags_with_suffix->{$pub_id}->{$suffix}->{'timestamp'}[-1];
							$has_curated_data->{$pub_id}->{$suffix} = $flag_timestamp;


						}
					} else {

						print "ERROR: unknown suffix type: topic: $ATP, pub_id: $pub_id, suffix: $suffix\n";
					}
				}
			}

		}
		print "AFTER $ATP\n";
		print Dumper ($has_curated_data);

	} else {

		warn "Use flag suffix only: $ATP\n"; # temporary warning till this part of code is filled out.

	}


}
