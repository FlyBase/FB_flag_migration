package ABCInfo;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(get_topic_entity_tag_source_data);

use JSON::PP;

=head1 MODULE: AuditTable

Module containing subroutines that get information from the ABC.

=cut

1;


sub get_topic_entity_tag_source_data {

=head1 SUBROUTINE:
=cut

=head1

	Title:    get_topic_entity_tag_source_data
	Usage:    get_topic_entity_tag_source_data(API_type, curator_type);
	Function: The get_topic_entity_tag_source_data subroutine gets json that describes the topic_entity_tag_source information, using a curl command to query the relevant Alliance REST API service
	Example: my $source_data = &get_topic_entity_tag_source_data('production', 'curator');

	
Arguments:

o API_type: the 'type' of the relevant Alliance REST API service to query - must be either 'production' or 'stage'

o curator_type: the type of curation that you want the json details for - must be either 'curator' or 'author'

o Returns the appropriate source information as a reference


=cut


	unless (@_ == 2) {

		die "Wrong number of parameters passed to the get_topic_entity_tag_source_data subroutine\n";
	}

	my ($API_type, $curator_type) = @_;

	unless ($API_type eq 'production' | $API_type eq 'stage') {

		die "unrecognized value ($API_type) passed to get_topic_entity_tag_source_data surboutine as API_type: must be 'production' or 'stage'\n";


	}


	my $curator_type_mapping = {

# For manual curation, use: ATP:0000036 = 'documented statement evidence used in manual assertion by professional biocurator'

		'curator' => {

			'evidence' => '0000036',
			'source_method' => 'FlyBase_curation',

		},
# For community curation, use: ATP:0000035 = 'documented statement evidence used in manual assertion by author'

		'author' => {

			'evidence' => '0000035',
			'source_method' => 'author_first_pass',

		},

	};

	unless (exists $curator_type_mapping->{$curator_type}) {

		die "unrecognized value ($curator_type) passed to get_topic_entity_tag_source_data subroutine as curator_type: must be 'curator' or 'author'\n";


	}

	my $cmd = '';

	if ($API_type eq 'stage') {

		$cmd = "curl -X 'GET' 'https://stage-literature-rest.alliancegenome.org/topic_entity_tag/source/ATP%3A$curator_type_mapping->{$curator_type}->{evidence}/$curator_type_mapping->{$curator_type}->{source_method}/FB/FB' -H 'accept: application/json'";

	} else {

		$cmd = "curl -X 'GET' 'https://literature-rest.alliancegenome.org/topic_entity_tag/source/ATP%3A$curator_type_mapping->{$curator_type}->{evidence}/$curator_type_mapping->{$curator_type}->{source_method}/FB/FB' -H 'accept: application/json'";

	}

# fetch the data and convert the json to a reference
	my $raw_json =`$cmd`;

	my $json_encoder = JSON::PP->new()->canonical(1);
	my $result = $json_encoder->decode($raw_json);


	return ($result);

}