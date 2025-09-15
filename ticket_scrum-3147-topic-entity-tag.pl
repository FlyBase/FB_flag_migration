use strict;
use warnings;
#use XML::DOM;
use DBI;
use Digest::MD5  qw(md5 md5_hex md5_base64);
use Time::Piece;

use JSON::PP;

use File::Basename;
use File::Spec;

# add lib sub-folder containing modules into @INC
# has to be done this way - cannot assign  File::Basename::dirname(File::Spec->rel2abs($0) (which is directory script lives in) to a variable and then put that in the 'use lib' line, because the use lib line is done at compile time, not run time
use lib File::Spec->catdir(File::Basename::dirname(File::Spec->rel2abs($0)), 'lib');

# add modules from lib-subfolder
use AuditTable;

=head1 NAME ticket_scrum-3147-topic-entity-tag.pl


=head1 SYNOPSIS

Used to load FlyBase triage flag information into the Alliance ABC literature database. Generates a json object for each FBrf+triage flag combination which is then submitted using POST to the appropriate ABC server, depending on the script mode provided as one of the arguments.

=cut

=head1 USAGE

USAGE: perl ticket_scrum-3147-topic-entity-tag.pl pg_server db_name pg_username pg_password dev|test|stage|production filename okta_token


=cut

=head1 DESCRIPTION

Script has four modes:

o test/stage/production modes - script uses POST to load the json object data into the corresponding Alliance test/stage/production server. 

o dev mode - script does not try to POST data into a server, but instead just prints the json. In addition, it works for a single FBrf (rather than all FBrfs); the user is asked to submit the FBrf to be tested.


Mapping hashes:

o $flags_to_ignore - triage flags that we do not want to submit to the Alliance

o $flag_mapping - triage flags that we DO want to submit to the Alliance, with key value pairs specifying the relevant mapping information and metadata



Script logic:

1. gets FBrf and pub_id of all current publications that have triage flag information.

2. For each pub_id:

2a. gets triage flag details, including the 'I' timestamp from audit_chado (which indicates when the flag was added).

2b. splits the 'raw' triage flag into the flag part and the suffix part (splits on ::) (e.g. disease::DONE -> flag = disease, suffix = DONE).

3. For each flag,

3a. the flag is ignored if it is in the $flags_to_ignore hash or it has a suffix and the suffix is 'Inappropriate use of flag' (which indicates the flag is incorrect).

3b. For the remaining flags, the script tries to find the matching curator from the 'curated_by' pubprop for that pub_id by comparing audit_chado timestamps.

- the AuditTable::get_relevant_curator subroutine first gets all matching 'curated_by' pubprops with the same audit_chado 'I' timestamp as the triage flag and then:

- if a single match is found, that curator is used.

- if multiple or no curator matches are found, the flag properties are used to try to determine if it must have been a FB curator that added the flag (rather than community curation) - if that is the case, the curator is set to 'FB_curator'.

3c. If a matching curator was successfully identified, a data structure with the relevant information is made for that flag+FBrf combination, using the flag timestamp from audit_chado and mapping information in the $flag_mapping hash to fill out the data structure.

3d. the data structure is then converted to json, and either printed (dev mode) or submitted to the appropriate ABC server using POST (all other modes).


=cut

=head1 STILL TO DO

1. script currently has the topic_entity_tag_source_id number hard-coded, and the number is different for the test/stage/production servers. It is possible to use GET to get this information so investigate whether can change code to use GET instead, so that it is not hard-coded (in case of changes in the servers).

Here is the information about the two topic_entity_tag_sources used, whose ids are currently hard-coded

 use to load FB triage flag into alliance, here we use post to post data into test/stage/production server. 
 before that, we need to set the topic_entity_tag_source_id, so We need first create those two top_entity_tag_source 

So, if Created By = ‘Author Submission’ or ‘User Submission’ you should use: test: 222 stage:222 prod:171

{
  "source_evidence_assertion": "ATP:0000035",
  "source_method": "author_first_pass",
  "description": "Manual creation of entity and data type associations to publications during author first-pass curation using the FlyBase Fast-Track Your Paper form.",
  "validation_type": "author",
  "data_provider": "FB",
  "secondary_data_provider_abbreviation": "FB"
}


otherwise for any other ‘Created by’ value , you should use: test: 223 stage:223 prod: 172

{
  "source_evidence_assertion": "ATP:0000036",
  "source_method": "FlyBase_curation",
  "validation_type": "professional_biocurator",
  "description": "Creation or association of entities and data by biocurator using FB curation systems.",
  "data_provider": "FB",
  "secondary_data_provider_abbreviation": "FB"
}



2. The system call to actually run the $cmd to POST the data to a server is currently commented out. In addition, need to add a test to check that the system call completes successfully and to print an error if not.

3. the script currently requires an input file (given in 5th argument) that maps FBrf numbres to AGKRB numbers. Investigate whether its possible to submit the json using FBrf (I assume not) or whether could use GET to get the AGKRB for each required FBrf (this might make it to slow as its all FBrfs ?!)


the instructions to make the currently required input file are:

To generate the input file use:-
You may need to change the --host value if you want to use prod etc.
You will be prompted for a password, obviously not given here.
You will also need VPN access to the database for this to work.

psql --host literature-dev.cmnnhlso7wdi.us-east-1.rds.amazonaws.com \
     -U postgres -d literature\
     -c "select cr.curie, r.curie from reference r, cross_reference cr where r.reference_id=cr.reference_id and curie_prefix='FB'" \
     -A -F ' ' -t > FBrf_to_AGRKB.txt

=cut


if (@ARGV != 7) {
    warn "Wrong number of argument, shouldbe 7!\n";
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|stage|production filename okta_token\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|stage|production FBrf_to_AGRKB.txt ABCD1234\n\n";
    exit;
}

my $server = shift(@ARGV);
my $db = shift(@ARGV);
my $user = shift(@ARGV);
my $pwd = shift(@ARGV);
my $ENV_STATE = shift(@ARGV);
my $INPUT_FILE = shift(@ARGV);
my $okta_token = shift(@ARGV);


my @STATE = ("dev", "test", "stage", "production");
if (! grep( /^$ENV_STATE$/, @STATE ) ) {
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|stage|production filename okta_token\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|stage|production FBrf_to_AGRKB.txt ABCD1234\n\n";
    exit;
}

# Sanity check if state is not test, make sure the user wants to
# save the data to the database
if ($ENV_STATE eq "stage" || $ENV_STATE eq "production") {
	print STDERR "You are about to write data to $ENV_STATE Alliance literature server\n";
	print STDERR "Type y to continue else anything else to stop\n";
	my $continue = <STDIN>;
	chomp $continue;
	if (($continue eq 'y') || ($continue eq 'Y')) {
	    print STDERR "Processing will continue.";
    }
    else{
	    die "Processing has been cancelled.";
    }
}

my $dsource = sprintf("dbi:Pg:dbname=%s;host=%s;port=5432",$db,$server);
my $dbh = DBI->connect($dsource,$user,$pwd) or die "cannot connect to $dsource\n";

my $FBrf_like='^FBrf[0-9]+$';


# 

my $json_encoder;

# set the json output format to be slightly different for dev mode - pretty separates the name/value pairs by return so its easier to read
if ($ENV_STATE eq "dev") {

	$json_encoder = JSON::PP->new()->pretty(1)->canonical(1);
} else {
	$json_encoder = JSON::PP->new()->canonical(1);

}

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

		'pert_exp' => {
			'ATP_topic' => 'ATP:0000042',
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
		},

		'dm_other' => {

			'ATP_topic' => 'ATP:0000040',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'curator_only' => '1',
		},

		'disease' => {

			'ATP_topic' => 'ATP:0000152',# 'disease model' ATP term - using more specific ATP term for DO curation
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'diseaseHP' => {

			'ATP_topic' => 'ATP:0000152',# disease model ATP term - using more specific ATP term for DO curation
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'data_novelty' => 'ATP:0000229', # new to field
			'curator_only' => '1',
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
		},

		'cell_line' => {
			'ATP_topic' => 'ATP:0000008',
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},


		'cell_line(commercial)' => {
			'ATP_topic' => 'ATP:0000008',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'note' => 'Commercially purchased cell line', # this is what is on FTYP form
		},

		'cell_line(stable)' => {
			'ATP_topic' => 'ATP:0000008',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'note' => 'Stable line generated', # this is what is on FTYP form
		},

		'chemical' => {
			'ATP_topic' => 'ATP:0000094',
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
		},

		'genome_feat' => {
			'ATP_topic' => 'ATP:0000056',
		},

		'pert_exp' => {
			'ATP_topic' => 'ATP:0000042',
			# not curator only - was in original version of FTYP
		},

		'phys_int' => {
			'ATP_topic' => 'ATP:0000069',
		},

		'wt_cell_line' => {
			'ATP_topic' => 'ATP:0000008',
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'wt_exp' => {
			'ATP_topic' => 'ATP:0000041',
		},

		'neur_exp' => {
			'ATP_topic' => 'ATP:0000338',
			'curator_only' => '1',
		},




	},

	'onto_flag' => {

		'novel_anat' => {

			'ATP_topic' => 'ATP:0000031',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'data_novelty' => 'ATP:0000229', # new to field
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

# triage flags that we do not want to submit to the Alliance
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


my %FBgn_type; #key:FBgn, value: transcript type

#read the mapping of FBrf vs alliance curie, which generate from: select cr.curie, r.curie from reference r, cross_reference cr where r.reference_id=cr.reference_id and curie_prefix='FB' ;
my %FB_curie;

unless ($ENV_STATE eq "dev") {

	open (IN, $INPUT_FILE) or die "unable to open file $INPUT_FILE";
	while (<IN>){
   	 chomp;
    	my ($FB, $curie)=split(/\s+/);
    	$FB_curie{$FB}=$curie;
	}
} else {

	print STDERR "FBrf to test:";
	$FBrf_like = <STDIN>;
	chomp $FBrf_like;

}
my %FBrf_pubid;
#my $sql_FBrf=sprintf("select distinct p.uniquename, p.pub_id from pub p, pubprop pp, cvterm c  where p.pub_id=pp.pub_id and c.cvterm_id=pp.type_id and p.is_obsolete='false' and c.name in ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag') and  p.uniquename~'%s' and p.uniquename in ('FBrf0240817','FBrf0236883','FBrf0134733','FBrf0167748','FBrf0213082','FBrf0246285','FBrf0244403','FBrf0209874')  group by p.uniquename, p.pub_id  ",$FBrf_like); #,'harv_flag'  and p.uniquename not in ('FBrf0072646', 'FBrf0081144','FBrf0209074','FBrf0126732','FBrf0210738','FBrf0134733','FBrf0201683','FBrf0108289')    and p.uniquename in ('FBrf0240817','FBrf0236883','FBrf0134733','FBrf0167748','FBrf0213082','FBrf0246285','FBrf0244403','FBrf0209874')  'FBrf0256192', 'FBrf0167748',
my $sql_FBrf=sprintf("select distinct p.uniquename, p.pub_id from pub p, pubprop pp, cvterm c  where p.pub_id=pp.pub_id and c.cvterm_id=pp.type_id and p.is_obsolete='false' and c.name in ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag') and  p.uniquename~'%s' group by p.uniquename, p.pub_id  ",$FBrf_like);

#print "$sql_FBrf\n";
my $FBrf= $dbh->prepare  ($sql_FBrf);
$FBrf->execute or die" CAN'T GET FBrf FROM CHADO:\n$sql_FBrf)\n";
my ($uniquename_FBrf, $pubid);
while (( $uniquename_FBrf, $pubid) = $FBrf->fetchrow_array()) {
  $FBrf_pubid{$uniquename_FBrf}= $pubid;
}

my %topic_entity_tag_source_hash;
$topic_entity_tag_source_hash{"users"}{"dev"}=222;
$topic_entity_tag_source_hash{"users"}{"test"}=222;
$topic_entity_tag_source_hash{"users"}{"stage"}=222;
$topic_entity_tag_source_hash{"users"}{"production"}=171;

$topic_entity_tag_source_hash{"curators"}{"dev"}=223;
$topic_entity_tag_source_hash{"curators"}{"test"}=223;
$topic_entity_tag_source_hash{"curators"}{"stage"}=223;
$topic_entity_tag_source_hash{"curators"}{"production"}=172;

=head
{
  "source_evidence_assertion": "ATP:0000036",
  "source_method": "author_first_pass",
  "validation_type": "professional_biocurator",
  "description": "FlyBase literature curation flag",
  "data_provider": "FB",
  "secondary_data_provider_abbreviation": "FB"l
}
=cut

foreach my $FBrf (sort keys %FBrf_pubid){
    
	my $pubid=$FBrf_pubid{$FBrf};
	#print "uniquename_p:$FBrf:pubid:$pubid:\n";
	my $sql=sprintf("select  c.name, pp.value, pp.pub_id, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.pub_id=%s and c.cvterm_id=pp.type_id  and c.name in ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag')  and ac.audited_table='pubprop' and ac.audit_transaction='I'  and pp.pubprop_id=ac.record_pkey",$pubid );

	my $flag = $dbh->prepare  ($sql);
	$flag->execute or die" CAN'T GET flag FROM CHADO:\n$sql\n";

	while (my ($flag_source,$raw_flag_type, $pub_id, $flag_audit_timestamp) = $flag->fetchrow_array()) {


		# try to split the $raw_flag_type into the triage flag and suffix components. set defaults for the case where there is no suffix
		my $flag_type = $raw_flag_type;
		my $flag_suffix = '';

		if ($raw_flag_type =~ m/^(.+)::(.+)$/) {

			$flag_type = $1;
			$flag_suffix = $2;

		} 

		# 1. only process flags that we want to submit the FB flag to the Alliance
		unless (exists $flags_to_ignore->{$flag_source} && exists $flags_to_ignore->{$flag_source}->{$flag_type}) {


			if (exists $flag_mapping->{$flag_source} && exists $flag_mapping->{$flag_source}->{$flag_type}) {


				# this suffix indicates that the flag is incorrect: ignore and do not submit to the Alliance
				# It would technically be possible to subtmit this with validation information saying flag was incorrect, but this would only add a tiny subset of all the incorrect flags, as it would only be those updated directly in the db (e.g. via chia), and not those that were corrected via plingc in proforma. So decided better to not submit them.
				if ($flag_suffix && $flag_suffix eq 'Inappropriate use of flag') {
					next;
				}


				# 2. try to find the relevant curator (from curated_by pubprop) using audit table timestamp information
				my $curator_data = &AuditTable::get_relevant_curator($dbh, $pub_id, $flag_audit_timestamp);
				my $curator = ''; # this will be the relevant curator with a matching timestamp.
				my $file = ''; # this will be the relevant curation record. Not submitted to the Alliance, but useful for plain text output (DATA: lines) when testing.

				if (defined $curator_data) {

					# simple case, only one matching curated_by pubprop
					if ($curator_data->{count} == 1) {

						$curator = $curator_data->{relevant_curator};
						$file = $curator_data->{relevant_record};

					} else {

						# multiple records for same FBrf submitted in same week by same curator
						if (scalar keys %{$curator_data->{curator}} == 1) {

							$curator = join '', keys %{$curator_data->{curator}};
							$file = join ', ', sort keys %{$curator_data->{curator}->{$curator}};

						} else {

							# flag info must have been submitted/looked at by a curator rather than just multiple user curation, so set curator to the generic 'FB_curator'
							if (exists $flag_mapping->{$flag_source}->{$flag_type}->{curator_only} || $flag_suffix ne '' || exists $curator_data->{FB_curator_count} ) {
								$curator = 'FB_curator';

							} else {
								print "ERROR: multiple different curators that cannot reconcile, not adding: $FBrf\t$flag_source\t$raw_flag_type\t" . (join ', ', keys %{$curator_data->{curator}}) . "\t" . (join ', ', keys %{$curator_data->{curator}->{$curator}}) . "\t$flag_audit_timestamp\n";

							}

						}

					}

					# convert all unknown style curators to the same 'FB_curator' name that is used for persistent store submissions
					if ($curator eq 'Unknown Curator' || $curator eq 'Generic Curator' || $curator eq 'P. Leyland') {
						$curator = 'FB_curator';
					}

				} else {

					# flag info must have been submitted/looked at by a curator rather than just user curation, so set curator to the generic 'FB_curator'
					if (exists $flag_mapping->{$flag_source}->{$flag_type}->{curator_only} || $flag_suffix ne '') {
						$curator = 'FB_curator';

					} else {

						print "ERROR: unable to find who curated for $flag_source $raw_flag_type $FBrf\n";
					}
				}

				# 3. if a curator has been assigned, make a json structure and (unless in dev mode) submit to alliance.
				if ($curator ne '') {


					# first store variables in a $data hash so it is easy to convert to correct json format later (and to add/change json structure if Alliance model changes)
					my $data = {};

					# set basic information for this particular flag and FBrf combination
					my $FBrf_with_prefix="FB:".$FBrf;
					$data->{reference_curie} = ($ENV_STATE eq "dev") ? $FBrf_with_prefix : $FB_curie{$FBrf_with_prefix};

					$data->{created_by} = $curator;
					$data->{date_created} = $flag_audit_timestamp;


					# set other parameters for the flag based on $flag_mapping hash or set the relevant default if the key does not exist in the mapping hash for that flag
					$data->{topic} = $flag_mapping->{$flag_source}->{$flag_type}->{ATP_topic};

					$data->{species} = exists $flag_mapping->{$flag_source}->{$flag_type}->{species} ? $flag_mapping->{$flag_source}->{$flag_type}->{species} : 'NCBITaxon:7227';
					$data->{negated} = exists $flag_mapping->{$flag_source}->{$flag_type}->{negated} ? 1 : 0;

					$data->{novel_topic_data} = exists $flag_mapping->{$flag_source}->{$flag_type}->{data_novelty} ? 1 : 0;

					$data->{data_novelty} = exists $flag_mapping->{$flag_source}->{$flag_type}->{data_novelty} ? $flag_mapping->{$flag_source}->{$flag_type}->{data_novelty} : 'ATP:0000335'; # if the mapping hash has no specific data novelty term set, the parent term (ATP:0000335 = 'data novelty') must be added for ABC validation purposes

					#choose different topic_entity_tag_source_id based on ENV_STATE and 'created_by' value
					if ($curator eq "Author Submission" || $curator eq "User Submission"){
						$data->{topic_entity_tag_source_id} = $topic_entity_tag_source_hash{"users"}{$ENV_STATE};
					} else {
						$data->{topic_entity_tag_source_id} = $topic_entity_tag_source_hash{"curators"}{$ENV_STATE};
					}

					# plain text output useful for testing
					print "DATA: $FBrf\t$flag_source\t$raw_flag_type\t$curator\t$file;\t$flag_audit_timestamp\n";

					my $json_data = $json_encoder->encode($data);



					if ($ENV_STATE eq "dev") {
						print "JSON: \n$json_data\n";

					}

					my $cmd;
					if ($ENV_STATE eq "test"){
						$cmd="curl -X 'POST' 'https://dev4005-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$json_data'";
					} elsif ($ENV_STATE eq "stage"){
						$cmd="curl -X 'POST' 'https://stage-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$json_data'";
					} elsif ($ENV_STATE eq "production"){
						$cmd="curl -X 'POST' 'https://literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$json_data'";
					}

					#print "\n$FBrf $raw_flag_type\n$data\n";
					#print "\n\n$cmd\n";
					#system($cmd);


				}


			} else {

				print "\nERROR: no mapping in the the flag_mapping hash for this flag_type:$raw_flag_type from $flag_source\n";

			}
		}
	}
}




