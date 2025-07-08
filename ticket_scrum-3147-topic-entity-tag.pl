use strict;
use warnings;
#use XML::DOM;
use DBI;
use Digest::MD5  qw(md5 md5_hex md5_base64);
use Time::Piece;

=head
 use to load FB triage flag into alliance, here we use post to post data into test/stage/production server. 
 before that, we need to set the top_entity_tag_source_id, so We need first create those two top_entity_tag_source 

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

# not complete yet
my $flag_mapping = {


	'cam_flag' => {


		'new_al' => {
			'ATP_topic' => 'ATP:0000006',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'novel_data_qualifier' => 'ATP:0000229', # new to field
		},

		'new_allele' => {
			'ATP_topic' => 'ATP:0000006',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'novel_data_qualifier' => 'ATP:0000229', # new to field
		},

		'new_transg' => {

			'ATP_topic' => 'ATP:0000013',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'novel_data_qualifier' => 'ATP:0000229', # new to field
		},


		'gene_group' => {
			'ATP_topic' => 'ATP:0000065',
			'species' => '??need to check??', # only have this if not the default of Dmel, value is NCBITaxon:xxxx
		},

		'pathway' => {
			'ATP_topic' => 'ATP:0000113',
			'species' => '??need to check??', # only have this if not the default of Dmel, value is NCBITaxon:xxxx
		},

		'pheno' => {

			'ATP_topic' => 'ATP:0000079',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'novel_data_qualifier' => 'ATP:0000321??', # ATP:0000321 is 'new data' - not sure whether should have for pheno flag to distinguish between papers that have been curated for phenotype, but did not merit a pheno flag and whether to use more general 'new data' rather than 'new to field'??
		},

		'pheno_anat' => {

			'ATP_topic' => 'ATP:0000032',
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'pheno_chem' => {

			'ATP_topic' => 'ATP:0000080',
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'rename' => {

			'ATP_topic' => 'ATP:0000048',
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'pert_exp' => {
			'ATP_topic' => 'ATP:0000042',
		},

	},


	'dis_flag' => {


		'dm_gen' => {

			'ATP_topic' => 'ATP:0000151',
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'dm_other' => {

			'ATP_topic' => 'ATP:0000040',
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'disease' => {

			'ATP_topic' => 'ATP:0000152',# disease model ATP term
			'species' => 'NCBITaxon:7214', # Drosophilidae
		},

		'noDOcur' => {

			'ATP_topic' => 'ATP:0000152',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'negated' => '1', # only present if the flag should have the 'no data' boolean set in ATP, note that representation of this is in flux in ATP
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



	},

	'onto_flag' => {

		'novel_anat' => {

			'ATP_topic' => 'ATP:0000031',
			'species' => 'NCBITaxon:7214', # Drosophilidae
			'novel_data_qualifier' => 'ATP:0000229', # new to field
		},

	},
};


# triage flags that we do not want to submit to the Alliance
my $flags_to_ignore = {

	'cam_flag' => {

		'no_flag' => '1',
		'nocur_abs' => '1',
		'orthologs' => '1',
		'new_gene' => '1',
		'y' => '1',
	},

	'harv_flag' => {
		'y' => '1',
		'n' => '1',
		'no' => '1',
		'trans_assay' => '1',
		'RNAi' => '1',
		'micr_arr' => '1',
		'gene_model_nonmel' => '1',
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

#print "\n$sql_FBrf";
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
my $topic_entity_tag_source_id;#need to re-create topic_entity_tag_source and update manually for stage/production ?



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
my $entity_source='alliance';

# my $okta_token='';

print "\nEntity\tEntity_type_ATP\tEntity_source\tFBrf\tFlag_type\tCurator\tTime_from_curator\tTime_from_audit_chado";
foreach my $uniquename_p (keys %FBrf_pubid){
    
	my $pubid=$FBrf_pubid{$uniquename_p};
	#print "\nuniquename_p:$uniquename_p:pubid:$pubid:";
	my $sql=sprintf("select  c.name, pp.value, pp.pub_id, ac.audit_transaction, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.pub_id=%s and c.cvterm_id=pp.type_id  and c.name in ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag')  and ac.audited_table='pubprop' and ac.audit_transaction='I'  and pp.pubprop_id=ac.record_pkey",$pubid );

	#print "\n$sql\n\n";
	my $flag = $dbh->prepare  ($sql);
	$flag->execute or die" CAN'T GET flag FROM CHADO:\n$sql\n";

	my ($flag_source,$raw_flag_type, $pub_id, $transaction_type, $transaction_timestamp, $transaction_timestamp_curated, $transaction_timestamp_audit, $pubprop_id);
	while (($flag_source,$raw_flag_type, $pub_id, $transaction_type, $transaction_timestamp ) = $flag->fetchrow_array()) {


		# split the $raw_flag_type into the triage flag and suffix components. set defaults for the case where there is no suffix
		my $flag_type = $raw_flag_type;
		my $flag_suffix = '';

		if ($raw_flag_type =~ m/^(.+)::(.+)$/) {

			$flag_type = $1;
			$flag_suffix = $2;

		} 

		# only process flags that we want to submit the FB flag to the Alliance
		unless (exists $flags_to_ignore->{$flag_source} && exists $flags_to_ignore->{$flag_type}) {


			if (exists $flag_mapping->{$flag_source} && exists $flag_mapping->{$flag_source}->{$flag_type}) {

				# set parameters based on mapping hash (set a default if key does not exist)
				my $species = exists $flag_mapping->{$flag_source}->{$flag_type}->{species} ? $flag_mapping->{$flag_source}->{$flag_type}->{species} : 'NCBITaxon:7227';
				my $negated = exists $flag_mapping->{$flag_source}->{$flag_type}->{negated} ? 1 : 0;
				my $novel_data_qualifier = exists $flag_mapping->{$flag_source}->{$flag_type}->{novel_data_qualifier} ? $flag_mapping->{$flag_source}->{$flag_type}->{novel_data_qualifier} : '';

				my $topic = $flag_mapping->{$flag_source}->{$flag_type}->{ATP_topic};

				# try to find curated_by pubprop with the same 'timelastmodified' timestamp as the triage flag audit table information
				my @temp0=split(/\s+/, $transaction_timestamp);
				my $time_flag=$temp0[0];
				#print "\n$flag_source,$raw_flag_type,$transaction_timestamp time_flag:$time_flag\n";
				#get all possible 'curated_by', then based on the flag_source, and timestamp to decided who curate it.
				my $sql_curated=sprintf("select distinct  pp.value, ac.transaction_timestamp, pp.pubprop_id  from   pubprop pp, cvterm c, audit_chado ac  where ac.audited_table='pubprop' and ac.audit_transaction='I' and pp.pubprop_id=ac.record_pkey and pp.pub_id=%s and c.cvterm_id=pp.type_id and c.name in ('curated_by')", $pub_id);
				#print "\n$sql_curated\n";
				my $flag=0;
				my $flag_curated = $dbh->prepare  ($sql_curated);
				$flag_curated->execute or die" CAN'T GET curator info FROM CHADO:\n$sql_curated\n";
				while (($transaction_timestamp_curated,  $transaction_timestamp_audit, $pubprop_id) = $flag_curated->fetchrow_array()) {
					#print "\ncurated_by_time: $transaction_timestamp_audit";
					my @case=( $transaction_timestamp_curated =~ /(Curator:.*;)(Proforma: .*;)(timelastmodified: .*)/ ); #Curator: Author Submission;Proforma: as773.user;timelastmodified: Thu Mar 17 08:24:07 2011
					if ($#case >-1){
=header  this use the timestamp attached to the pubprop.value , eg. Curator: P. Leyland;Proforma: pl174708.bibl;timelastmodified: Thu Dec  6 07:15:20 2018
						#print "\n$case[2]";
						my @temp=split(/timelastmodified\:\s+/, $case[2]);
						my $time = $temp[1];	    
						#print "\n$uniquename_p $raw_flag_type $transaction_timestamp_curated time:$time:";
						#expect date format:Thu Jan 17 07:47:53 2008
						#wrong date format cause error: FBrf0072646 nocur Curator: B. Matthews;Proforma: 72646.bev.chem.200617;timelastmodified: Thu 29 Oct 2020 09:13:21 AM EDT

						my @case_time=($time =~/([A-Za-z]+)\s+([A-Za-z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d+)/); #Thu Mar 17 08:24:07 2011
						my @case_time1=($time =~/([a-zA-Z]+)\s+(\d+)\s+([a-zA-Z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+([A-Z]+)\s+([A-Z]+)/);#Thu 29 Oct 2020 09:13:21 AM EDT
	    
						my $time_curated;
						if ($#case_time>-1){
							$time_curated= Time::Piece->strptime($time, '%a %b %d %H:%M:%S %Y')->ymd("-");#Thu Mar 17 08:24:07 2011
						} elsif ($#case_time1>-1) {#Thu 29 Oct 2020 09:13:21 AM EDT
							print "\nwrong format:$uniquename_p $raw_flag_type $transaction_timestamp_curated time:$time:";
							Time::Piece->strptime($time, '%a %d %b %Y %H:%M:%S %Y %c %e')->ymd("-");
							next;
						} else {
							print "\nweird format:$uniquename_p $raw_flag_type $transaction_timestamp_curated time:$time:";
							next;
						}

=cut
						#here we use the audit_chado timestamp as 'curated' time to figure out who curate the flag
						my ($time_curated, $junk)=split(/\s+/, $transaction_timestamp_audit);

						#print "\ntime_flag:$time_flag\ttime_curated:$time_curated";
						if ($time_curated eq $time_flag){
							#get the right curator
							my @temp2=($case[0]=~/(.*):\s(.*)(;)/); #Curator: P. Leyland;
							my $curator=$temp2[1];
							#print "\n$curator $time_curated\n";

							#here to parse filename which insert this flag from pubprop.value
							my ($junk0, $file)=split(/Proforma\:\s+/, $case[1]);
							#here need to parse the time from the pubprop.value
							my @temp=split(/timelastmodified\:\s+/, $case[2]);
							my $time = $temp[1];
							my @case_time=($time =~/([A-Za-z]+)\s+([A-Za-z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d+)/); #Thu Mar 17 08:24:07 2011
							my @case_time1=($time =~/([a-zA-Z]+)\s+(\d+)\s+([a-zA-Z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+([A-Z]+)\s+([A-Z]+)/);#Thu 29 Oct 2020 09:13:21 AM EDT
							my $time_from_curator="";
							if ($#case_time>-1){
								$time_from_curator= Time::Piece->strptime($time, '%a %b %d %H:%M:%S %Y')->ymd("-");#Thu Mar 17 08:24:07 2011
								$time_from_curator.=" ".$case_time[3];
							} elsif ($#case_time1>-1) {#Thu 29 Oct 2020 09:13:21 AM EDT
								my @temp=split(/\s+/, $time);
								my $time_before=$temp[0]." ".$temp[2]." ".$temp[1]." ".$temp[4]." ".$temp[3];
								$time_from_curator= Time::Piece->strptime($time_before, '%a %b %d %H:%M:%S %Y')->ymd("-");
								$time_from_curator.=" ".$temp[4];
							} else {
								print "\nweird curated_by time format:$uniquename_p $raw_flag_type $transaction_timestamp_curated time:$time:";
								next;
							}

							my $FBrf_with_prefix="FB:".$uniquename_p;

							print "\n$uniquename_p\t$flag_source\t$raw_flag_type\t$curator\t$file\t$time_from_curator\t$time_curated";
							#choose different topic_entity_tag_source_id based on ENV_STATE and 'created_by' value
							if ($curator eq "Author Submission" || $curator eq "User Submission"){
								$topic_entity_tag_source_id =$topic_entity_tag_source_hash{"users"}{$ENV_STATE};
							} else {
								$topic_entity_tag_source_id =$topic_entity_tag_source_hash{"curators"}{$ENV_STATE};
							}

							my $data = '';
							my $reference_curie = ($ENV_STATE eq "dev") ? $FBrf_with_prefix : $FB_curie{$FBrf_with_prefix};

							$data='{"date_created": "'.$time_from_curator.'","created_by": "'.$curator.'", "topic": "'.$topic.'", "species": "'.$species.'","topic_entity_tag_source_id": '.$topic_entity_tag_source_id.', "negated": '.$negated.', "reference_curie": "'.$reference_curie.'"}';

							if ($ENV_STATE eq "dev") {
								print "\n$data";

							}

							my $cmd;
							if ($ENV_STATE eq "test"){
								$cmd="curl -X 'POST' 'https://dev4005-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$data'";
							} elsif ($ENV_STATE eq "stage"){
								$cmd="curl -X 'POST' 'https://stage-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$data'";
							} elsif ($ENV_STATE eq "production"){
								$cmd="curl -X 'POST' 'https://literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$data'";
							}

							#print "\n$uniquename_p $raw_flag_type\n$data\n";
							#print "\n\n$cmd\n";
							#system($cmd);
		
							$flag=1;
							last;
						}
					} else {
						print "\nwrong curated_by date format for $uniquename_p transaction_timestamp_curated\n";
					}
				}
				if ($flag==0){
					print "\nunable to find who curated for $flag_source $raw_flag_type $uniquename_p";
				}


			} else {

				warn "no ATP mapping for this flag_type:$raw_flag_type from $flag_source";

			}
		}
	}
}#foreach




