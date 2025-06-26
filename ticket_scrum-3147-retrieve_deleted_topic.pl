#!/usr/bin/perl -w
use strict; 
use warnings;
use File::Find;


my %flag_type = (
 'GOcur'=>'cam_flag',#    1393
 'RNAi'=>'harv_flag',#    431
 'cell_cult'=>'harv_flag',#     20
 'cell_cult::DONE'=>'harv_flag',#    612
 'cell_line(commercial)::DONE'=>'harv_flag',#    106
 'cell_line(stable)::DONE'=>'harv_flag',#     31
 'cell_line::DONE'=>'harv_flag',#   1599
 'chemical'=>'harv_flag',#    308
 'chemical::DONE'=>'harv_flag',#   1489
 'cis_reg'=>'harv_flag',#   1501
 'cis_reg::DONE'=>'harv_flag',#     51
 'dataset'=>'harv_flag',#   2272
 'disease'=>'dis_flag',#     901
 'disease::DONE'=>'harv_flag',#   3699
 'disease::Inappropriate use of flag'=>'harv_flag',#    218
 'diseaseF'=>'harv_flag',#    593
 'diseaseF::DONE'=>'harv_flag',#    210
 'diseaseHP::DONE'=>'harv_flag',#    227
    'dm_gen::DONE'=>'dis_flag',#    2729
    'dm_gen'=>'dis_flag',# 
 'dm_other'=>'dis_flag',#     660
 'gene_group'=>'cam_flag',#     450
 'gene_group::DONE'=>'cam_flag',#      68
 'gene_model'=>'harv_flag',#     23
 'gene_model::DONE'=>'harv_flag',#    627
 'gene_model_nonmel'=>'harv_flag',#    125
 'genom_feat'=>'harv_flag',#     63
 'genom_feat::DONE'=>'harv_flag',#   3123
 'genom_feat::No response to author query'=>'arv_flag',#     56
 'marker'=>'harv_flag',#    635
 'merge'=>'cam_flag',#     361
 'neur_exp'=>'harv_flag',#   1140
 'neur_exp::DONE'=>'harv_flag',#    115
 'new_al'=>'cam_flag',#    4326
 'new_char'=>'cam_flag',#    2495
 'new_gene'=>'cam_flag',#     105
 'new_transg'=>'cam_flag',#    9486
 'noDOcur'=>'dis_flag',#   12104
 'noGOcur'=>'cam_flag',#     296
 'no_flag'=>'harv_flag',#  22478
 'nocur'=>'cam_flag',#   10341
 'nocur_abs'=>'cam_flag',#     950
 'novel_anat'=>'onto_flag',#    208
 'novel_anat::DONE'=>'onto_flag',#    540
 'orthologs'=>'cam_flag',#     100
 'pathway'=>'cam_flag',#      94
 'pert_exp'=>'harv_flag',#   8288
 'pert_exp::DONE'=>'harv_flag',#     16
 'pheno'=>'cam_flag',#   13791
 'pheno_anat'=>'cam_flag',#     970
 'pheno_chem'=>'cam_flag',#    2566
 'phys_int'=>'harv_flag',#    254
 'phys_int::DONE'=>'harv_flag',#   5151
 'rename'=>'cam_flag',#    1476
 'split'=>'cam_flag',#      15
 'trans_assay'=>'harv_flag',#     44
 'wt_exp'=>'harv_flag',#   3202
 'wt_exp::DONE'=>'harv_flag',#   4458
 'wt_exp::Inappropriate use of flag'=>'harv_flag',#    964
 'wt_exp::Needs cam curation'=>'harv_flag',#    277
    );


    
my $FBrf_filter='FBrf0256192';
my $FBrf_like='^FBrf[0-9]+$';
find({ wanted => \&parse_flag, no_chdir => 1 }, ("/data/camdata/proforma"));
find({ wanted => \&parse_flag, no_chdir => 1 }, ("/data/harvcur/archive"));





sub parse_flag{
    if (-f $_) {
	my $file=$_;
	my $file_local=$file;
	if ($file=~/\/camdata/ && ($file=~/pl.+bibl/ || $file !~/PHASE/)){
	    #print "\nignore file for new FBrf:$_";
	    return;
	}
        open (IN, $file) or die "unable to open file:$file";
        my $previous_line="";
        my ($FBrf,  $filename, $flag, $flag_full, $flag_site);
        my @temp=split(/\//, $file_local);
        $filename=$temp[$#temp];
	$file=~s/$filename//;
	my $flag_found=0;#for case where new line without ! but previous line find flag
	my $flag_addback=0; #for case where new line without !, but extend from !c, use 'ADD_BACK' instead of ADD
    while (<IN>){
	chomp;
	my $line=$_;
       	if (/P22.*FBrf[0-9]+/){
		my ($junk1, $junk2)=split(/\:/);
		$FBrf=$junk2;
		$FBrf=~s/^\s+//g;#/data/harvcur/archive/2008_02/epicycle5/194414.mr.skim ! P22. Publication FBrf            *U :         FBrf0194414
		$FBrf=~s/\s+$//g;
        }
	#reset $flag_ound=1;
	if ($line =~/^!/){
	    $flag_found=0;
	    $flag_addback=0;
	}
       if (defined $FBrf && $line=~/^!c?\s+P4[0-3]/){
	   #parse the filename, line to get the flag
	   $line=~s/[\(|\[]SoftCV[\)|\]]//g; # /data/camdata/proforma/2008_02/epicycle5/PHASE2/pm890 ! P40. Flag Cambridge for curation      CAMCUR (SoftCV) :nocur
	   # /data/camdata/proforma/2008_08/epicycle1/PHASE1/st629.edit !c P40. Flag Cambridge for curation      CAMCUR [SoftCV] :
	   $line=~s/[\(|\[]y\/n[\)|\]]//g;
	   $line=~s/\r//g; #return  for this: /data/camdata/proforma/2008_07/epicycle3/PHASE6/km19.pro ! P40. Flag Cambridge for curation      CAMCUR (SoftCV) :
	   #my @case=( $line =~ /(!.*P4[0-3]\.)\s+([A-Za-z]+)\s+([A-Za-z]+)\s+([A-Za-z]+)\s+([A-Za-z]+)\s+([CAMCUR|HARVCUR|ONTO|DISEASE]+)\s+:(.+)/ );
	   my @case=( $line =~ /(!.*P4[0-3].*)\s+:(.*)/ );
	   #print "\ncase[0]:$case[0]";
	   if ($#case >-1){
	       #$flag_site=$case[5];
	       #print "\ncase[0]|$case[0]|";
	       
               if ($case[0] =~/[^\t\r\n\x20-\x7E]+/){
	         # print "\nbefore:|$case[0]|";
	          $case[0]=~s/[^\t\r\n\x20-\x7E]+//g;
		  $case[0]=~s/\s+$//g;
	         # print "\nafter :|$case[0]|\n";
	       }
	       
	       my @temp=split(/\s+/, $case[0]);
	       $flag_site=$temp[$#temp];
	       $flag=$case[1];
	       if ($case[0]=~/!c/){#remove and also could add new flag
		   print "\nDELETE\t$FBrf $file\t$filename\t$flag_site\t";
		   if ($case[1] ne ""){
		       print "\nADD_BACK\t$FBrf\t$file\t$filename\t$flag_site\t$flag";
		       $flag_addback=1;
		   }
		  $flag_found=1; 
	       }
	       elsif ($flag ne "" and $flag ne 'y' and $flag ne 'n') {#new flag, #2008_07/epicycle3/PHASE6/km19.pro with .2 'y', 'n' data error, should not be mapped to ATP term - per Gillian
		   print "\nADD\t$FBrf\t$file\t$filename\t$flag_site\t$flag";
		   $flag_found=1;
	       }
		
	   }
	   else {
	       print "\nwrong format:$file_local\n$line\n";
	   }
    	   
		 
	    
	}
        #/data/camdata/proforma/2011_04/epicycle3/PHASE3/as773.user	
        #! P40.  Flag Cambridge for curation           CAMCUR :new_char
        #pheno
	#new_al
	
	#/data/camdata/proforma//2023_05/epicycle7/PHASE4/gm75131.thin
	#!c P41.  Flag Harvard for curation            HARVCUR :dataset
        #genom_feat
        #wt_exp
	#if (defined $FBrf && $line !~/^!/ && $previous_line =~/^!c?\s+P4[0-3]/){#new line for flag data
	if (defined $FBrf && $line !~/^!/ && $flag_found==1){#new line for flag data
	       $flag=$line;
	       #print "\nnew line of flag:$flag";
	       if ($flag_addback==1){
		   print "\nADD_BACK\t$FBrf\t$file\t$filename\t$flag_site\t$flag";
	       }
	       else {
		   print "\nADD\t$FBrf\t$file\t$filename\t$flag_site\t$flag";
	       }
	 }
	 else {
	 }
	$previous_line=$line;    
    }
  }#if (-f $file)
  
}
