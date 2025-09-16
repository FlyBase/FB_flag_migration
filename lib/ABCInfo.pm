package ABCInfo;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(get_topic_entity_tag_source_data get_AGRKB_for_FBrf);

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
	Function: The get_topic_entity_tag_source_data subroutine gets json that describes the topic_entity_tag_source information, using a curl command to query the relevant Alliance REST API service, and returns that information as a reference.
	Example: my $source_data = &get_topic_entity_tag_source_data('production', 'curator');

	
Arguments:

o API_type: the 'type' of the relevant Alliance REST API service to query - must be either 'production' or 'stage'

o curator_type: the type of curation that you want the json details for - must be either 'curator' or 'author'


=cut


	unless (@_ == 2) {

		die "Wrong number of parameters passed to the get_topic_entity_tag_source_data subroutine\n";
	}

	my ($API_type, $curator_type) = @_;

	unless ($API_type eq 'production' | $API_type eq 'stage') {

		die "unrecognized value ($API_type) passed to get_topic_entity_tag_source_data subroutine as API_type: must be 'production' or 'stage'\n";


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


sub get_AGRKB_for_FBrf {



=head1 SUBROUTINE:
=cut

=head1

	Title:    get_AGRKB_for_FBrf
	Usage:    get_AGRKB_for_FBrf(API_type, FBrf);
	Function: The get_AGRKB_for_FBrf subroutine gets the corresponding AGRKB number for the FBrf number supplied as the second argument, by using a curl command to query the relevant Alliance REST API service.
	Example: my $AGRKB_data = &get_AGRKB_for_FBrf('production', 'FBrf0111489');


Arguments:

o API_type: the 'type' of the relevant Alliance REST API service to query - must be either 'production' or 'stage'

o FBrf: the FBrf number for which the AGRKB number is needed.


Returns:

o Corresponding AGRKB number.

=cut

	unless (@_ == 2) {

		die "Wrong number of parameters passed to the get_AGRKB_for_FBrf subroutine\n";
	}

	my ($API_type, $FBrf) = @_;

	unless ($API_type eq 'production' | $API_type eq 'stage') {

		die "unrecognized value ($API_type) passed to get_AGRKB_for_FBrf surboutine as API_type: must be 'production' or 'stage'\n";


	}

	unless ($FBrf =~ m/^FBrf[0-9]{7}$/) {
		die "FBrf number passed to get_AGRKB_for_FBrf subroutine ($FBrf) is not correct format\n";

	}

	my $cmd = '';

	if ($API_type eq 'stage') {

		$cmd = "curl -X 'GET' 'https://stage-literature-rest.alliancegenome.org/cross_reference/FB%3A$FBrf' -H 'accept: application/json'";

	} else {

		$cmd = "curl -X 'GET' 'https://literature-rest.alliancegenome.org/cross_reference/FB%3A$FBrf' -H 'accept: application/json'";

	}

# fetch the data and convert the json to a reference
	my $raw_json =`$cmd`;

	my $json_encoder = JSON::PP->new()->canonical(1);
	my $result = $json_encoder->decode($raw_json);

	my $AGRKB = $result->{reference_curie};

	return ($AGRKB);


}
