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
				'for_curation_status' => {
					'get_curated_data' => 'phenotype',
					'use_filename' => 'phen',
					'relevant_internal_note' => 'only pheno_chem data in paper|No phenotypic data in paper|phen_cur: CV annotations only',
				},
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
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'DO_annotation',
					'use_filename' => 'DO',
				},

			},

			'dm_other' => {

				'ATP_topic' => 'ATP:0000040',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'curator_only' => '1',
			},

			'disease' => {

				'ATP_topic' => 'ATP:0000152',# 'disease model' ATP term - using more specific ATP term for DO curation
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'for_curation_status' => {
					'suffix' => 'use',
				},

			},

			'diseaseHP' => {

				'ATP_topic' => 'ATP:0000152',# disease model ATP term - using more specific ATP term for DO curation
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000229', # new to field
				'curator_only' => '1',
				'for_curation_status' => {
					'suffix' => 'use',
				},

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
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'cell_line',
					'use_filename' => 'cell_line',
				},

			},

			'cell_line' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'cell_line',
					'use_filename' => 'cell_line',
				},

			},


			'cell_line(commercial)' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'note' => 'Commercially purchased cell line', # this is what is on FTYP form
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'cell_line',
					'use_filename' => 'cell_line',
				},

			},

			'cell_line(stable)' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'note' => 'Stable line generated', # this is what is on FTYP form
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'cell_line',
					'use_filename' => 'cell_line',
				},

			},

			'chemical' => {
				'ATP_topic' => 'ATP:0000094',
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'chemical',
					'use_filename' => 'chemical',
				},

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
				'for_curation_status' => {
					'suffix' => 'only',
				},
			},

			'genom_feat' => {
				'ATP_topic' => 'ATP:0000056',
				'for_curation_status' => {
					'suffix' => 'use',
					'use_filename' => 'args',
					'get_curated_data' => 'genom_feat',
				},

			},

			'genome_feat' => {
				'ATP_topic' => 'ATP:0000056',
				'for_curation_status' => {
					'suffix' => 'use',
					'use_filename' => 'args',
					'get_curated_data' => 'genom_feat',
				},

			},

			'pert_exp' => {
				'ATP_topic' => 'ATP:0000042',
				# not curator only - was in original version of FTYP

			},

			'phys_int' => {
				'ATP_topic' => 'ATP:0000069',
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'phys_int',
					'use_filename' => 'phys_int',
					'relevant_internal_note' => 'phys_int not curated',
				},

			},

			'wt_cell_line' => {
				'ATP_topic' => 'ATP:0000008',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'cell_line',
					'use_filename' => 'cell_line',
				},

			},

			'wt_exp' => {
				'ATP_topic' => 'ATP:0000041',
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'expression_annotation',
					'use_filename' => 'wt_exp',
				},

			},

			'neur_exp' => {
				'ATP_topic' => 'ATP:0000338',
				'curator_only' => '1',
				'for_curation_status' => {
					'suffix' => 'use',
					'get_curated_data' => 'expression_annotation',
					'use_filename' => 'neur_exp',
				},

			},
		},

		'onto_flag' => {

			'novel_anat' => {

				'ATP_topic' => 'ATP:0000031',
				'species' => 'NCBITaxon:7214', # Drosophilidae
				'data_novelty' => 'ATP:0000229', # new to field

				'for_curation_status' => {
					'suffix' => 'only',
				},
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
			'marker' => '1',
	
		},

	};


	return ($flags_to_ignore);



}
