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
=cut


if (@ARGV != 5) {
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|stage|production\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|stage|production\n\n";
    exit;
}

my $server = shift(@ARGV);
my $db = shift(@ARGV);
my $user = shift(@ARGV);
my $pwd = shift(@ARGV);
my $ENV_STATE = shift(@ARGV);

my @STATE = ("dev", "test", "stage", "production");
if (! grep( /^$ENV_STATE$/, @STATE ) ) {
    warn "\n USAGE: $0 pg_server db_name pg_username pg_password dev|test|stage|production\n\n";
    warn "\teg: $0 flysql24 production_chado zhou pwd dev|test|stage|production\n\n";
    exit;
}

my $dsource = sprintf("dbi:Pg:dbname=%s;host=%s;port=5432",$db,$server);
my $dbh = DBI->connect($dsource,$user,$pwd) or die "cannot connect to $dsource\n";

my $FBgn_like='^FBgn[0-9]+$';
my $FBtr_like='^FBtr[0-9]+$';
my $FBpp_like='^FBpp[0-9]+$';
my $FBrf_like='^FBrf[0-9]+$';
my $FBal_like='^FBal[0-9]+$';
my $FBog_like='^FBog[0-9]+$';
my $XR_like='%-XR';
my $XP_like='%-XP';
my $symbol_like='%@%@%';
     my $cvterm_gene='gene';
     my $cv_so='SO';

#updated 20250612, see https://flybase.atlassian.net/browse/FTA-47
my %flag_ATP=(
'GOcur'=>'ATP:0000012',# GO (gene ontology)                                  | cam_flag  |  1393
 'gene_group'=>'ATP:0000065',#                              | cam_flag  |   449
 'gene_group::DONE'=>'ATP:0000065',#                        | cam_flag  |    68
 #'merge'=>'',#                                   | cam_flag  |   360
 'new_al'=>'ATP:0000006',# allele                                 | cam_flag  |  4306
 'new_char'=>'ATP:0000142',# entity, NOT SURE                              | cam_flag  |  2489
 'new_gene'=>'ATP:0000045',#NOT SURE                                | cam_flag  |   105
 'new_transg'=>'ATP:0000013',#  new transgenic construct               | cam_flag  |  9443
 'noGOcur'=>'ATP:0000012',#                                 | cam_flag  |   296
 #'nocur'=>'',#                                   | cam_flag  | 10332
 #'nocur_abs'=>'',#                               | cam_flag  |   946
 #'orthologs'=>'',#                               | cam_flag  |   100    N/A
 'pathway'=>'ATP:0000113',#                                 | cam_flag  |    92
# changed pheno mapping to more specific ATP term (genetic phenotype)
 'pheno'=>'ATP:0000079',# phenotype                                 | cam_flag  | 13754
 'pheno_anat'=>'ATP:0000032',#                              | cam_flag  |   968
 'pheno_chem'=>'ATP:0000080',#                              | cam_flag  |  2558
 'rename'=>'ATP:0000048',#                                  | cam_flag  |  1474
 #'split'=>'',#                                   | cam_flag  |    15
 #'RNAi'=>'ATP:0000082',#                                   | harv_flag |   431
 'cell_cult'=>'ATP:0000008',#                               | harv_flag |    20
 'cell_cult::DONE'=>'ATP:0000008',#                         | harv_flag |   612
 #'cell_line(commercial)::DONE'=>'ATP:0000008',#             | harv_flag |   101
 #'cell_line(stable)::DONE'=>'ATP:0000008',#                 | harv_flag |    31
 'cell_line::DONE'=>'ATP:0000008',#                         | harv_flag |  1556
 'chemical'=>'ATP:0000094',#                                | harv_flag |   300
 'chemical::DONE'=>'ATP:0000094',#                          | harv_flag |  1384
 'cis_reg'=>'ATP:0000055',#                                 | harv_flag |  1499
 'cis_reg::DONE'=>'ATP:0000055',#                           | harv_flag |    51
 'dataset'=>'ATP:0000150',#                                 | harv_flag |  2264
 'disease'=>'ATP:0000152',#                                 | harv_flag |    23
 'disease::DONE'=>'ATP:0000152',#                           | harv_flag |  3642
 #'disease::Inappropriate use of flag'=>'',#      | harv_flag |   215                  ???
 #'diseaseF'=>'',#                                | harv_flag |   593
 #'diseaseF::DONE'=>'',#                          | harv_flag |   210
 #'diseaseHP::DONE'=>'',#                         | harv_flag |   225
 'gene_model'=>'ATP:0000054',#                              | harv_flag |    23
 'gene_model::DONE'=>'ATP:0000054',#                        | harv_flag |   624
 #'gene_model_nonmel'=>'',#                       | harv_flag |   125              N/A
 'genom_feat'=>'ATP:0000056',#                              | harv_flag |    59
 'genom_feat::DONE'=>'ATP:0000056',#                        | harv_flag |  3105
 #'genom_feat::No response to author query'=>'',# | harv_flag |    56
 #'marker'=>'',#                                  | harv_flag |   635
 #'n'=>'',#                                       | harv_flag |   121    N/A
 #'neur_exp'=>'',#                                | harv_flag |  1136
 #'neur_exp::DONE'=>'',#                          | harv_flag |   115
 #'no_flag'=>'',#                                 | harv_flag | 22412
 'pert_exp'=>'ATP:0000042',#                                | harv_flag |  8287
 'pert_exp::DONE'=>'ATP:0000042',#                          | harv_flag |    16
 'phys_int'=>'ATP:0000069',#                               | harv_flag |   252
 'phys_int::DONE'=>'ATP:0000069',#                          | harv_flag |  5131
 #'trans_assay'=>'',#                             | harv_flag |    44            N/A
 'wt_exp'=>'ATP:0000041',#gene expression in wild type     | harv_flag |  3186
 'wt_exp::DONE'=>'ATP:0000041',#gene expression in wild type  | harv_flag |  4449
 #'wt_exp::Inappropriate use of flag'=>'',#       | harv_flag |   963
'wt_exp::Needs cam curation'=>'ATP:0000041',#gene expression in wild type    | harv_flag |   277
 #'y'=>'',#                                     | harv_flag |    56   N/A
    'disease'=>'ATP:0000011',#                                 | dis_flag  |   899
    'diseaseHP'=>'ATP:0000152',#                                 | dis_flag  | ?
 'dm_gen'=>'ATP:0000151',#                            | dis_flag  |
 'dm_gen::DONE'=>'ATP:0000151',#                            | dis_flag  |  2726
 'dm_other'=>'ATP:0000040',#                                | dis_flag  |   659
 'noDOcur'=>'ATP:0000152',#                                 | dis_flag  | 12086                   ???
 'novel_anat'=>'ATP:0000031',#                              | onto_flag |   212
    'novel_anat::DONE'=>'ATP:0000031',#                        | onto_flag |   538
    
 'gene'=>'ATP:0000005',   #entity ATP ?
 'allele'=>'ATP:0000006', #entity ATP ?
 
 
    );


my %FBgn_type; #key:FBgn, value: transcript type

#read the mapping of FBrf vs alliance curie, which generate from: select cr.curie, r.curie from reference r, cross_reference cr where r.reference_id=cr.reference_id and curie_prefix='FB' ;
my %FB_curie;

unless ($ENV_STATE eq "dev") {

	open (IN, 'ticket_scrum-3147-FB_curie20250612.txt') or die 'unable to open file ticket_scrum-3147-FB_curie.txt';
	while (<IN>){
   	 chomp;
    	my ($junk, $FB, $curie)=split(/\s+/);
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

my $species='NCBITaxon:7214';
my %topic_entity_tag_source_hash;
$topic_entity_tag_source_hash{"users"}{"test"}=222;
$topic_entity_tag_source_hash{"users"}{"stage"}=222;
$topic_entity_tag_source_hash{"users"}{"production"}=171;

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

my $okta_token='';

print "\nEntity\tEntity_type_ATP\tEntity_source\tFBrf\tFlag_type\tCurator\tTime_from_curator\tTime_from_audit_chado";
foreach my $uniquename_p (keys %FBrf_pubid){
    
    my $pubid=$FBrf_pubid{$uniquename_p};
    #print "\nuniquename_p:$uniquename_p:pubid:$pubid:";
  my $sql=sprintf("select  c.name, pp.value, pp.pub_id, ac.audit_transaction, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.pub_id=%s and c.cvterm_id=pp.type_id  and c.name in ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag')  and ac.audited_table='pubprop' and ac.audit_transaction='I'  and pp.pubprop_id=ac.record_pkey",$pubid );

  #print "\n$sql\n\n";
  my $flag = $dbh->prepare  ($sql);
  $flag->execute or die" CAN'T GET flag FROM CHADO:\n$sql\n";
  my ($symbol_g, $uniquename, $fpid, $value, $fbrf);

  my ($flag_source,$flag_type, $pub_id, $transaction_type, $transaction_timestamp, $transaction_timestamp_curated, $transaction_timestamp_audit, $pubprop_id);
  while (($flag_source,$flag_type, $pub_id, $transaction_type, $transaction_timestamp ) = $flag->fetchrow_array()) {
    
    my @temp0=split(/\s+/, $transaction_timestamp);
    my $time_flag=$temp0[0];
    #print "\n$flag_source,$flag_type,$transaction_timestamp time_flag:$time_flag\n";
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
            #print "\n$uniquename_p $flag_type $transaction_timestamp_curated time:$time:";
	    #expect date format:Thu Jan 17 07:47:53 2008
	    #wrong date format cause error: FBrf0072646 nocur Curator: B. Matthews;Proforma: 72646.bev.chem.200617;timelastmodified: Thu 29 Oct 2020 09:13:21 AM EDT

	    my @case_time=($time =~/([A-Za-z]+)\s+([A-Za-z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d+)/); #Thu Mar 17 08:24:07 2011
	    my @case_time1=($time =~/([a-zA-Z]+)\s+(\d+)\s+([a-zA-Z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+([A-Z]+)\s+([A-Z]+)/);#Thu 29 Oct 2020 09:13:21 AM EDT
	    
	    my $time_curated;
	    if ($#case_time>-1){
		$time_curated= Time::Piece->strptime($time, '%a %b %d %H:%M:%S %Y')->ymd("-");#Thu Mar 17 08:24:07 2011
	    }
	    elsif ($#case_time1>-1) {#Thu 29 Oct 2020 09:13:21 AM EDT
		print "\nwrong format:$uniquename_p $flag_type $transaction_timestamp_curated time:$time:";
                Time::Piece->strptime($time, '%a %d %b %Y %H:%M:%S %Y %c %e')->ymd("-");
		next;
	    }
	    else {
	        print "\nweird format:$uniquename_p $flag_type $transaction_timestamp_curated time:$time:";
		next;
	    }

=cut
            #here we use the audti_chado timestamp as 'curated' time to figure out who curate the flag
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
	        }
	        elsif ($#case_time1>-1) {#Thu 29 Oct 2020 09:13:21 AM EDT
	  	    my @temp=split(/\s+/, $time);
                    my $time_before=$temp[0]." ".$temp[2]." ".$temp[1]." ".$temp[4]." ".$temp[3];
                    $time_from_curator= Time::Piece->strptime($time_before, '%a %b %d %H:%M:%S %Y')->ymd("-");
		    $time_from_curator.=" ".$temp[4];
	       }
	       else {
	          print "\nweird format:$uniquename_p $flag_type $transaction_timestamp_curated time:$time:";
		  next;
	       }

		#here to check if link to any entity (allele, gene etc) with same ac.transaction_timestamp
		my $sql_entity=sprintf("select distinct f.uniquename, c.name  from feature f, cvterm c,  feature_pub fp, pubprop pp, audit_chado ac  where ac.audited_table='feature_pub' and ac.audit_transaction='I' and fp.feature_pub_id=ac.record_pkey and f.feature_id=fp.feature_id and fp.pub_id=pp.pub_id and pp.pubprop_id=%s and c.cvterm_id=f.type_id ", $pubprop_id);
		#print "\n$sql_entity";
		my $FBrf_with_prefix="FB:".$uniquename_p;
		my $topic=$flag_ATP{$flag_type};
		my $flag_entity=0;
=header		

		# this section was for working on adding entities (genes, alleles etc.) which is no longer being done by this script
		my $entity='alliance';
		my ($entity_type, $entity_type_ATP);
		my ($FBid);
                my $entity_q = $dbh->prepare  ($sql_entity);
                $entity_q->execute or die" CAN'T GET entity info FROM CHADO:\n$sql_entity\n";
		while (($FBid, $entity_type) = $entity_q->fetchrow_array()) {
                    $entity="FB:".$FBid;
		    $entity_type_ATP=$flag_ATP{$entity_type};
		    if (!(defined $entity_type_ATP)){
			$entity_type_ATP='ATP_for_'.$entity_type;
		    }
		    print "\n$entity\t$entity_type_ATP\t$entity_source\t$uniquename_p\t$flag_type\t$curator\t$time_from_curator\t$time_curated";
		    $flag_entity=0;
		}
=cut
		print "\n$uniquename_p\t$flag_source\t$flag_type\t$curator\t$file\t$time_from_curator\t$time_curated";
		if (!(exists $flag_ATP{$flag_type})){
		    warn "\nno ATP for this flag_type:$flag_type from $flag_source";
		    next;
		}
		my $negated='false';
		if ($flag_type eq 'noDOcur'){
		    $negated='true';
		}
		#choose different topic_entity_tag_source_id based on ENV_STATE and 'crated_by' value
		if ($curator eq "Author Submission" || $curator eq "User Submission"){
                    $topic_entity_tag_source_id =$topic_entity_tag_source_hash{"users"}{$ENV_STATE};
                }
                else {
                    $topic_entity_tag_source_id =$topic_entity_tag_source_hash{"curators"}{$ENV_STATE};
                }

		my $data = '';
		unless ($ENV_STATE eq "dev") {
			$data='{"date_created": "'.$time_from_curator.'","created_by": "'.$curator.'", "topic": "'.$topic.'", "species": "'.$species.'","topic_entity_tag_source_id": '.$topic_entity_tag_source_id.', "negated": '.$negated.', "reference_curie": "'.$FB_curie{$FBrf_with_prefix}.'"}';

		} else {

			$data='{"date_created": "'.$time_from_curator.'","created_by": "'.$curator.'", "topic": "'.$topic.'", "species": "'.$species.'","topic_entity_tag_source_id": '.$topic_entity_tag_source_id.', "negated": '.$negated.', "reference_curie": "'. $FBrf_with_prefix .'"}';
			print "\n$data";


		}
		my $cmd;
		if ($ENV_STATE eq "test"){
		    $cmd="curl -X 'POST' 'https://dev4005-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$data'";
		}
		elsif ($ENV_STATE eq "stage"){
		    $cmd="curl -X 'POST' 'https://stage-literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$data'";
		}
		elsif ($ENV_STATE eq "production"){
		    $cmd="curl -X 'POST' 'https://literature-rest.alliancegenome.org/topic_entity_tag/'  -H 'accept: application/json'  -H 'Authorization: Bearer $okta_token' -H 'Content-Type: application/json'  -d '$data'";
		}
		if ($flag_entity==0){#no entity
		  #  print "\nN/A\tN/A\tN/A\t$uniquename_p\t$flag_type\t$curator\t$time_from_curator\t$time_curated";
		}
		print "\n$uniquename_p $flag_type\n$data\n";
		#print "\n\n$cmd\n";
		#system($cmd);
		
		$flag=1;
		last;
	    }
	}
	else {
	    print "\nwrong curated_by date format for $uniquename_p transaction_timestamp_curated\n";
	}
    }
    if ($flag==0){
	print "\nunable to find who curated for $flag_source $flag_type $uniquename_p";
    }
  }
}#foreach




