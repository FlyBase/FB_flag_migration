package Util;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(make_abc_json_metadata get_yyyymmdd_date_stamp);

use JSON::PP;

=head1 MODULE: AuditTable

Module containing utility subroutines.

=cut

1;


sub make_abc_json_metadata {


=head1 SUBROUTINE:
=cut

=head1

	Title:    make_abc_json_metadata
	Usage:    make_abc_json_metadata(destination_database);
	Function: The make_abc_json_metadata subroutine makes a reference containing standard information for a "metaData" json object for a json file containing data to be submitted to the ABC.
	Example: my $json_metadata = &make_abc_json_metadata('production');
        Args    : destination DB that the json is intended for (must be either 'stage' or 'production'.


=cut

	unless (@_ == 1) {

		die "Wrong number of parameters passed to the make_abc_json_metadata subroutine\n";
	}

	my ($destination) = @_;
	unless ($destination eq 'production' | $destination eq 'stage') {
		die "unrecognized value ($destination) passed to make_abc_json_metadata subroutine: argument must be 'production' or 'stage'\n";

	}


	my $date_stamp = &get_yyyymmdd_date_stamp();

	my $metadata = {
		# copied format from agr_schemas/ingest/metaData.json
		'dataProvider' => {

			'mod' => 'FB',
			'type' => 'curated', 
		},

	};

	# copied format from agr_schemas/ingest/metaData.json
	$metadata->{'dateProduced'} = $date_stamp;

	# new element to say whether json should be submitted to stage or production ABC
	$metadata->{'destinationDB'} = $destination;


	return ($metadata);

}


sub get_yyyymmdd_date_stamp {


=head1 SUBROUTINE:
=cut

=head1

        Title   : get_yyyymmdd_date_stamp
        Usage   : get_yyyymmdd_date_stamp()
        Function: Produces a date stamp in yyyymmdd format that can be used to
                  append to file/folder names etc.
        Example : my $date_stamp = &get_yyyymmdd_date_stamp();
        Returns : date_stamp
        Args    : none


=cut


	my @time = localtime;

	my ($day, $month, $year) = ($time[3], $time[4], $time[5]);

	$year = $year + 1900;

	$month = $month +1;

	if ($month < 10) {
		$month =~ s|^|0|;
	}

	if ($day < 10) {
		$day =~ s|^|0|;
	}


	my $date_stamp = "$year" . "$month" . "$day";

	return $date_stamp;

}

