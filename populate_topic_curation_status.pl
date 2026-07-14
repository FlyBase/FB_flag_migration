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

Script has three modes:

o dev mode

  o single FBrf mode: asks user for FBrf number (can also use a regular expression to test multiple FBrfs in this mode).


o test mode

  o single FBrf mode: asks user for FBrf number (must be a single FBrf number).

  o uses curl to try to POST data to the Alliance ABC stage server (so asks user for okta token for Alliance ABC stage server).


o production mode

  o makes data for all relevant FBrfs in chado.




o Output files

  o The same four files are made in each mode:

  o json output file (FB_curation_status_data.json) - in all modes except 'test' contains a single json structure for all the data (curation status data is a set of arrays within a 'data' object, plus there is a 'metaData' object to indicate source). In test mode, successfully submitted json elements are printed in this file.

 o 'plain' output file (FB_curation_status_data.txt) to aid in debugging - prints the same information as in the json file, but in a more human-readable tsv format with a single row for each FBrf+topic combination, along with additional information useful for debugging.

  o FB_curation_status_data_errors.err - errors in mapping FlyBase data to appropriate Alliance json are printed in this file.

  o FB_curation_status_process_errors.err - processing errors - if a curl POST fails in test mode, the failed json element and the reason for the failure are printed in this file. Expected to be empty for all other modes.


Mapping hashes: 

o $curation_status_topics - mapping hash of topics that we want to submit curation status information for to the Alliance. This hash is structured from the point of view of the relevant ATP topics, to make processing easier. This hash is built using the information in the standard $flag_mapping mapping hash obtained from the &get_flag_mapping subroutine; more than one FB triage flag in the $flag_mapping mapping hash can collapse down to a single ATP topic for curation status tracking.


o $flag_suffix_mapping - mapping of FB triage flag suffixes to:

  o either the appropriate ATP term describing curation status; terms are children of the 'curation' (ATP:0000230) - workflow tag.
  o or 'undef' if the suffix is not relevant to curation status (so that these irrelevant suffixes can be ignored later on in the script).



Script logic:

1. Builds the $curation_status_topics hash to build a list of the ATP topics for which we want to export curation status information to the Alliance.

2. For each ATP topic in the $curation_status_topics hash the following data is then gathered:

2a. If relevant for the topic (when the ATP topic has a 'suffix' key in $curation_status_topics), makes a list ($flags_with_suffix) of all pub_id that have any of the relevant FB triage flags for that ATP topic, where the FB triage flag has a suffix. The list stores the ATP curation status and timestamp information for each pub_id+ATP topic combination.

2b. If relevant for the topic (when the ATP topic has a 'get_curated_data' key in $curation_status_topics), makes a list ($has_curated_data) of all pub_id that have curated data corresponding to the ATP topic (this allows QA/QC later).

2c. If relevant for the topic (when the ATP topic has a 'use_filename' key in $curation_status_topics), makes a list ($currecs_by_timestamp) of all pub_id that are *expected* to contain curated data corresponding to the ATP topic because they have a curation record with the standard filename format for that topic (this allows QA/QC later, and also allows additional information to be exported to the Alliance for those publications that were curated *before* we started using triage flags in FB).

2d. For topics where the curation status is to be determined based on whether thin curation has been done (when the ATP topic has a 'use_thin_cur_status' key in $curation_status_topics), two lists are made: a. list of relevant curation records, b. the list of publications that have the relevant triage flag(s) for that topic.

3. If the curation status in FB is recorded using a :: suffix appended to the FB triage flag, this is used first to try to determine curation status.

3a. For some topics, the triage flag suffix alone is sufficient to determine curation status without using any additional information (value of 'suffix' key is 'only').

3b. For other topics, additional QA/QC is done to determine the final curation status to submit to the Alliance.

This is necessary because for some FB triage flags, the suffix '::DONE' has been used in the past to mean two different things:

o there is data for that triage flag and the relevant curation has been 'done'.

o the FB triage flag was incorrect and that there is therefore nothing to curate for that particular datatype.


The additional QA/QC checks for flags with a '::DONE' suffix:

- add the appropriate curation_status and curation_tag information based on whether or not the publication contains curated data of the relevant datatype.
- for cases where this is no curated data of the relevant type, stores an explanatory 'potential_note' that *may* be added to the json structure later on (in 5. below), depending on whether there are any standard format internal notes for that topic.


4. Then, the list of publications that have a curation record with the standard filename format expected for that datatype is used to fill in curation status for any publications that have not already been taken care of in 3.

This is needed to add curation status for publications where the curation was done in FB before we started using triage flags.

Again, the curation status is stored along with any relevant 'controlled_tag' and/or 'potential_note' information based on whether or not the publication contains curated data of the relevant datatype.

5. For topics where the curation status is to be determined based on whether thin curation has been done (when the ATP topic has a 'use_thin_cur_status' key in $curation_status_topics), the data stored in 2d. above is used to add the relevant curation status.

6. Internal notes associated with the publication are then used as follows:

For some topics it is not appropriate to add any internal notes, as they will instead be added in the workflow status for 'manual indexing' (these topics have a 'do_not_add_internal_note' key in the $curation_status_topics hash).

For other topics:

6a. if the internal note matches any of the standard format notes expected for that topic:

- the original curation_tag information assinged in 3. or 4. above may be changed to a more appropriate value (using the info in $int_note_to_curation_tag_mapping).
- the potential_note may be added into the 'note' slot for submitting in the json (only used if adding the more appropriate curation_tag does not fully explain the curation status)
- the standard format note may be *removed* from the internal note text (done when the the more appropriate curation_tag fully conveys the information in the standard format note).
- any remaining internal note information is added to the 'note' slot for submitting in the json.

6b. for any other internal notes not dealt with by the above, then if the internal note metadata (timestamp, curator, curation records) *completely* matches that of the curated_by timestamp for a topic, then it is safe to add that internal note into the 'note' slot for that topic.




7. Once the script has been through all the ATP topics, the stored information is converted into json for submitting to the Alliance.

NOTE: The script uses the above more complicated logic rather than only using the list made in 2b. of publications that that have curated data corresponding to the ATP topic data because the presence of data in the database does not give any indication of how *complete* the curation is for a given topic, but that detail can be mapped from the FB flag suffixes and standard curation record filename information.

NOTE on timestamps:

o For timestamps determined from the FB triage flag suffix, the *latest* timestamp for the pub+triage flag combination in FB is used, because this should correspond to the timestamp of when the curation of the datatype occurred (the earliest timestamp can indicate the timestamp when the triage flag (without suffix) was added to the database, rather than the curation of the datatype).

o For timestamps determined from curation record(s) with the standard filename format expected for that datatype, the *earliest* timestamp for any matching records for the pub+topic combination in FB is used, because this should correspond to the first (main) curation record containing the curation for that datatype (rather than any subsequent edits).

=cut



if (@ARGV != 6) {
    warn "Wrong number of arguments, should be 6!\n";
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|production access_token\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|production ABCD1234\n\n";
    exit;
}

my $server = shift(@ARGV);
my $db = shift(@ARGV);
my $user = shift(@ARGV);
my $pwd = shift(@ARGV);
my $ENV_STATE = shift(@ARGV);
my $access_token = shift(@ARGV);

unless ($ENV_STATE eq 'dev'|| $ENV_STATE eq 'test'|| $ENV_STATE eq 'production') {

	warn "Unknown state '$ENV_STATE': must be 'dev', 'test' or 'production'\n\n";
	exit;

}

my $test_FBrf = '';

# variable that specifies the appropriate path (downstream of the base URL) to use for the Alliance Literature Service API.
# Used to add an element in the metaData object of the output json file and in the curl command used when in test mode.
my $api_endpoint = 'curation_status';



if ($ENV_STATE eq "test") {

	print STDERR "You are about to write data to the stage Alliance literature server\n";
	print STDERR "Type y to continue else anything else to stop:\n";

	my $continue = <STDIN>;
	chomp $continue;
	if (($continue eq 'y') || ($continue eq 'Y')) {
		print STDERR "Processing will continue.\n";
	} else {
		die "Processing has been cancelled.\n";

	}

}

if ($ENV_STATE eq "dev" || $ENV_STATE eq "test") {

	print STDERR "FBrf to test:";
	$test_FBrf = <STDIN>;
	chomp $test_FBrf;

	if ($ENV_STATE eq "test") {

		unless ($test_FBrf =~ m/^FBrf[0-9]{7}$/) {
			die "Only a single FBrf is allowed in test mode.\n";
		}
	}
}

my $dsource = sprintf("dbi:Pg:dbname=%s;host=%s;port=5432",$db,$server);
my $dbh = DBI->connect($dsource,$user,$pwd) or die "cannot connect to $dsource\n";

my $json_encoder = JSON::PP->new()->pretty(1)->canonical(1);


# map bit after :: when present in flag according to the type of information it adds wrt curation status
my $flag_suffix_mapping = {

	'DONE' => {
		'curation_status' => 'ATP:0000239', # 'curated'
	},

	'Partially done' => {

		'curation_status' => 'ATP:0000239', # 'curated'
		'note' => 'Partial curation.',
	},

	'In progress' => {

		'curation_status' => 'ATP:0000237', # 'curation in progress'
	},

	'Author query sent' => {

		'curation_status' => 'ATP:0000236', # 'curation blocked'
		'note' => 'Author query sent.',
	},

	'No response to author query' => {

		'curation_status' => 'ATP:0000236', # 'curation blocked'
		'note' => 'No response to author query.',
	},

	'Needs cam curation' => {

		'curation_status' => 'ATP:0000236', # 'curation blocked'
		'note' => 'Needs manual indexing.', # should also add a needs curating status to the manual indexing part in the Alliance
	},

	'untouched' => {

		'curation_status' => 'ATP:0000239', # set to 'curated' so that the relevant topic goes through the QA/QC that resets status depending on curated data and/or curation record filename.
	},

# suffix that does not add information about the curation status of the topic to which the suffix is attached
# the information that the topic is incorrect will need to be used (in different script) to prevent adding the relevant topic
# need to use it here to suppress false-positive WARNING messages 
	'Inappropriate use of flag' => undef,


};


# structure of the required json for each element
#{
#  "date_created": $timestamp,
#  "date_updated": $timestamp,
#  "created_by": $curator,
#  "updated_by": $curator,
#  "mod_abbreviation": "FB",
#  "reference_curie": FB:$FBrf,
#  "topic": $ATP,
#  "curation_status": $flag_suffix_mapping->{$ATP}->{'curation_status'},
#  "note": $flag_suffix_mapping->{$ATP}->{'note'}
#  "curation_tag": # this is for the 'controlled_note' - most are negative 
#}


# open output and error logging files

open my $json_output_file, '>', "FB_curation_status_data.json"
	or die "Can't open json output file ($!)\n";
binmode($json_output_file, ":utf8");

open my $data_error_file, '>', "FB_curation_status_data_errors.err"
	or die "Can't open data error logging file ($!)\n";
binmode($data_error_file, ":utf8");

open my $process_error_file, '>', "FB_curation_status_process_errors.err"
	or die "Can't open processing error logging file ($!)\n";
binmode($process_error_file, ":utf8");


open my $plain_output_file, '>', "FB_curation_status_data.txt"
	or die "Can't open plain output file ($!)\n";
binmode($plain_output_file, ":utf8");


print $plain_output_file "##Starting processing: " . (scalar localtime) . "\n";



my $pub_id_to_FBrf = {};

my $sql_query;

unless ($ENV_STATE eq 'dev' || $ENV_STATE eq 'test') {

	$sql_query = sprintf("select p.uniquename, p.pub_id, cvt.name from pub p, cvterm cvt where p.is_obsolete = 'f' and p.type_id = cvt.cvterm_id and cvt.is_obsolete = '0' and cvt.name in ('paper', 'erratum', 'letter', 'note', 'teaching note', 'supplementary material', 'retraction', 'personal communication to FlyBase', 'review') and p.uniquename ~'%s'", '^FBrf[0-9]+$');


} else {


	$sql_query = sprintf("select p.uniquename, p.pub_id, cvt.name from pub p, cvterm cvt where p.is_obsolete = 'f' and p.type_id = cvt.cvterm_id and cvt.is_obsolete = '0' and cvt.name in ('paper', 'erratum', 'letter', 'note', 'teaching note', 'supplementary material', 'retraction', 'personal communication to FlyBase', 'review') and p.uniquename ~'%s'", $test_FBrf);


}
my $db_query= $dbh->prepare  ($sql_query);
$db_query->execute or die" CAN'T GET FBrf FROM CHADO:\n$sql_query)\n";
while (my ($uniquename, $pub_id, $pub_type) = $db_query->fetchrow_array()) {
  $pub_id_to_FBrf->{$pub_id}->{'FBrf'} = $uniquename;
  $pub_id_to_FBrf->{$pub_id}->{'type'} = $pub_type;
}

# 1. Use the mapping information obtained from &get_flag_mapping to make a $curation_status_topics mapping hash
# from the point of view of the ATP topic term that will be used to submit curation_status info into the ABC.
my $flag_mapping = &get_flag_mapping();
my $curation_status_topics = {};
my $diseaseHP_types = {};

# 1a. First fill in the relevant information for FB triage flags which can have a suffix that is relevant to curation status.
foreach my $flag_type (sort keys %{$flag_mapping}) {

	foreach my $flag (sort keys %{$flag_mapping->{$flag_type}}) {

		if ($flag eq 'diseaseHP') {
			$diseaseHP_types->{$flag_type} = "$flag_mapping->{$flag_type}->{$flag}->{ATP_topic}";

		}

		if (exists $flag_mapping->{$flag_type}->{$flag}->{'for_curation_status'}) {

			my $ATP = $flag_mapping->{$flag_type}->{$flag}->{ATP_topic};

			$curation_status_topics->{$ATP}->{'flag_type_list'}->{$flag_type}++;

			push @{$curation_status_topics->{$ATP}->{'flags'}}, $flag;

# assign information from $flag_mapping that was originally under for_curation_status for the flag to a hash where the key has '_list' appended to the end.
# this allows for QC in 1b. below, to make sure that when multiple FB flags map to a single ATP topic all the curation_status related data for each flag is consistent
			foreach my $key (sort keys %{$flag_mapping->{$flag_type}->{$flag}->{'for_curation_status'}}) {


				my $value = $flag_mapping->{$flag_type}->{$flag}->{'for_curation_status'}->{$key};

				my $list_key = "$key" . "_list";
				
				$curation_status_topics->{$ATP}->{$list_key}->{$value}++;

			}

		}
	}

}


# 1b. check for data conflicts after populating $curation_status_topics and warn if needed.
# this checks that when multiple FB triage flags map to a single ATP topic, the curation_status related data coming from each FB triage flag is consistent.
foreach my $ATP (sort keys %{$curation_status_topics}) {

	foreach my $key (sort keys %{$curation_status_topics->{$ATP}}) {

		if ($key =~ m/_list$/) {

			if (scalar keys %{$curation_status_topics->{$ATP}->{$key}} == 1) {

				my $key_minus_list = "$key";
				$key_minus_list =~ s/_list$//;
				my $value = join '', keys %{$curation_status_topics->{$ATP}->{$key}};
				$curation_status_topics->{$ATP}->{$key_minus_list} = $value;
				delete $curation_status_topics->{$ATP}->{$key}; # remove unecessary '_list' branch if passes checks

			} else {

				my $key_minus_list = "$key";
				$key_minus_list =~ s/_list$//;

				if ($key eq 'flag_type_list') {
					warn "\$curation_status_topics: The ATP term: $ATP is being used for triage flags in different flag_type slots in chado - cannot process this.\n";

				} else {
					warn "\$curation_status_topics: $ATP has multiple values in the '$key' slot - cannot process this as it indicates a data conflict.\nValues were: " . (join ' ', (sort keys %{$curation_status_topics->{$ATP}->{$key}})). "\nFix values of the '$key_minus_list' key for flags that map to $ATP in the get_flag_mapping of Mappings.pm to remove the conflict.\n";
				}
			}
		}


	}
}


my $int_note_to_curation_tag_mapping = {

	'ATP:0000069' => {

		'1' => {

			'regex' => 'phys_int not curated',
			'tag' => 'ATP:0000208',
			'status' => 'ATP:0000299',
			'remove_potential_note' => '1',
		},

		'2' => {
			'regex' => 'phys_int not curated; bad flag',
			'tag' => 'ATP:0000226',
			'status' => 'ATP:0000299',
			'remove_potential_note' => '1',
		},
		'3' => {

			'regex' => 'phys_int not curated; bad SVM flag',
			'tag' => 'ATP:0000226',
			'status' => 'ATP:0000299',
			'remove_potential_note' => '1',

		},
		'4' =>{
			'regex' => 'already curated by',
			'tag' => '',
			'status' => 'ATP:0000299',
			'remove_potential_note' => '1',
			'freeze_tag' => '1',
		},

	},


	'ATP:0000079' => {

		# this one is necessary due to a small number of cases where the 'phen_cur: CV annotations only' note was erroneously added for papers with no phenotypic data
		'1' => {

			'regex' =>'^phen curation: No phenotypic data in paper\.( *[a-z]{2}[0-9]{6}\.?)?\nphen_cur: CV annotations only(\. *[a-z]{2}[0-9]{6}\.?)?$',
			'remove_int_note' => '1',
			'remove_potential_note' => '1',
			'status' => 'ATP:0000299',

		},
		'2' => {

			'regex' =>'^phen curation: only pheno_chem data in paper\.( *[a-z]{2}[0-9]{6}\.?)?\nphen_cur: CV annotations only(\. *[a-z]{2}[0-9]{6}\.?)?$',
			'remove_int_note' => '1',
			'remove_potential_note' => '1',
			'status' => 'ATP:0000299',

		},
		'3' => {

			'regex' =>'^phen curation: only pheno_chem data in paper\.( *[a-z]{2}[0-9]{6}\.?)?$',
			'remove_int_note' => '1',
			'status' => 'ATP:0000299',
			'remove_potential_note' => '1',

		},

		'4' => {

			'regex' =>'^phen curation: No phenotypic data in paper\.( *[a-z]{2}[0-9]{6}\.?)?$',
			'remove_int_note' => '1',
			'remove_potential_note' => '1',
			'status' => 'ATP:0000299',

		},

		'5' => {
			'regex' =>'^phen_cur: CV annotations only(\. *[a-z]{2}[0-9]{6}\.?)?$',
			'status' => 'ATP:0000239',
		},

	},


	'ATP:0000011' => {

		'1' => {

			'regex' =>'^HDM flag not applicable\.?( *[a-z]{1,}[0-9]{6})?$',
			'remove_int_note' => '1',
			'remove_potential_note' => '1',
			'status' => 'ATP:0000299',
		},

	},

	'ATP:0000151' => {

		'1' => {

			'regex' =>'^FTA: DOcur genotype - need to check for missing drivers$',
			'status' => 'ATP:0000239',
		},

	},


};


#print Dumper ($curation_status_topics);
#print Dumper ($diseaseHP_types);
#die;


# get list of all internal notes, filtering out notes that will be added elsewhere in the Alliance in a different script
my $additional_filters = [

	# Use simple regex to remove *all* 'Dataset:' lines - will be converted to a topic and/or associated free text note in populate_topic_data script
	'^(D|d)ataset:.+$',

	# filters to remove lines that will be converted to a free text note attached to relevant topic in populate_topic_data script
	'^The phys_int flag inferred from.+$',
	'^The phys_int flag is inferred from.+$',
	'^The phys_int flag was inferred.+$',
	'^FTYP cell line:.+$',

	# filter to remove lines that would be better converted into a note when submit curation record filename info.
	'^Curation record .*? is to add the allele phendesc data originally curated in .+$',
	'^Curation record .*? is to fix data for MI4 .+$',
	'^Curation record .*? generated by hand to fix MI4 ticket.+$',

	# filter to remove preliminary data that will not be submitted to the Alliance
	'^HDM flag future.+$',


];


my $all_candidate_internal_notes = &get_all_pub_internal_notes_for_tet_wf($dbh, $additional_filters);
my $all_curation_record_data = &get_all_currec_data($dbh);

# get list of all pub_ids that have had plincg (correct) to triage flag data
my $pubs_with_triage_flag_plingc = &get_pubs_with_triage_flag_plingc($dbh);


my $complete_data = {};

# 2. go through each topic in the $curation_status_topics hash, determine and store curation status, using relevant information for that flag (this is specified in the $curation_status_topics hash).


foreach my $ATP (sort keys %{$curation_status_topics}) {

	my $curation_status_data = {};

	# get relevant info for the topic
	# get references with triage flag(s) with suffixes for the flag(s) that correspond to the ATP topic
	my $flags_with_suffix = undef;
	if (exists $curation_status_topics->{$ATP}->{'suffix'}) {
		$flags_with_suffix = &get_timestamps_for_flaglist_with_suffix($dbh,$curation_status_topics->{$ATP}->{'flag_type'},$curation_status_topics->{$ATP}->{'flags'});
	}
	# if appropriate, get references that have curated data corresponding to the ATP topic (identified from direct db query for references containing the datatype)
	my $has_curated_data = undef;
	if (exists $curation_status_topics->{$ATP}->{'get_curated_data'}) {
		$has_curated_data = &pub_has_curated_data($dbh,$curation_status_topics->{$ATP}->{'get_curated_data'});
	}

	# if appropriate, get references that are *expected* to contain curated data corresponding to the ATP topic, based on curation record filename.
	# (Note this is NOT used to populate data for topics that are curated during thin curation, because there is not a one-to-one relationship between
	# presence/absence of one of these topics and presence/absence of thin curation record. The separate $thin_currecs is used to store references for instead).
	my $currecs = {};

	if (exists $curation_status_topics->{$ATP}->{'use_filename'}) {

		($currecs->{"by_timestamp"}, $currecs->{"by_curator"}) = &get_relevant_currec_for_datatype($dbh,$curation_status_topics->{$ATP}->{'use_filename'});

	}

	#additional 'cam_full' curation record filename info - needed for pheno flag
	my $cam_full = {};
	if (exists $curation_status_topics->{$ATP}->{'use_cam_full_filename'}) {
		($cam_full->{"by_timestamp"}, $cam_full->{"by_curator"}) = &get_relevant_currec_for_datatype($dbh,'cam_full');

	}

	# information for working out curation status for topics that are curated during thin curation
	# references that have had thin curation done
	my $thin_currecs = {};
	# mapping of topic to references
	my $thin_flag_data = undef;
	my @record_types;

	if (exists $curation_status_topics->{$ATP}->{'use_thin_cur_status'}) {
		@record_types = split '\|', $curation_status_topics->{$ATP}->{'use_thin_cur_status'};

		foreach my $record_type (@record_types) {
			($thin_currecs->{$record_type}->{"by_timestamp"}, $thin_currecs->{$record_type}->{"by_curator"}) = &get_relevant_currec_for_datatype($dbh,$record_type);

		}
		$thin_flag_data = &get_timestamps_for_flaglist($dbh,$curation_status_topics->{$ATP}->{'flag_type'},$curation_status_topics->{$ATP}->{'flags'});

	}


	# first assign curation status based on flag suffixes, double-checking that there is curated data of the relevant type, if that is appropriate for the particular flag
	if (defined $flags_with_suffix) {
		foreach my $pub_id (sort keys %{$flags_with_suffix}) {

			if (exists $pub_id_to_FBrf->{$pub_id}) {

				unless ($curation_status_topics->{$ATP}->{'flag_type'} eq 'cam_flag' && $pub_id_to_FBrf->{$pub_id}->{'type'} eq 'review') {

					if (scalar keys %{$flags_with_suffix->{$pub_id}} == 1) {

						my $suffix = join '', keys %{$flags_with_suffix->{$pub_id}};

						if (exists $flag_suffix_mapping->{$suffix}) {

							# only consider suffixes that are relevant to curation status
							if (defined $flag_suffix_mapping->{$suffix}) {

								my $curation_status = $flag_suffix_mapping->{$suffix}->{curation_status};

								my $curation_tag = '';
								my $note = '';
								my $potential_note = '';
								my $debugging_note = '';

								if (exists $flag_suffix_mapping->{$suffix}->{note}) {

									if ($note) {
										$note = "$note||$flag_suffix_mapping->{$suffix}->{note}";
									} else {
										$note = "$flag_suffix_mapping->{$suffix}->{note}";
									}
								}


								my $timestamp = $flags_with_suffix->{$pub_id}->{$suffix}->{'timestamp'}[-1];
								my $curated_by = '';
								my $relevant_currecs = '';

								# try to match up timestamp information to relevant curation record
								my $curator_details = &get_relevant_curator_from_candidate_list($currecs, $pub_id);


								unless (defined $curator_details) {

									# the publication DOES NOT have a curation record of the expected filename format for the topic (so the data was probably submitted as an edit record).
									# If appropriate for the topic, see if it is possible to unambiguously identify a single curation record of any format that BOTH matches the flag suffix timestamp
									# AND where the curator *added* a flag::DONE flag straight into that record (because the record contains the curation for that topic).
									unless (exists $curation_status_topics->{$ATP}->{'exclude_check_any_record_matching_suffix_timestamp'}) {

										# set default debugging_note that gets overridden if curator can be reconciled
										$debugging_note = 'CURATOR: no record with filename format for topic exists for pub (in flag suffix loop) - CANNOT RECONCILE TO SINGLE CURATOR';

										## determine whether appropriate to try to identify matching curation record
										my $do_check_switch = 0;

										if (exists $pubs_with_triage_flag_plingc->{$pub_id}) {

											if (exists $pubs_with_triage_flag_plingc->{$pub_id}->{"$curation_status_topics->{$ATP}->{flag_type}"}) {

												if (exists $pubs_with_triage_flag_plingc->{$pub_id}->{"$curation_status_topics->{$ATP}->{flag_type}"}->{$timestamp}) {

													# if the flag_with_suffix was being plingc-ed, only do the check if appropriate for the topic and if this publication is the *ONLY* time it was plingc-ed
													if (scalar keys %{$pubs_with_triage_flag_plingc->{$pub_id}->{"$curation_status_topics->{$ATP}->{flag_type}"}} == 1) {

														if (exists $curation_status_topics->{$ATP}->{'relax_plingc_constraint_for_any_record_check'}) {
															$do_check_switch = 2;

															if (exists $curation_status_topics->{$ATP}->{'relax_plingc_constraint_currec_regex'}) {
																$do_check_switch = 3;
															}

														}


													}

												} else {
													# the flag_with_suffix was being added, NOT plingc-ed so do the check
													$do_check_switch = 1;
												}


											} else {

												# no plingc for the triage flag type for the pub so do the check
												$do_check_switch = 1;
											}

										} else {
											# no plingc for the pub so do the check
											$do_check_switch = 1;

										}
										##

										if ($do_check_switch) {

											my $candidate_curator_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id, $timestamp);
											if (defined $candidate_curator_details) {

												my $candidate_curator = "$candidate_curator_details->{curator}";
												my $candidate_currecs = "$candidate_curator_details->{currecs}";

												if ($candidate_currecs ne 'multiple curators for same timestamp') {

													if ($do_check_switch == 3) {

														if ($candidate_currecs =~ m/$curation_status_topics->{$ATP}->{relax_plingc_constraint_currec_regex}/) {

															$curated_by = "$candidate_curator";
															$relevant_currecs = "$candidate_currecs";
															$debugging_note = 'CURATOR: currec matching flag suffix timestamp ONLY (relax plingc constraint) (no record with filename format for topic exists for pub)';

														}

													} else {

														$curated_by = "$candidate_curator";
														$relevant_currecs = "$candidate_currecs";
														$debugging_note = 'CURATOR: currec matching flag suffix timestamp ONLY (no record with filename format for topic exists for pub)';
														if ($do_check_switch == 2) {
															$debugging_note = 'CURATOR: currec matching flag suffix timestamp ONLY (relax plingc constraint) (no record with filename format for topic exists for pub)';
														}


													}
												}
											}
										}
									}

								} else {

									# the publication does have a curation record of the expected filename format for the topic
									my $curator_timestamp = "$curator_details->{timestamp}";
									if ($curator_timestamp eq $timestamp && $curator_details->{currecs} ne 'multiple curators for same timestamp') {
									# if the timestamp does match, use the curator details

										$curated_by = "$curator_details->{curator}";
										$relevant_currecs = "$curator_details->{currecs}";
										$debugging_note = 'CURATOR: currec matching flag suffix timestamp AND filename format for topic';

									} else {
									# if the timestamp does not match, see if there is only one curation record of the appropriate filename format for the topic, and if so, use that, updating the timestamp to that of the curation record (so that any internal notes from that record will be pulled in later on)
										# set default debugging_note that gets overridden if curator can be reconciled
										$debugging_note = 'CURATOR: multiple currec matching filename format (in flag suffix loop) - CANNOT RECONCILE TO SINGLE CURATOR';
										# first check that there is just a single timestamp for matching curation records
										if (scalar @{$currecs->{"by_timestamp"}->{$pub_id}} == 1) {

											# if there is just a single matching curation record for the topic use that
											unless ($curator_details->{currecs} =~ m/ /) {
												$curated_by = "$curator_details->{curator}";
												$relevant_currecs = "$curator_details->{currecs}";
												$timestamp = "$curator_details->{timestamp}";
												$debugging_note = 'CURATOR: single currec matching filename format for topic, overriding timestamp for flag suffix';

											}
										} else {

											# if there are multiple curation records for the topic but they are all from the same curator, use the details from the earliest curation record
											if (scalar keys %{$currecs->{"by_curator"}->{$pub_id}} == 1) {

												unless ($curator_details->{currecs} =~ m/ /) {
													$curated_by = "$curator_details->{curator}";
													$relevant_currecs = "$curator_details->{currecs}";
													$timestamp = "$curator_details->{timestamp}";
													$debugging_note = 'CURATOR: multiple currec matching filename format for topic but all from ONE curator, so using earliest, overriding timestamp for flag suffix';
												}
											}

										}
									}

								}

								my $store_status = 0;

								# flag suffix can be used by itself to store curation status. DESCRIPTION, Script logic: 3a.
								if (exists $curation_status_topics->{$ATP}->{'suffix'} && $curation_status_topics->{$ATP}->{'suffix'} eq 'only') {
									$store_status++;

								} else {

									# always safe to store curation status when it is something other than 'curated' regardless of whether or not FB db contains relevant data
									unless (exists $flag_suffix_mapping->{$suffix}->{'curation_status'} && $flag_suffix_mapping->{$suffix}->{'curation_status'} eq 'ATP:0000239') {
										$store_status++;
									} else {

										# when curation status is 'curated' do additional QA/QC where possible to check that database does have curated data of the relevant type
										# DESCRIPTION, Script logic: 3b.
										if (defined $has_curated_data) {
											if (exists $has_curated_data->{$pub_id}) {

												$store_status++;


											} else {

												# this represents cases where there is a DONE flag suffix but no curated data of the expected type.

												# for genom_feat ('ATP:0000056') keep curation_status as 'curated' and add an explanatory note only, as the curated data may have been done in a related pc.

												# for all other topics assume that 'DONE' means 'a curator looked at the publication and there was no data to curate'
												# Set curation_status and curation_tag values to appropriate default values ('won't curate' and 'no curatable data').
												# (Note: The default curation_tag value may get overridden later on if there as an publication internal note indicating a slightly different situation).
												# Also record the value of a 'potential_note' that may be added into the 'note' slot later to explain the situation
												# This will only be added if needed (in most cases there will be a publication internal note that can be used
												# to assign a curation_tag which makes the 'potential_note' unecessary).

												$store_status++;

												my $note_to_add = '';
												unless ($ATP eq 'ATP:0000056') {

													$curation_status = 'ATP:0000299'; # won't curate
													$curation_tag = 'ATP:0000226'; # no curatable data
													$potential_note = "'$suffix' flag suffix present in FB, indicating that the publication has been looked at, but there is no curated data of the relevant type in FB, so status set to 'won't curate' with a 'no curatable data' tag.";

												} else {

													$note_to_add = "'$suffix' flag suffix present in FB, indicating that the publication has been looked at, but there is no curated data of the relevant type in FB. Despite this, set status to 'curated' as attribution may be to a related personal communication (after author correspondence) instead of the original reference.";

												}

												if ($note) {
													$note = "$note||$note_to_add";
												} else {
													$note = "$note_to_add";
												}
											}

										} else {

											# in the absence of a check for curated data of the expected type, use presence of curation record with expected filename
											if (exists $currecs->{"by_timestamp"}) {

												if (exists $currecs->{"by_timestamp"}->{$pub_id}) {

													$store_status++;

													my $note_to_add = "'curated' flag suffix confirmed by presence of currec with expected filename format.";

													if ($note) {
														$note = "$note||$note_to_add";
													} else {
														$note = "$note_to_add";
													}

												} else {
													print $data_error_file "WARNING: DONE style flag but no corresponding currec: topic: $ATP, pub_id: $pub_id, suffix: $suffix, note: $note\n";


												}


											}

										}
									}
								}


								if ($store_status) {

									$curation_status_data->{$pub_id}->{json}->{'date_created'} = $timestamp;
									$curation_status_data->{$pub_id}->{json}->{'date_updated'} = $timestamp;

									if ($curated_by) {
										$curation_status_data->{$pub_id}->{json}->{'created_by'} = $curated_by;
										$curation_status_data->{$pub_id}->{json}->{'updated_by'} = $curated_by;


									} else {

										$curation_status_data->{$pub_id}->{json}->{'created_by'} = "FB_curator";
										$curation_status_data->{$pub_id}->{json}->{'updated_by'} = "FB_curator";
									}


									$curation_status_data->{$pub_id}->{json}->{'mod_abbreviation'} = "FB";
									my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
									$curation_status_data->{$pub_id}->{json}->{'reference_curie'} = "FB:$FBrf";

									$curation_status_data->{$pub_id}->{json}->{'topic'} = $ATP;
									$curation_status_data->{$pub_id}->{json}->{'curation_status'} = $curation_status;

									if ($note) {
										$curation_status_data->{$pub_id}->{json}->{note} = $note;
									}

									if ($curation_tag) {
										$curation_status_data->{$pub_id}->{json}->{'curation_tag'} = $curation_tag;
									}

									if ($potential_note) {
										$curation_status_data->{$pub_id}->{debugging}->{'potential_note'} = $potential_note;
									}

									if ($relevant_currecs) {
										$curation_status_data->{$pub_id}->{debugging}->{'currecs'} = $relevant_currecs;

									}

									if ($debugging_note) {
										$curation_status_data->{$pub_id}->{debugging}->{'debugging_note'} = $debugging_note;

									}

								}

							} else {

								# this loop adds an undefined 'curation_status' when the suffix is 'Inappropriate use of flag', which prevents any incorrect 'curated' status being added in the 'DESCRIPTION, Script logic: 4' loop below for these cases.
								if ($suffix eq 'Inappropriate use of flag') {
									$curation_status_data->{$pub_id}->{json}->{'curation_status'} = undef;

								}

							}

						} else {

							print $data_error_file "ERROR: unknown suffix type: topic: $ATP, pub_id: $pub_id, suffix: $suffix\n";
						}
					} else {
						print $data_error_file "ERROR: more than one suffix type for single topic: topic: $ATP, pub_id: $pub_id\n";
					}

				}

			}
		}
	}

########################

	# second assign curation status based on thin curation status, for those flags where that is appropriate
	if (defined $thin_flag_data) {
		foreach my $pub_id (sort keys %{$thin_flag_data}) {

			if (exists $pub_id_to_FBrf->{$pub_id}) {

				unless ($curation_status_topics->{$ATP}->{'flag_type'} eq 'cam_flag' && $pub_id_to_FBrf->{$pub_id}->{'type'} eq 'review') {

					foreach my $record_type (@record_types) {

						unless (exists $curation_status_data->{$pub_id}->{json}) {

							# try to determine the relevant curator for the topic
							my $timestamp = '';
							my $curated_by = '';
							my $relevant_currecs = '';

							my $curator_details = &get_relevant_curator_from_candidate_list($thin_currecs->{$record_type}, $pub_id);

							my $curation_status = '';
							my $debugging_note = '';
							my $curation_tag = '';

							my $store_status = 0;

							if (defined $curator_details) {

								$timestamp = "$curator_details->{timestamp}";
								$curated_by = "$curator_details->{curator}";

								$relevant_currecs = "$curator_details->{currecs}";
								$curation_status = 'ATP:0000239'; # 'curated'

								if ($record_type eq 'cam_full') {

									$debugging_note = "CURATOR: currec matching camcur 'full' filename format";

								} else {
									$debugging_note = 'CURATOR: currec matching filename format for topic';

								}

								$store_status++;


							}




							if ($store_status) {

								$curation_status_data->{$pub_id}->{json}->{'date_created'} = $timestamp;
								$curation_status_data->{$pub_id}->{json}->{'date_updated'} = $timestamp;

								if ($curated_by) {
									$curation_status_data->{$pub_id}->{json}->{'created_by'} = $curated_by;
									$curation_status_data->{$pub_id}->{json}->{'updated_by'} = $curated_by;


								} else {

									$curation_status_data->{$pub_id}->{json}->{'created_by'} = "FB_curator";
									$curation_status_data->{$pub_id}->{json}->{'updated_by'} = "FB_curator";
								}


								$curation_status_data->{$pub_id}->{json}->{'mod_abbreviation'} = "FB";
								my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
								$curation_status_data->{$pub_id}->{json}->{'reference_curie'} = "FB:$FBrf";

								$curation_status_data->{$pub_id}->{json}->{'topic'} = $ATP;
								$curation_status_data->{$pub_id}->{json}->{'curation_status'} = $curation_status;


								if ($curation_tag) {
									$curation_status_data->{$pub_id}->{json}->{'curation_tag'} = $curation_tag;
								}

								if ($relevant_currecs) {
									$curation_status_data->{$pub_id}->{debugging}->{'currecs'} = $relevant_currecs;

								}

								$curation_status_data->{$pub_id}->{debugging}->{'debugging_note'} = $debugging_note;


							}

						}

					}

				}
			}

		}

	}

########################



	#third, assign curation status based on standard record filenames, if not already assigned above (this gets data for papers curated before triage flags were used in FB).
	# DESCRIPTION, Script logic: 4
	if (exists $currecs->{"by_timestamp"}) {

		foreach my $pub_id (sort keys %{$currecs->{"by_timestamp"}}) {

##
			if (exists $pub_id_to_FBrf->{$pub_id}) {

				unless ($curation_status_topics->{$ATP}->{'flag_type'} eq 'cam_flag' && $pub_id_to_FBrf->{$pub_id}->{'type'} eq 'review') {

					unless (exists $curation_status_data->{$pub_id}->{json}) {

						# try to determine the relevant curator for the topic
						my $timestamp = '';
						my $curated_by = '';
						my $relevant_currecs = '';

						my $curator_details = &get_relevant_curator_from_candidate_list($currecs, $pub_id);

						if (defined $curator_details) {

							$timestamp = "$curator_details->{timestamp}";
							$curated_by = "$curator_details->{curator}";
							$relevant_currecs = "$curator_details->{currecs}";


							my $curation_status = '';
							my $potential_note = '';
							my $curation_tag = '';

							my $store_status = 0;


							if (defined $has_curated_data) {



								if (exists $has_curated_data->{$pub_id}) {

									$curation_status = 'ATP:0000239'; # 'curated'
									$store_status++;


								} else {

									# there is no curated data of the expected type, so assume that there was no data to curate,
									# set curation status and curation tag values to appropriate values, along with explanatory note.
									# These values may get overridden later on if there as an internal note indicating a different situation.

									# exclude the special cases of 1. wt_exp 'fex' expression records, and 2. genom_feat 'args' records where this cannot be assumed.


									unless (($ATP eq 'ATP:0000041' && $relevant_currecs =~ m/\.fex\./) || $ATP eq 'ATP:0000056') {
										$store_status++;

										$curation_status = 'ATP:0000299'; # won't curate
										$curation_tag = 'ATP:0000226'; # no curatable data

										$potential_note = "Curation record of standard filename present in FB, indicating that the publication has been looked at, but there is no curated data of the relevant type in FB, so status set to 'won't curate' with a 'no curatable data' tag.";

									}
								}


							}


							if ($store_status) {

								$curation_status_data->{$pub_id}->{json}->{'date_created'} = $timestamp;
								$curation_status_data->{$pub_id}->{json}->{'date_updated'} = $timestamp;
								$curation_status_data->{$pub_id}->{json}->{'curation_status'} = $curation_status;


								$curation_status_data->{$pub_id}->{json}->{'created_by'} = $curated_by;
								$curation_status_data->{$pub_id}->{json}->{'updated_by'} = $curated_by;
								$curation_status_data->{$pub_id}->{json}->{'mod_abbreviation'} = "FB";
								my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
								$curation_status_data->{$pub_id}->{json}->{'reference_curie'} = "FB:$FBrf";

								$curation_status_data->{$pub_id}->{json}->{'topic'} = $ATP;

								if ($curation_tag) {
									$curation_status_data->{$pub_id}->{json}->{'curation_tag'} = $curation_tag;
								}

								$curation_status_data->{$pub_id}->{debugging}->{'currecs'} = $relevant_currecs;

								if ($potential_note) {
									$curation_status_data->{$pub_id}->{debugging}->{'potential_note'} = $potential_note;
								}

								$curation_status_data->{$pub_id}->{debugging}->{'debugging_note'} = 'CURATOR: currec matching filename format for topic';


							}


						}

					}
				}
			}
##
		}
	}

####
	#fourth, for phenotype datatype, additional check for older curation record with older filename format indicating 'full' curation by cam.
	if (exists $cam_full->{"by_timestamp"}) {

		foreach my $pub_id (sort keys %{$cam_full->{"by_timestamp"}}) {

			if (exists $pub_id_to_FBrf->{$pub_id} && $pub_id_to_FBrf->{$pub_id}->{'type'} ne 'review') {

				unless (exists $curation_status_data->{$pub_id}->{json}) {


					# try to determine the relevant curator for the topic
					my $timestamp = '';
					my $relevant_currecs = '';
					my $curated_by = '';

					my $curator_details = &get_relevant_curator_from_candidate_list($cam_full, $pub_id);


					if (defined $curator_details) {

						$timestamp = "$curator_details->{timestamp}";
						$curated_by = "$curator_details->{curator}";
						$relevant_currecs = "$curator_details->{currecs}";

						# add curation status if there is phenotypic data - it is expected that many of this kind of curation record will NOT contain phenotype data,
						# so no need for else loop for those without phenotypic data
						if (defined $has_curated_data) {

							if (exists $has_curated_data->{$pub_id}) {


								$curation_status_data->{$pub_id}->{json}->{'date_created'} = $timestamp;
								$curation_status_data->{$pub_id}->{json}->{'date_updated'} = $timestamp;
								$curation_status_data->{$pub_id}->{json}->{'created_by'} = $curated_by;
								$curation_status_data->{$pub_id}->{json}->{'updated_by'} = $curated_by;

								$curation_status_data->{$pub_id}->{json}->{'mod_abbreviation'} = "FB";
								my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
								$curation_status_data->{$pub_id}->{json}->{'reference_curie'} = "FB:$FBrf";
								$curation_status_data->{$pub_id}->{json}->{'topic'} = $ATP;
								$curation_status_data->{$pub_id}->{json}->{'curation_status'} = "ATP:0000239";


								$curation_status_data->{$pub_id}->{debugging}->{'currecs'} = $relevant_currecs;
								$curation_status_data->{$pub_id}->{debugging}->{'debugging_note'} = "CURATOR: currec matching camcur 'full' filename format";

							}

						}

					}

				}

			}

		}
	}
####




#	print "$ATP\n";
#	print Dumper ($curation_status_data);

	foreach my $pub_id (sort keys %{$curation_status_data}) {


		my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
		my $pub_type = $pub_id_to_FBrf->{$pub_id}->{'type'};



		if (defined $curation_status_data->{$pub_id}->{json}->{'curation_status'}) {


			# variables used for adding internal notes (also used for plain output later)
			my $curated_by = exists $curation_status_data->{$pub_id}->{json}->{'created_by'} ? "$curation_status_data->{$pub_id}->{json}->{'created_by'}" : '';
			my $curation_status = exists $curation_status_data->{$pub_id}->{json}->{'curation_status'} ? $curation_status_data->{$pub_id}->{json}->{'curation_status'} : '';
			my $date_created = exists $curation_status_data->{$pub_id}->{json}->{'date_created'} ? $curation_status_data->{$pub_id}->{json}->{'date_created'} : '';
			my $curation_records = exists $curation_status_data->{$pub_id}->{debugging}->{currecs} ? $curation_status_data->{$pub_id}->{debugging}->{currecs} : '';
			my $debugging_note = exists $curation_status_data->{$pub_id}->{debugging}->{'debugging_note'} ? $curation_status_data->{$pub_id}->{debugging}->{'debugging_note'} : '';


			## 5. adding pub internal notes here
			unless (exists $curation_status_topics->{$ATP}->{'do_not_add_internal_note'}) {
				if (exists $all_candidate_internal_notes->{$pub_id}) {

					my $freeze_tag = 0; # switch so that under some circumstances can 'freeze' the curation_tag value once its been found amongst all possible internal notes under that pub_id

					foreach my $int_note (sort keys %{$all_candidate_internal_notes->{$pub_id}}) {

						my $dealt_with = 0;

						if ($curated_by && $date_created && $curation_records) {

							if (scalar @{$all_candidate_internal_notes->{$pub_id}->{$int_note}} == 1) {
								my $int_note_timestamp = join '', @{$all_candidate_internal_notes->{$pub_id}->{$int_note}};
								my $int_note_details = &get_relevant_curator_from_candidate_list_using_pub_and_timestamp($all_curation_record_data, $pub_id, $int_note_timestamp);



								if (defined $int_note_details && $int_note_timestamp eq $date_created) {

									if ($curated_by eq $int_note_details->{curator} && $int_note_details->{currecs} eq $curation_records && $curation_records ne 'multiple curators for same timestamp' && $curation_records !~ m/ /) {


										# always use the internal note if all the relevant metadata matches, unless it is a camcur 'full' curation record (those internal notes will go under manual indexing status)
										unless ($debugging_note && $debugging_note eq 'CURATOR: currec matching camcur \'full\' filename format') {

											$dealt_with++;

										}

										if (exists $int_note_to_curation_tag_mapping->{$ATP}) {

											foreach my $match_type (sort keys %{$int_note_to_curation_tag_mapping->{$ATP}}) {

												my $string = $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{regex};

												if ($int_note =~ m|$string|m) {

													$dealt_with++;
													if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{tag}) {

														unless ($freeze_tag) {


															# only override the curation_tag value based on the standard_format internal note when the curation_status
															# calculated earlierfrom presence/absence of data matches the expected status for that format internal note
															# (so don't incorrectly add a tag if the internal note was either added by mistake or the complex phys_int case
															# where there can be a formatted 'negative' internal note even when there is curated data
															if ($int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{status} eq $curation_status) {

																if ($int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{tag} ne '') {
																	$curation_status_data->{$pub_id}->{json}->{'curation_tag'} = "$int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{tag}";

																} else {
																	delete $curation_status_data->{$pub_id}->{json}->{'curation_tag'};

																}

																if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{freeze_tag}) {
																	$freeze_tag++;
																}
															}
														}
													}


													# remove the internal note if either a. it has been converted to a curation_tag above
													# or b. the presence of the note must be an error as its a 'no data' standard internal note
													# but there *is* data curated under the paper.
													if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{remove_int_note}) {

														$int_note =~ s/$string//mg;

													}


													if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{remove_potential_note}) {

														if (exists $curation_status_data->{$pub_id}->{debugging}->{'potential_note'}) {

															delete $curation_status_data->{$pub_id}->{debugging}->{'potential_note'};

														}
													}
												}
											}

											$int_note =~ s/^ +//;
											$int_note =~ s/ +$//;
											$int_note =~ s/^\n+//;
											$int_note =~ s/\n+$//;

										}




										# add the internal note info here if its been marked as dealt_with
										if ($dealt_with && $int_note ne '') {
											if (exists $curation_status_data->{$pub_id}->{json}->{note}) {

												$curation_status_data->{$pub_id}->{json}->{note} = &clean_note("$curation_status_data->{$pub_id}->{json}->{note}||$int_note");

											} else {
												$curation_status_data->{$pub_id}->{json}->{note} = &clean_note("$int_note");
											}
										}
									}
								}

							}

						}


						###
						unless ($dealt_with) {


							# then deal with any remaining standard format internal notes (that do not match timestamp of curated_by e.g. if added in .edit record later)
							# this code is the same as that which deals with standard format internal notes where the timestamp info does match above
							if (exists $int_note_to_curation_tag_mapping->{$ATP}) {

								foreach my $match_type (sort keys %{$int_note_to_curation_tag_mapping->{$ATP}}) {

									my $string = $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{regex};

									if ($int_note =~ m|$string|m) {

										$dealt_with++;



										if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{tag}) {

											unless ($freeze_tag) {


												# only override the curation_tag value based on the standard_format internal note when the curation_status
												# calculated earlierfrom presence/absence of data matches the expected status for that format internal note
												# (so don't incorrectly add a tag if the internal note was either added by mistake or the complex phys_int case
												# where there can be a formatted 'negative' internal note even when there is curated data
												if ($int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{status} eq $curation_status) {

													if ($int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{tag} ne '') {
														$curation_status_data->{$pub_id}->{json}->{'curation_tag'} = "$int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{tag}";

													} else {
														delete $curation_status_data->{$pub_id}->{json}->{'curation_tag'};

													}

													if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{freeze_tag}) {
														$freeze_tag++;
													}
												}
											}
										}


										# remove the internal note if either a. it has been converted to a curation_tag above
										# or b. the presence of the note must be an error as its a 'no data' standard internal note
										# but there *is* data curated under the paper.
										if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{remove_int_note}) {

											$int_note =~ s/$string//mg;

										}


										if (exists $int_note_to_curation_tag_mapping->{$ATP}->{$match_type}->{remove_potential_note}) {

											if (exists $curation_status_data->{$pub_id}->{debugging}->{'potential_note'}) {

												delete $curation_status_data->{$pub_id}->{debugging}->{'potential_note'};

											}
										}
									}
								}

								$int_note =~ s/^ +//;
								$int_note =~ s/ +$//;
								$int_note =~ s/^\n+//;
								$int_note =~ s/\n+$//;

								# only add the internal note at this point if it was one of the standard format ones (will deal with others in loop below, as need to check that they have the correct timestamp)
								if ($dealt_with && $int_note ne '') {
									if (exists $curation_status_data->{$pub_id}->{json}->{note}) {

										$curation_status_data->{$pub_id}->{json}->{note} = &clean_note("$curation_status_data->{$pub_id}->{json}->{note}||$int_note");


									} else {
										$curation_status_data->{$pub_id}->{json}->{note} = &clean_note("$int_note");
									}

								}

							}
						}
					}
				}
			}

			# add any remaining 'potential_note' information once finished dealing with internal notes for the publication

			if (exists $curation_status_data->{$pub_id}->{debugging}->{potential_note}) {

				if (exists $curation_status_data->{$pub_id}->{json}->{note}) {

					$curation_status_data->{$pub_id}->{json}->{note} = "$curation_status_data->{$pub_id}->{json}->{note}||$curation_status_data->{$pub_id}->{debugging}->{potential_note}";

				} else {

					$curation_status_data->{$pub_id}->{json}->{note} = "$curation_status_data->{$pub_id}->{debugging}->{potential_note}";
				}


			}


			#store data for making json later
			push @{$complete_data->{data}}, $curation_status_data->{$pub_id}->{json};

			# remaining variables needed for plain output (useful for debugging)
			my $flag = $curation_status_topics->{$ATP}->{'flags'}[0];
			my $curation_tag = exists $curation_status_data->{$pub_id}->{json}->{'curation_tag'} ? $curation_status_data->{$pub_id}->{json}->{'curation_tag'} : '';
			my $note = exists $curation_status_data->{$pub_id}->{json}->{note} ? $curation_status_data->{$pub_id}->{json}->{note} : '';

			# form for printing in plain output
			my $reformatted_note = "$note";
			$reformatted_note =~ s/\n/ /g;

			print $plain_output_file "DATA:$pub_id\t$FBrf\t$pub_type\t$ATP\t$flag\t$curation_status\t$date_created\t$curation_tag\t$reformatted_note\t$curated_by\t$curation_records\t$debugging_note\n";

		}

	}


}

## add 'curation_needed' information for 'plain' (no suffix) diseaseHP flags (both harv_flag and dis_flag), i.e. those that still need curating
foreach my $flag_type (keys %{$diseaseHP_types}) {

	my $diseaseHP_flags = &get_matching_pubprop_value_with_timestamps($dbh,$flag_type,'^diseaseHP$');


	foreach my $pub_id (sort keys %{$diseaseHP_flags}) {


		if (scalar keys %{$diseaseHP_flags->{$pub_id}} == 1) {

			my $flag = join '', keys %{$diseaseHP_flags->{$pub_id}};

			if ($flag eq 'diseaseHP') {

				my $timestamp = $diseaseHP_flags->{$pub_id}->{$flag}[0];

				if (exists $pub_id_to_FBrf->{$pub_id}) {

					my $FBrf = $pub_id_to_FBrf->{$pub_id}->{'FBrf'};
					my $pub_type = $pub_id_to_FBrf->{$pub_id}->{'type'};

					my $element = {};

					$element->{'date_created'} = $timestamp;
					$element->{'date_updated'} = $timestamp;

					$element->{'created_by'} = "FB_curator";
					$element->{'updated_by'} = "FB_curator";

					$element->{'mod_abbreviation'} = "FB";
					$element->{'reference_curie'} = "FB:$FBrf";
					$element->{'topic'} = "$diseaseHP_types->{$flag_type}";
					$element->{'curation_status'} = "ATP:0000238"; # curation_needed
					$element->{'curation_tag'} = "ATP:0000353"; # high priority data

					my $note = '';

					push @{$complete_data->{data}}, $element;

					print $plain_output_file "DATA:$pub_id\t$FBrf\t$pub_type\t$element->{'topic'}\t$flag\t$element->{'curation_status'}\t$element->{'date_created'}\t$element->{'curation_tag'}\t$note\t$element->{'created_by'}\n";
				}


			} else {

				if ($flag_type eq 'dis_flag') {
					print $data_error_file "ERROR: $flag_type flag '$flag' is unexpected (should be converted to more specific flag, not have a suffix): pub_id: $pub_id\n";


				}

			}


		} else {


			print $data_error_file "ERROR: more than one $flag_type 'diseaseHP' style flag for single publication: pub_id: $pub_id\n";

		}
	}

}


#print Dumper ($complete_data);

# convert stored data into json for submitting to the Alliance

# first convert any curator names as needed
$complete_data->{data} = &convert_curator_names_bulk($complete_data->{data});


unless ($ENV_STATE eq "test") {

	my $json_metadata = &make_abc_json_metadata($db, $api_endpoint);

	$complete_data->{"metaData"} = $json_metadata;
	my $complete_json_data = $json_encoder->encode($complete_data);

	print $json_output_file $complete_json_data;


} else {


	foreach my $element (@{$complete_data->{"data"}}) {

		my $json_element = $json_encoder->encode($element);


		my $cmd="curl -X 'POST' 'https://stage-literature-rest.alliancegenome.org/$api_endpoint/'  -H 'accept: application/json'  -H 'Authorization: Bearer $access_token' -H 'Content-Type: application/json'  -d '$json_element'";
		my $raw_result = `$cmd`;
		my $result = $json_encoder->decode($raw_result);

		unless (exists $result->{'detail'}) {

			print $json_output_file "json post success\nJSON:\n$json_element\n\n";

		} else {

			print $process_error_file "json post failed\nJSON:\n$json_element\nREASON:\n$raw_result\n#################################\n\n";

		}


	}




}

print $plain_output_file "##Finished processing: " . (scalar localtime) . "\n";


close $json_output_file;
close $data_error_file;
close $process_error_file;
close $plain_output_file;

