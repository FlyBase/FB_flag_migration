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

		'phys_int' => ['select distinct p.pub_id from pub p, interaction_pub ip, interaction i where p.is_obsolete = \'f\' and p.pub_id = ip.pub_id and ip.interaction_id = i.interaction_id and i.is_obsolete = \'f\''],
		'cell_line' => ['select distinct p.pub_id from pub p, cell_line_pub cp, cell_line c where p.is_obsolete = \'f\' and p.pub_id = cp.pub_id and cp.cell_line_id = c.cell_line_id'],


		'chemical' => ['select distinct p.pub_id from pub p, feature f, feature_pub fp where p.is_obsolete = \'f\' and p.pub_id = fp.pub_id and f.feature_id = fp.feature_id and f.is_obsolete = \'f\' and f.uniquename ~\'^FBch\''],

		'DO_annotation' => ['select distinct p.pub_id FROM feature f, feature_cvterm fc, cvterm c, pub p, cv where p.is_obsolete = \'f\' and p.pub_id = fc.pub_id and fc.cvterm_id = c.cvterm_id and c.cv_id = cv.cv_id and cv.name = \'disease_ontology\' and c.is_obsolete = \'0\' and fc.feature_id = f.feature_id and f.is_obsolete = \'f\'',
				'select distinct p.pub_id from feature f, featureprop fp, cvterm cvt, featureprop_pub fpp, pub p where f.feature_id = fp.feature_id and fp.type_id = cvt.cvterm_id and cvt.name = \'hdm_comments\' and f.is_obsolete = \'f\' and fpp.featureprop_id = fp.featureprop_id and fpp.pub_id = p.pub_id and p.is_obsolete = \'f\''],

# two different queries are needed to get publications with expression data
# the first gets publications with curated controlled expression (TAP) statements
# the second gets publications where a polypeptide/transcript/ reporter was used as a marker for an anatomical structure
		'expression_annotation' => ['select distinct p.pub_id from feature f, feature_expression fe, expression e, pub p where p.is_obsolete = \'f\' and p.pub_id = fe.pub_id and fe.expression_id = e.expression_id and f.feature_id = fe.feature_id and f.is_obsolete = \'f\'',
		'select distinct p.pub_id, f.name FROM feature f, feature_cvterm fc, feature_cvtermprop fcp, cvterm cvt, pub p where p.is_obsolete = \'f\' and p.pub_id = fc.pub_id and fc.feature_cvterm_id = fcp.feature_cvterm_id and fcp.type_id = cvt.cvterm_id and cvt.name = \'bodypart_expression_marker\' and fc.feature_id = f.feature_id and f.is_obsolete = \'f\''


],

# two different queries are needed to get publications with genom_feat data
# the first gets publications which contain features representing variations that are mapped to the genome - the cvterms used in this query are based on those in the 'variation' feature_subtypes information in alliance-linkml-flybase code, with the addition of 'rescue_region'.
# the second gets publications where there is sequence location information for transgenic insertions
# the third gets publications where there is sequence location information for aberration breakpoints
		'genom_feat' => ['select distinct p.pub_id from pub p, feature f, feature_pub fp, cvterm cvt where p.is_obsolete = \'f\' and p.pub_id = fp.pub_id and f.feature_id = fp.feature_id and f.is_obsolete = \'f\' and f.type_id = cvt.cvterm_id and cvt.name in (\'MNV\', \'complex_substitution\', \'deletion\', \'delins\', \'insertion\', \'point_mutation\', \'sequence_alteration\', \'sequence_variant\', \'rescue_region\') and cvt.is_obsolete = \'0\'',

				'select distinct p.pub_id from feature f, pub p, featureloc_pub flp, featureloc fl where p.pub_id = flp.pub_id and flp.featureloc_id = fl.featureloc_id and fl.feature_id = f.feature_id and f.is_obsolete = \'f\' and p.is_obsolete = \'f\' and f.uniquename ~\'^FBti\'',

				'select distinct p.pub_id from feature f, pub p, featureloc_pub flp, featureloc fl where p.pub_id = flp.pub_id and flp.featureloc_id = fl.featureloc_id and fl.feature_id = f.feature_id and f.is_obsolete = \'f\' and p.is_obsolete = \'f\' and f.uniquename ~\':bk\''


],


# queries needed to get phenotypic data - includes phenstatement (controlled phenotype lines), phenotype_comparison (genetic interactions, complementation, rescue data), phendesc (free text related to phenstatement, phenotype_comparison)
		'phenotype' => ['select distinct p.pub_id from phenstatement ps, pub p, genotype g where p.is_obsolete = \'f\' and p.pub_id = ps.pub_id and ps.genotype_id = g.genotype_id and g.is_obsolete = \'f\'',
				'select distinct p.pub_id from phenotype_comparison pc, pub p, genotype g1, genotype g2 where p.is_obsolete = \'f\' and p.pub_id = pc.pub_id and pc.genotype1_id = g1.genotype_id and g1.is_obsolete = \'f\' and pc.genotype2_id = g2.genotype_id and g2.is_obsolete = \'f\'',

				'select distinct p.pub_id from phendesc pd, pub p, genotype g where p.is_obsolete = \'f\' and p.pub_id = pd.pub_id and pd.genotype_id = g.genotype_id and g.is_obsolete = \'f\''

],

	};


	unless (exists $mapping->{$data_type}) {

		die "Unknown data type: $data_type passed to pub_has_data_check subroutine: add the appropriate sql query to the \$mapping hash and run the script again.";
	}

	my $data = {};

	foreach my $query_text (@{$mapping->{$data_type}}) {
		my $sql_query = sprintf("$query_text");
		my $db_query = $dbh->prepare($sql_query);
		$db_query->execute or die "WARNING: ERROR: Unable to execute pub_has_curated_data query ($!)\n";

		while (my ($pub_id) = $db_query->fetchrow_array) {


			$data->{$pub_id} = undef;
		}
	}
	return $data;


}


