package Util;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(make_abc_json_metadata get_yyyymmdd_date_stamp pub_has_curated_data get_relevant_curator_from_candidate_list get_relevant_curator_from_candidate_list_using_pub_and_timestamp check_and_validate_nocur clean_note convert_curator_names_for_single_element convert_curator_names_bulk);

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
	Example: my $json_metadata = &make_abc_json_metadata('production', 'curation_status');
	Example: my $json_metadata = &make_abc_json_metadata($db, $api_endpoint);
        Args    : source database - the name of the FlyBase chado database used to make the file.

Arguments:

o $source - the name of the FlyBase chado database used to make the file.

o $api_endpoint - the appropriate path (downstream of the base URL) to use for the Alliance Literature Service API when loading the json data into the ABC.

=cut

	unless (@_ == 2) {

		die "Wrong number of parameters passed to the make_abc_json_metadata subroutine\n";
	}

	my ($source, $api_endpoint) = @_;

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
	$metadata->{'endpoint'} = $api_endpoint;


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
		'humanhealth' => ['select distinct p.pub_id from pub p, humanhealth hh, humanhealth_pub hhp where p.is_obsolete = \'f\' and p.pub_id = hhp.pub_id and hh.humanhealth_id = hhp.humanhealth_id and hh.is_obsolete = \'f\''],


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

# the list of FBid types used in the query is deliberately strict, so that only publications that are about a gene or that use fly lines count as 'has genetic data' to make sure that the manual indexing status and cross-checks with nocur work correctly
		'genetic_data' => ['select distinct p.pub_id from pub p, feature f, feature_pub fp where p.is_obsolete = \'f\' and p.pub_id = fp.pub_id and f.feature_id = fp.feature_id and f.is_obsolete = \'f\' and f.uniquename ~\'^FB(gn|al|ab|ba|ti|te)\'',
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

sub get_relevant_curator_from_candidate_list {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_relevant_curator_from_candidate_list
	Usage:    get_relevant_curator_from_candidate_list(candidate_list,pub_id);
	Function: Gets relevant curator details for a pub_id specified in the second argument, from the candidate_list provided in the first argument.
	Example:  my $curator_details = &get_relevant_curator_from_candidate_list($fb_data->{"$relevant_record_type"}, $pub_id);

Arguments:

candidate_list contains timestamp, curator name and curation record information for curation records of a particular type, keyed on pub_ids.

candidate_list needs to be a data structure with the following general format, which can be generated by using the get_relevant_currec_for_datatype subroutine (this returns two references that can first be put into the candidate_list->{"by_timestamp"} and candidate_list->{"by_curator"} halves of the data structure before it is passed to get_relevant_curator_from_candidate_list.

o $candidate_list->{"by_timestamp"}->{pub_id}

    o each pub_id refers to an array of the timestamps associated with the pub_id for the curation records, ordered by date.

o $candidate_list->{"by_curator"}->{pub_id}->{curator}->{timestamp}->{record_number}



pub_id is the pub_id of a single reference.

Returns:


o if the pub_id is NOT a key in $candidate_list->{"by_timestamp"}, returns undef (i.e. there is NO curation of this particular curation type for this pub_id).

o if the pub_id IS a key in $candidate_list->{"by_timestamp"}, returns information for the *earliest* curation record from the candidate list (getting the relevant details from $candidate_list->{"by_curator"}).


   o $curator_details->{curator} = curator name
   o $curator_details->{timestamp} = timestamp
   o $curator_details->{currecs} = curation record filename - useful for debugging

If there is more than one 'relevant' curator for the *earliest* timestamp (i.e. if multiple curation records of the same type of curation were submitted for the same pub_id in the same data load) then:

o curator is set as follows:

   o if any of the relevant curators are FB curators - set to 'FB_curator'

   o otherwise, if any of the relevant curators are community curation - set to 'User Submission'

   o otherwise - set to 'ERROR:unable to reconcile curator' so can easily be identified as an error.

o currecs is set to 'multiple curators for same timestamp'


=cut


	unless (@_ == 2) {

		die "Wrong number of parameters passed to the get_relevant_curator_from_candidate_list subroutine\n";
	}


	my ($data, $pub_id) = @_;

	my $curator_details = undef;



	if (exists $data->{"by_timestamp"}->{$pub_id}) {


		# get the timestamp of the *earliest* matching curation record
		my $timestamp = $data->{"by_timestamp"}->{$pub_id}[0];

		# try to determine the relevant curator if appropriate for the topic
		my $relevant_curator = '';
		my $relevant_records = '';


		if (exists $data->{"by_curator"}->{$pub_id}) {

			if (scalar keys %{$data->{"by_curator"}->{$pub_id}} == 1) {
				my $curator_candidate = join '', keys %{$data->{"by_curator"}->{$pub_id}};

				if (exists $data->{"by_curator"}->{$pub_id}->{$curator_candidate}->{$timestamp}) {
					$relevant_curator = $curator_candidate;
					$relevant_records = join ' ', sort keys %{$data->{"by_curator"}->{$pub_id}->{$curator_candidate}->{$timestamp}};

				}
			} else {

				my $count = 0;
				my $curator_count = 0;
				my $community_curation_count = 0;
				foreach my $curator_candidate (sort keys %{$data->{"by_curator"}->{$pub_id}}) {

					foreach my $candidate_timestamp (sort keys %{$data->{"by_curator"}->{$pub_id}->{$curator_candidate}}) {

						if ($candidate_timestamp eq $timestamp) {

							$relevant_curator = $curator_candidate;
							$relevant_records = join ' ', sort keys %{$data->{"by_curator"}->{$pub_id}->{$curator_candidate}->{$candidate_timestamp}};

							unless ($relevant_curator eq 'Author Submission' || $relevant_curator eq 'User Submission' || $relevant_curator eq 'UniProtKB') {

								$curator_count++;
							}

							if ($relevant_curator eq 'Author Submission' || $relevant_curator eq 'User Submission') {

								$community_curation_count++;
							}
							$count++;

						}
					}
				}

				unless ($count == 1) {
					if ($curator_count) {
						$relevant_curator = 'FB_curator';

					} elsif ($community_curation_count) {

						$relevant_curator = 'User Submission';

					} else {

						$relevant_curator = 'ERROR:unable to reconcile curator';
					}
					$relevant_records = 'multiple curators for same timestamp';

				}
			}
		}

		if ($relevant_curator) {

			# convert all unknown style curators to the same 'FB_curator' name that is used for persistent store submissions
			if ($relevant_curator eq 'Unknown' || $relevant_curator eq 'Unknown Curator' || $relevant_curator eq 'Generic Curator' || $relevant_curator eq 'P. Leyland') {

				$relevant_curator = 'FB_curator';

			}


			$curator_details->{curator} = $relevant_curator;
			$curator_details->{timestamp} = $timestamp;
			$curator_details->{currecs} = $relevant_records; # useful for debugging

		}


	}

	return $curator_details;
}



sub get_relevant_curator_from_candidate_list_using_pub_and_timestamp {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_relevant_curator_from_candidate_list_using_pub_and_timestamp
	Usage:    get_relevant_curator_from_candidate_list_using_pub_and_timestamp(candidate_list, pub_id of reference, timestamp);
	Function: Extracts curator and corresponding curation_record_filename information from the candidate_list specified in the first argument, where it matches the specified pub_id (second argument) plus timestamp (third argument) combination.
	Example:  my $nocur_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id, $nocur_timestamp);

Arguments:

o candidate_list needs to be a data structure with the following general format (a data structure with the correct format that contains ALL curator related information can be generated by using the get_all_currec_data subroutine that is in lib/AuditTable.pm).

    o $candidate_list->{pub_id}->{timestamp}->{curator}->{curation_record_filename}


o pub_id is the pub_id of the single reference to be matched.

o timestamp is the timestamp to be matched.

Returns:


o if there is no matching curator information for the pub_id+timestamp combination, returns undef.

o if there is a single matching curator for the pub_id+timestamp combination, returns the following:


   o $curator_details->{curator} = curator name
   o $curator_details->{currecs} = curation record filename(s) - useful for debugging


o If there is *more than one* matching curator for the pub_id+timestamp combination, then instead of a returning an individual curator name, a more generic curator name is returned if possible, using the following logic:

   o if any of the relevant curators are FB curators - $curator_details->{curator} is set to 'FB_curator'

   o otherwise, if any of the relevant curators represent community curation - $curator_details->{curator} is set to 'User Submission' (the more general 'curator' for community curation).

   o otherwise - $curator_details->{curator} is set to 'ERROR:unable to reconcile curator' so can easily be identified as a potential error when debugging.

   o In addition, $curator_details->{currecs} is set to 'multiple curators for same timestamp' to help with debugging.


=cut


	unless (@_ == 3) {

		die "Wrong number of parameters passed to the get_relevant_curator_from_candidate_list_using_pub_and_timestamp subroutine\n";
	}


	my ($data, $pub_id, $timestamp) = @_;

	my $curator_details = undef;

	if (exists $data->{$pub_id} && exists $data->{$pub_id}->{$timestamp}) {

		my $relevant_curator = '';
		my $relevant_records = '';

		# single matching curator
		if (scalar keys %{$data->{$pub_id}->{$timestamp}} == 1) {
			$relevant_curator = join '', keys %{$data->{$pub_id}->{$timestamp}};
			$relevant_records = join ' ', sort keys %{$data->{$pub_id}->{$timestamp}->{$relevant_curator}};

		# multiple matching curators
		} else {

			my $fb_curator_count = 0; # count of number of matching FB curators
			my $community_curation_count = 0; # count of number of matching types of community curation
			foreach my $curator_candidate (sort keys %{$data->{$pub_id}->{$timestamp}}) {

				$relevant_curator = $curator_candidate;
				$relevant_records = join ' ', sort keys %{$data->{$pub_id}->{$timestamp}->{$curator_candidate}};

				unless ($relevant_curator eq 'Author Submission' || $relevant_curator eq 'User Submission' || $relevant_curator eq 'UniProtKB') {

					$fb_curator_count++;
				}

				if ($relevant_curator eq 'Author Submission' || $relevant_curator eq 'User Submission') {

					$community_curation_count++;
				}

			}

			if ($fb_curator_count) {
				$relevant_curator = 'FB_curator';

			} elsif ($community_curation_count) {

				$relevant_curator = 'User Submission';

			} else {

				$relevant_curator = 'ERROR:unable to reconcile curator';
			}
			$relevant_records = 'multiple curators for same timestamp';

		}


		if ($relevant_curator) {


			# convert all unknown style curators to the same 'FB_curator' name that is used for persistent store submissions
			if ($relevant_curator eq 'Unknown' || $relevant_curator eq 'Unknown Curator' || $relevant_curator eq 'Generic Curator' || $relevant_curator eq 'P. Leyland') {

				$relevant_curator = 'FB_curator';

			}


			$curator_details->{curator} = $relevant_curator;
			$curator_details->{currecs} = $relevant_records; # useful for debugging

		}


	}

	return $curator_details;
}


sub check_and_validate_nocur {

=head1 SUBROUTINE:
=cut

=head1

	Title:    check_and_validate_nocur
	Function: Checks whether a publication has been marked as a 'nocur' (contains no genetic data), and validates whether that flagging is consistent with the types of entity attached to the publication in FlyBase. Returns information based on this checking and validation.
	Example:  my ($nocur_status, $nocur_timestamp, $nocur_note) = &check_and_validate_nocur($nocur_flags, $has_genetic_data, $pub_id);

Arguments:

o $nocur_flags - hash reference containing nocur/nocur_abs flag information

o $has_genetic_data - list of all publications that have genetic entities attached to them.

o $pub_id is the pub_id of the single publication to be checked.

Returns:


$nocur_status is a boolean. It is only set to 1 if the publication being checked IS a nocur (has a nocur/nocur_abs flag in FlyBase) AND passed the validation (there are NO genetic entities attached to it).

(i.e. if a publication has a nocur/nocur_abs flag in FlyBase but there ARE genetic entities attached to the publication, $nocur_status = 0).


$nocur_timestamp: timestamp of when the nocur/nocur_abs flag was added (if the flag exists).

$nocur_note: free text note that can be added in the 'note' slot of the relevant ATP workflow_tag item.

   o contains 'Only looked at abstract.' for publications with a nocur_abs flag in FlyBase.


=cut



	unless (@_ == 3) {

		die "Wrong number of parameters passed to the check_and_validate_nocur subroutine\n";
	}

	my ($nocur_flags, $has_genetic_data, $pub_id) = @_;


	my $nocur_status = 0;
	my $nocur_timestamp = '';
	my $note = '';

	if (exists $nocur_flags->{$pub_id}) {

		# if there is curated genetic data then ignore any nocur flag as it must be an error
		unless (exists $has_genetic_data->{$pub_id}) {
			$nocur_status = 1;
		}

		if (exists $nocur_flags->{$pub_id}->{nocur}) {
			$nocur_timestamp = $nocur_flags->{$pub_id}->{nocur}[0];

		} else {

			$nocur_timestamp = $nocur_flags->{$pub_id}->{nocur_abs}[0];

			$note = "Only looked at abstract.";
		}
	}

	return ($nocur_status, $nocur_timestamp, $note);


}




sub clean_note {


=head1 SUBROUTINE:
=cut

=head1

	Title:    clean_note
	Function: Subroutine that 'cleans' text that is being submitted to the Alliance ABC as an internal 'note'.
	Example:  &clean_note($value);

The conversions done are:

- removes any tabs

- converts superscripts/subscripts to curator-friendly form


- uses degreek subroutine to convert any greek symbols in FB 'sgml' format to spelt out greek name.


Does NOT substitute returns (because many of the internal notes being submitted are in multiline format which needs to be preserved).


=cut
	unless (@_ == 1) {

		die "Wrong number of parameters passed to the clean_free_text subroutine\n";
	}
	my ($string) =  @_;

	if ($string =~ m/\t/) {
		$string =~ s/\t/ /g;
	}

	$string =~ s/\<\/down\>/\]\]/g;
	$string =~ s/\<down\>/\[\[/g;
	$string =~ s/\<up\>/\[/g;
	$string =~ s/\<\/up\>/\]/g;

	$string = &degreek($string);

	return $string;

}



sub degreek {


=head1 SUBROUTINE:
=cut

=head1

	Title:    degreek
	Function: Subroutine that converts sgml greek format to spelt out greek name.


=cut


	my $symbol = $_[0];

	my %greek = (
		'&Agr;' => 'Alpha',
		'&Bgr;' => 'Beta',
		'&Ggr;' => 'Gamma',
		'&Dgr;' => 'Delta',
		'&Egr;' => 'Epsilon',
		'&Zgr;' => 'Zeta',
		'&EEgr;' => 'Eta',
		'&THgr;' => 'Theta',
		'&Igr;' => 'Iota',
		'&Kgr;' => 'Kappa',
		'&Lgr;' => 'Lambda',
		'&Mgr;' => 'Mu',
		'&Ngr;' => 'Nu',
		'&Xgr;' => 'Xi',
		'&Ogr;' => 'Omicron',
		'&Pgr;' => 'Pi',
		'&Rgr;' => 'Rho',
		'&Sgr;' => 'Sigma',
		'&Tgr;' => 'Tau',
		'&Ugr;' => 'Upsilon',
		'&PHgr;' => 'Phi',
		'&KHgr;' => 'Chi',
		'&PSgr;' => 'Psi',
		'&OHgr;' => 'Omega',
		'&agr;' => 'alpha',
		'&bgr;' => 'beta',
		'&ggr;' => 'gamma',
		'&dgr;' => 'delta',
		'&egr;' => 'epsilon',
		'&zgr;' => 'zeta',
		'&eegr;' => 'eta',
		'&thgr;' => 'theta',
		'&igr;' => 'iota',
		'&kgr;' => 'kappa',
		'&lgr;' => 'lambda',
		'&mgr;' => 'mu',
		'&ngr;' => 'nu',
		'&xgr;' => 'xi',
		'&ogr;' => 'omicron',
		'&pgr;' => 'pi',
		'&rgr;' => 'rho',
		'&sgr;' => 'sigma',
		'&tgr;' => 'tau',
		'&ugr;' => 'upsilon',
		'&phgr;' => 'phi',
		'&khgr;' => 'chi',
		'&psgr;' => 'psi',
		'&ohgr;' => 'omega',
	);


	$symbol =~ s/(&[a-z]{1,2}gr;)/$greek{$1}?"$greek{$1}":"$1"/egi;

	$symbol =~ s/&cap;/INTERSECTION/g; # conversion needed to make 'plain' symbol for any FBco symbols in note.

	return $symbol;

}

sub convert_curator_names_bulk {


=head1

	Title:    convert_curator_names_bulk
	Function: Takes a hash that contains an array of elements, where each element represent a single data item to be submitted to the ABC, and for each element converts curator names in any created_by or updated_by keys in the element to the corresponding ABC curator name (for the small number of cases where the ABC curator name is not identical to the FB curator name). Designed for use in any mode other than test where all data is gathered in a single hash of array elements before converting to a single json file.
	Example:  my $complete_data = &convert_curator_names_bulk($complete_data);
	Args   :  none

=cut


	my $cur_mapping = {

		'Author Submission' => 'FB Author Submission',
		'User Submission' => 'FB User Submission',
		'Virtual Fly Brain' => 'FB Virtual Fly Brain',

	};

	unless (@_ == 1) {

		die "Wrong number of parameters passed to the convert_curator_names_bulk subroutine\n";
	}


	my ($data) =  @_;

	foreach my $element (@{$data}) {

		my @fields_to_convert = ('created_by', 'updated_by');

		foreach my $field (@fields_to_convert) {

			if (exists $element->{$field}) {

				if (exists $cur_mapping->{"$element->{$field}"}) {

					my $converted_curator = $cur_mapping->{"$element->{$field}"};

					$element->{$field} = "$converted_curator";
				}
			}
		}
	}

	return $data;
}


sub convert_curator_names_for_single_element {


=head1

	Title:    convert_curator_names_for_single_element
	Function: Takes a hash and converts curator names in any created_by or updated_by keys in the hash to the corresponding ABC curator name (for the small number of cases where the ABC curator name is not identical to the FB curator name). Designed for use in test mode when submitting single json elements at a time to ABC.
	Example:  my $data = &convert_curator_names_for_single_element($data);
	Args   :  none

=cut


	my $cur_mapping = {

		'Author Submission' => 'FB Author Submission',
		'User Submission' => 'FB User Submission',
		'Virtual Fly Brain' => 'FB Virtual Fly Brain',

	};

	unless (@_ == 1) {

		die "Wrong number of parameters passed to the convert_curator_names_for_single_element subroutine\n";
	}


	my ($data) =  @_;


	my @fields_to_convert = ('created_by', 'updated_by');

	foreach my $field (@fields_to_convert) {

		if (exists $data->{$field}) {

			if (exists $cur_mapping->{"$data->{$field}"}) {

				my $converted_curator = $cur_mapping->{"$data->{$field}"};

				$data->{$field} = "$converted_curator";
			}
		}
	}

	return $data;
}
