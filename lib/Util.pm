package Util;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(make_abc_json_metadata get_yyyymmdd_date_stamp pub_has_curated_data);

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
	Usage:    make_abc_json_metadata(source database);
	Function: The make_abc_json_metadata subroutine makes a reference containing standard information for a "metaData" json object for a json file containing data to be submitted to the ABC.
	Example: my $json_metadata = &make_abc_json_metadata('production');
        Args    : source database - the name of the FlyBase chado database used to make the file.


=cut

	unless (@_ == 1) {

		die "Wrong number of parameters passed to the make_abc_json_metadata subroutine\n";
	}

	my ($source) = @_;

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
	$metadata->{'release'} = $source;


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





sub pub_has_curated_data {


=head1 SUBROUTINE:
=cut

=head1

        Title   : pub_has_curated_data
        Usage   : pub_has_curated_data($database_handle,$data_type)
        Function: Produces a list of current publications which contain curated data of the type specified in the second argument.
        Returns : Hash reference of matching publications: key is pub_id, value is 'undef' (to allow expansion of hash reference later in main script).
        Example : my $has_phys_int_data = &pub_has_curated_data($dbh, 'phys_int');

Arguments:

o $data_type is the type of curated data. The value must be present as a key in the $mapping hash of this subroutine; the corresponding value of the hash key is the appropriate sql query for the data_type. The $data_type string for a given type of data is typically the corresponding triage flag used to flag publications containing the type of data.



=cut


	unless (@_ == 2) {

		die "Wrong number of parameters passed to the pub_has_curated_data subroutine.\n";
	}


	my $dbh = shift; # this is the database handle
	my $data_type = shift; # this is the type of curated data


	# in each case, the sql query requires both the publication AND the curated data to be current.
	my $mapping = {

		'phys_int' => 'select distinct p.pub_id from pub p, interaction_pub ip, interaction i where p.is_obsolete = \'f\' and p.pub_id = ip.pub_id and ip.interaction_id = i.interaction_id and i.is_obsolete = \'f\'',
		'cell_line' => 'select distinct p.pub_id from pub p, cell_line_pub cp, cell_line c where p.is_obsolete = \'f\' and p.pub_id = cp.pub_id and cp.cell_line_id = c.cell_line_id',


	};


	unless (exists $mapping->{$data_type}) {

		die "Unknown data type: $data_type passed to pub_has_data_check subroutine: add the appropriate sql query to the \$mapping hash and run the script again.";
	}

	my $data = {};

	my $sql_query = sprintf("$mapping->{$data_type}");
	my $db_query = $dbh->prepare($sql_query);
	$db_query->execute or die "WARNING: ERROR: Unable to execute pub_has_curated_data query ($!)\n";

	while (my ($pub_id) = $db_query->fetchrow_array) {


		$data->{$pub_id} = undef;
	}

	return $data;


}


