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


# map bit after :: when present in flag according to the type of information it adds.
# key is string after '::', value is either 'curation_status' or 'flag_validation_negative'
my $flag_suffix_mapping = {

	'DONE' => 'curation_status',
	'Partially done' => 'curation_status',
	'in progress' => 'curation_status',
	'Author query sent' => 'curation_status',
	'Needs cam curation' => 'curation_status',
	'No response to author query' => 'curation_status',
	'untouched' => 'curation_status',

	'Inappropriate use of flag' => 'flag_validation_negative',



};

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


# add information that will be used to get the list of papers containing curated data for that topic, where appropriate
my $get_curated_data_mapping = {

	'ATP:0000008' => 'cell_line',
	'ATP:0000069' => 'phys_int',


};

#print Dumper ($curation_status_topics);

foreach my $ATP (sort keys %{$get_curated_data_mapping}) {

	if (exists $curation_status_topics->{$ATP}) {

		$curation_status_topics->{$ATP}->{'get_curated_data'} = $get_curated_data_mapping->{$ATP};

	} else {

		warn "the ATP term: $ATP is in the \$get_curated_data_mapping hash, but not in the \$curation_status_topics hash.\n";

	}

}

# 2. go through each topic in the $curation_status_topics hash and determine curation status

foreach my $ATP (keys %{$curation_status_topics}) {



	my $flags_with_suffix = &get_timestamps_for_flaglist_with_suffix($dbh,$curation_status_topics->{$ATP}->{'flag_type'},$curation_status_topics->{$ATP}->{'flags'});
#	print Dumper ($flags_with_suffix);

	if (exists $curation_status_topics->{$ATP}->{'get_curated_data'}) {

		my $has_curated_data = &pub_has_curated_data($dbh,$curation_status_topics->{$ATP}->{'get_curated_data'});

#		print "BEFORE\n";
#		print Dumper ($has_curated_data);

		#go through the list of pubs with data and check whether there is a DONE flag - if so, capture the relevant timestamp

		foreach my $pub_id (sort keys %{$has_curated_data}) {
			if (exists $flags_with_suffix->{$pub_id}) {

				if (scalar keys %{$flags_with_suffix->{$pub_id}} == 1) {

					my $suffix = join '', keys %{$flags_with_suffix->{$pub_id}};

					if ($suffix eq 'DONE') {
						# get the latest timestamp for the flag
						my $timestamp_to_get = $flags_with_suffix->{$pub_id}->{$suffix}->{'timestamp'}[-1];
						$has_curated_data->{$pub_id}->{DONE_flag} = $timestamp_to_get;

					}
				}
			}

		}
#		print "AFTER\n";
#		print Dumper ($has_curated_data);

	} else {

		warn "Use flag suffix only: $ATP\n";

	}


}
