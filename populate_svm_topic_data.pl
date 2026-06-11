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
use ABCInfo;
use Mappings;
use Util;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use Encode;
binmode(STDOUT, ":utf8");


use constant FALSE => \0;
use constant TRUE => \1;

=head1 NAME populate_svm_topic_data.pl

=head1 SYNOPSIS

Used to load FlyBase SVM pipeline triage flag information into the Alliance ABC literature database as topic data. Generates an output file containing a single json structure for all the data (topic data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source and intended destination database).

=cut

=head1 USAGE

USAGE: perl populate_svm_topic_data.pl folder_path dev|test|production XXXX


=cut


if (@ARGV != 3) {
    warn "Wrong number of arguments, should be 3!\n";
    warn "\n USAGE: $0 folder_path dev|test|production access_token\n\n";
    exit;
}

my $folder_path = shift(@ARGV);
my $ENV_STATE = shift(@ARGV);
my $access_token = shift(@ARGV);

unless ($ENV_STATE eq 'dev'|| $ENV_STATE eq 'test'|| $ENV_STATE eq 'production') {

	warn "Unknown state '$ENV_STATE': must be 'dev', 'test' or 'production'\n\n";
	exit;

}



if ($ENV_STATE eq "test") {
	print STDERR "You are about to write data to stage Alliance literature server\n";
	print STDERR "Type y to continue else anything else to stop:\n";
	my $continue = <STDIN>;
	chomp $continue;
	if (($continue eq 'y') || ($continue eq 'Y')) {
		print STDERR "Processing will continue.";
	} else{
		die "Processing has been cancelled.";
	}
}

my $test_FBrf = '';


if ($ENV_STATE eq "test") {

	print STDERR "FBrf to test:";
	$test_FBrf = <STDIN>;
	chomp $test_FBrf;

	if ($ENV_STATE eq "test") {

		unless ($test_FBrf =~ m/^FBrf[0-9]{7}$/) {

			die "Only a single FBrf is allowed in test mode."

		}
	}

}


# variable that specifies the appropriate path (downstream of the base URL) to use for the Alliance Literature Service API.
# Used to add an element in the metaData object of the output json file and in the curl command used when in test mode.
my $api_endpoint = 'topic_entity_tag';

my $json_encoder = JSON::PP->new()->pretty(1)->canonical(1);

my $confidence_mapping = {

	'high' => 'HIGH',
	'medium' => 'MEDIUM',
	'low' => 'LOW',
	'neg' => 'NEG',



};


my $month_mapping = {


	'Jan' => '01',
	'Feb' => '02',
	'Mar' => '03',
	'Apr' => '04',
	'May' => '05',
	'Jun' => '06',
	'Jul' => '07',
	'Aug' => '08',
	'Sep' => '09',
	'Oct' => '10',
	'Nov' => '11',
	'Dec' => '12',



};


my $MONTHS = join '|', sort keys %{$month_mapping};

# get source information for SVM from ABC
my $svm_source_data = {};

if ($ENV_STATE eq "dev" || $ENV_STATE eq "test") {

	$svm_source_data = &get_topic_entity_tag_source_data('stage', 'svm', $access_token);

} else {

	$svm_source_data = &get_topic_entity_tag_source_data($ENV_STATE, 'svm', $access_token);

}

#print Dumper ($svm_source_data);


# data structures for how/whether to map FB triage flags to corresponding ABC topic info
my $flag_mapping = &get_flag_mapping();
my $flags_to_ignore = &get_flags_to_ignore();



unless (-e $folder_path) {

	die "Exiting script: specified folder ($folder_path) does not exist.\n";

}

unless (-r $folder_path) {
	die "Exiting script: Cannot read specified folder ($folder_path)\n";
}

unless (-d $folder_path) {
	die "Exiting script: specified folder ($folder_path) is not a directory\n";
}

chdir $folder_path
	or die "Exiting script: cannot change directory to specified folder ($folder_path) ($!)\n";


my @textmining_files = glob "*_SVM.txt";





my $svm_data = {};

foreach my $textmining_file (@textmining_files) {

	open my $input_file, '<', "$textmining_file"
		or die "Can\'t open $textmining_file ($!)\n";

	my $timestamp = '';

	while (<$input_file>) {

		if (m|^\#|) {


			if (m/carried out on ([0-9]{1,2}) ($MONTHS) ([0-9]{4})/i) {

				my $day = $1;
				my $month = $2;

				$month = "$month_mapping->{$month}";
				my $year = $3;
				$timestamp = "$year-$month-$day";

			}

		} elsif (m|^.*?\t(FBrf[0-9]{7})\t([0-9]{1,})?\t(.+?):(.+?)\t(.+?)\t?$|) {

			if ($timestamp eq '') {
				warn "$textmining_file: no timestamp set: $_";

			}

			my $FBrf = $1;
			my $flag = $3;
			my $confidence = $4;
			my $flag_type = $5;
			$flag_type = $flag_type . '_flag';

			unless (exists $flags_to_ignore->{$flag_type} && exists $flags_to_ignore->{$flag_type}->{$flag}) {

				if (exists $flag_mapping->{$flag_type} && exists $flag_mapping->{$flag_type}->{$flag}) {


					if (exists $confidence_mapping->{$confidence}) {


						unless ($test_FBrf) {


							$svm_data->{$FBrf}->{$flag_type}->{$flag}->{count}++;
							$svm_data->{$FBrf}->{$flag_type}->{$flag}->{confidence} = $confidence_mapping->{$confidence};
							$svm_data->{$FBrf}->{$flag_type}->{$flag}->{timestamp} = $timestamp;


						} else {


							if ($FBrf =~ m/$test_FBrf/) {

								$svm_data->{$FBrf}->{$flag_type}->{$flag}->{count}++;
								$svm_data->{$FBrf}->{$flag_type}->{$flag}->{confidence} = $confidence_mapping->{$confidence};
								$svm_data->{$FBrf}->{$flag_type}->{$flag}->{timestamp} = $timestamp;

							}

						}

					} else {
						warn "ERROR: no mapping in the confidence_mapping hash for the '$confidence' confidence level: $_\n";


					}

				} else {

					#print $data_error_file "ERROR: no mapping in the flag_mapping hash for this flag_type:$flag from $flag_type, line: $_\n";
					warn "ERROR: no mapping in the flag_mapping hash for this flag_type:$flag from $flag_type, line: $_\n";
				}

			}

		} else {

			warn "Non-matching line ($textmining_file): $_";

		}


	}

	close $input_file;
}

#print Dumper ($svm_data);

my $complete_data = {};


foreach my $FBrf (sort keys %{$svm_data}) {
	foreach my $flag_type (sort keys %{$svm_data->{$FBrf}}) {
		foreach my $flag (sort keys %{$svm_data->{$FBrf}->{$flag_type}}) {

			# only use flag+FBrf combinations with a single row in original files (to avoid any data conflicts)
			if ($svm_data->{$FBrf}->{$flag_type}->{$flag}->{count} == 1) {


				# do not submit negative results for pipelines that are looking for 'new' data of a particular type (new_al, new_transg)
				# this is to match current policy for equivalent ABC pipelines. do the test here rather than in first pass that reads FB files
				# so that any cases with data conflicts can still be excluded
				unless (exists $flag_mapping->{$flag_type}->{$flag}->{data_novelty} && $svm_data->{$FBrf}->{$flag_type}->{$flag}->{confidence} eq 'NEG') {



					# first store variables in a $data_element hash so it is easy to convert to correct json format later (and to add/change json structure if Alliance model changes)
					my $data_element = {};
					my $FBrf_with_prefix="FB:$FBrf";
					$data_element->{reference_curie} = $FBrf_with_prefix;

					if ($svm_data->{$FBrf}->{$flag_type}->{$flag}->{timestamp}) {

						$data_element->{date_created} = $svm_data->{$FBrf}->{$flag_type}->{$flag}->{timestamp};
						$data_element->{date_updated} = $svm_data->{$FBrf}->{$flag_type}->{$flag}->{timestamp};

					}

					# set other parameters for the flag based on $flag_mapping hash or set the relevant default if the key does not exist in the mapping hash for that flag
					my $ATP = "$flag_mapping->{$flag_type}->{$flag}->{ATP_topic}";
					$data_element->{topic} = $ATP;
					$data_element->{species} = exists $flag_mapping->{$flag_type}->{$flag}->{species} ? $flag_mapping->{$flag_type}->{$flag}->{species} : 'NCBITaxon:7227';

					if ($svm_data->{$FBrf}->{$flag_type}->{$flag}->{confidence} eq 'NEG') {

						$data_element->{negated} = TRUE;

					} else {

						$data_element->{negated} = FALSE;
					}


					$data_element->{data_novelty} = exists $flag_mapping->{$flag_type}->{$flag}->{data_novelty} ? $flag_mapping->{$flag_type}->{$flag}->{data_novelty} : 'ATP:0000335'; # if the mapping hash has no specific data novelty term set, the parent term (ATP:0000335 = 'data novelty') must be added for ABC validation purposes

					$data_element->{topic_entity_tag_source_id} = $svm_source_data->{topic_entity_tag_source_id};


					$data_element->{confidence_level} = $svm_data->{$FBrf}->{$flag_type}->{$flag}->{confidence};


					unless ($ENV_STATE eq "test") {
						push @{$complete_data->{data}}, $data_element;

					} else {

						my $json_data = $json_encoder->encode($data_element);

						my $cmd="curl -X 'POST' 'https://stage-literature-rest.alliancegenome.org/$api_endpoint/'  -H 'accept: application/json'  -H 'Authorization: Bearer $access_token' -H 'Content-Type: application/json'  -d '$json_data'";
						my $raw_result = `$cmd`;
						my $result = $json_encoder->decode($raw_result);


					
						unless (exists $result->{'detail'}) {

							print "json post success\nJSON:\n$json_data\n\n";

						} else {

							print "json post failed\nJSON:\n$json_data\nREASON:\n$raw_result\n#################################\n\n";

						}
					}
				}

			}

		}
	}
}


unless ($ENV_STATE eq "test") {

	my $json_metadata = &make_abc_json_metadata('FB curation_data/text_mining_flags SVM files', $api_endpoint);
	$complete_data->{"metaData"} = $json_metadata;
	my $complete_json_data = $json_encoder->encode($complete_data);

	print $complete_json_data;


}




