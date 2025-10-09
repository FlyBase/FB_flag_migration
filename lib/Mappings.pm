package Mappings;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(get_flag_mapping get_flags_to_ignore);

use JSON::PP;

=head1 MODULE: Mappings

Module containing mappings needed to convert FB triage flag data to ABC topic/curation status data.

=cut

1;



sub get_flag_mapping {

=head1

	Title:    get_flag_mapping
	Usage:    get_flag_mapping()
	Function: Returns a mapping of FB triage flags to relevant information needed to load into the ABC.
	Example:  my $flag_mapping = &get_flag_mapping();
	Args   :  none

=cut

# not complete yet

# ATP_topic is compulsory for every flag
# other keys are optional
# species only present if it differs from default Dmel (NCBITaxon:7227) for that flag
# data_novelty only present if the FB triage flag indicates 'new' data of some kind
# negated only present if it applies to that flag

	my $flag_mapping = {


		'cam_flag' => {


			'new_al' => {
				'ATP_topic' => 'ATP:0000006',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000229', # new to field
			},

			'new_allele' => {
				'ATP_topic' => 'ATP:0000006',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000229', # new to field
			},

			'new_transg' => {

				'ATP_topic' => 'ATP:0000013',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000229', # new to field
			},


			'gene_group' => {
				'ATP_topic' => 'ATP:0000065',
			},

			'pathway' => {
				'ATP_topic' => 'ATP:0000113',
			},

			'pert_exp' => {
				'ATP_topic' => 'ATP:0000042',
			},

			'pheno' => {

				'ATP_topic' => 'ATP:0000079',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000321', # new data
			},

			'pheno_anat' => {

				'ATP_topic' => 'ATP:0000032',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'curator_only' => '1',
			},

			'pheno_chem' => {

				'ATP_topic' => 'ATP:0000080',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'curator_only' => '1',
			},

			'rename' => {

				'ATP_topic' => 'ATP:0000048',
				'species' => 'NCBITaxon:7214', # Drosophilidae
			},

			'merge' => {

				'ATP_topic' => 'ATP:0000340',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				# not curator only - was in original version of FTYP
			},

			'split' => {

				'ATP_topic' => 'ATP:0000341',
				'species' => 'NCBITaxon:7214', # Drosophilidae
			},

			'new_char' => {

				'ATP_topic' => 'ATP:0000339',
				'species' => 'NCBITaxon:7214', # Drosophilidae
			},

		},


		'dis_flag' => {


			'dm_gen' => {

				'ATP_topic' => 'ATP:0000151',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'curator_only' => '1',
				'use_suffix_for_curation_status' => '1',
			},

			'dm_other' => {

				'ATP_topic' => 'ATP:0000040',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'curator_only' => '1',
			},

			'disease' => {

				'ATP_topic' => 'ATP:0000152',# 'disease model' ATP term - using more specific ATP term for DO curation
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'use_suffix_for_curation_status' => '1',
			},

			'diseaseHP' => {

				'ATP_topic' => 'ATP:0000152',# disease model ATP term - using more specific ATP term for DO curation
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000229', # new to field
				'curator_only' => '1',
				'use_suffix_for_curation_status' => '1',
			},

			'noDOcur' => {

				'ATP_topic' => 'ATP:0000152',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'negated' => '1', # only present if the flag should have the 'no data' boolean set in ATP, note that representation of this is in flux in ATP
				'curator_only' => '1',
			},
		},


		'harv_flag' => {


			'cell_cult' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'use_suffix_for_curation_status' => '1',
			},

			'cell_line' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'use_suffix_for_curation_status' => '1',
			},


			'cell_line(commercial)' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'note' => 'Commercially purchased cell line', # this is what is on FTYP form
				'use_suffix_for_curation_status' => '1',
			},

			'cell_line(stable)' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'note' => 'Stable line generated', # this is what is on FTYP form
				'use_suffix_for_curation_status' => '1',
			},

			'chemical' => {
				'ATP_topic' => 'ATP:0000094',
#				'use_suffix_for_curation_status' => '1',
			},

			'cis_reg' => {
				'ATP_topic' => 'ATP:0000055',
			},

			'dataset' => {
				'ATP_topic' => 'ATP:0000150',
				'species' => 'NCBITaxon:7214', # Drosophilidae
			},

			# may decide not to submit this flag depending on whether FBhh curation will be done in Alliance (so may need deleting here and adding to ignore hash)
			'disease' => {

				'ATP_topic' => 'ATP:0000011',# 'disease' ATP term - using more general ATP term for FBhh curation
				'species' => 'NCBITaxon:7214', # Drosophilidae
			},

			# may decide not to submit this flag depending on whether FBhh curation will be done in Alliance (so may need deleting here and adding to ignore hash)
			'diseaseHP' => {

				'ATP_topic' => 'ATP:0000011',# 'disease' ATP term - using more general ATP term for FBhh curation
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000321', # new data
			},

			'gene_model' => {
				'ATP_topic' => 'ATP:0000054',
			},

			'genom_feat' => {
				'ATP_topic' => 'ATP:0000056',
				'use_suffix_for_curation_status' => '1',
			},

			'genome_feat' => {
				'ATP_topic' => 'ATP:0000056',
				'use_suffix_for_curation_status' => '1',
			},

			'pert_exp' => {
				'ATP_topic' => 'ATP:0000042',
				# not curator only - was in original version of FTYP
			},

			'phys_int' => {
				'ATP_topic' => 'ATP:0000069',
				'use_suffix_for_curation_status' => '1',
			},

			'wt_cell_line' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'use_suffix_for_curation_status' => '1',
			},

			'wt_exp' => {
				'ATP_topic' => 'ATP:0000041',
				'use_suffix_for_curation_status' => '1',
			},

			'neur_exp' => {
				'ATP_topic' => 'ATP:0000338',
				'curator_only' => '1',
				'use_suffix_for_curation_status' => '1',
			},
		},

		'onto_flag' => {

			'novel_anat' => {

				'ATP_topic' => 'ATP:0000031',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000229', # new to field
				'use_suffix_for_curation_status' => '1',

			},

		},
	};


	# sanity check for $flag_mapping hash - to check that every flag has an ATP_topic mapping

	foreach my $type (keys %{$flag_mapping}) {

		foreach my $flag (keys %{$flag_mapping->{$type}}) {

			unless (exists $flag_mapping->{$type}->{$flag}->{ATP_topic}) {

				die "ERROR in flag_mapping hash: ATP_topic missing for $type, $flag: add the correct ATP term and then try again\n";
			}
		}
	}




	return ($flag_mapping);

}




sub get_flags_to_ignore {


=head1

	Title:    get_flags_to_ignore
	Usage:    get_flags_to_ignore()
	Function: Returns a hash reference of FB triage flags that we do not want to submit to the Alliance.
	Example:  my $flags_to_ignore = &get_flags_to_ignore();
	Args   :  none

=cut

	my $flags_to_ignore = {

		'cam_flag' => {

			'no_flag' => '1',
			'nocur_abs' => '1',
			'orthologs' => '1',
			'new_gene' => '1',
			'y' => '1',
			'GO_cur' => '1',
			'GOcur' => '1',
			'noGOcur' => '1',

			'nocur' => '1', # nocur will not be added as a topic, but will instead be added to the curation status information in the workflow editor in the Alliance
		},

		'harv_flag' => {
			'y' => '1',
			'n' => '1',
			'no' => '1',
			'trans_assay' => '1',
			'RNAi' => '1',
			'micr_arr' => '1',
			'gene_model_nonmel' => '1',
			'no_flag' => '1', # need to double-check with harvcur
			'diseaseF' => '1', # need to double-check with harvcur
			'marker' => '1', # need to double-check with harvcur
	
		},

	};


	return ($flags_to_ignore);



}
