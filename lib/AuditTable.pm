package AuditTable;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(get_relevant_curator get_flag_info_with_audit_data get_timestamps_for_flag_with_suffix get_timestamps_for_flaglist_with_suffix get_timestamps_for_pubprop_value get_relevant_currec_for_datatype get_matching_pubprop_value_with_timestamps get_all_flag_info_with_timestamps);


=head1 MODULE: AuditTable

Module containing subroutines that get information from chado, including information from the audit_chado table.

=cut


1;

sub get_relevant_curator {

=head1 SUBROUTINE:
=cut

=head1

	Title:    get_relevant_curator
	Usage:    get_relevant_curator(database handle, pub_id of reference, timestamp information to be matched);
	Function: The get_relevant_curator subroutine takes audit_chado table timestamp information to be matched (e.g. timestamp for a particular triage flag) and the pub_id of the relevant reference and tries to find a matching 'curated_by' pubprop for that pub_id (ie. one with the same audit_chado table timestamp). If it finds any matches, it returns a data structure containing the relevant information from all matching 'curated_by' pubprop(s), otherwise it returns undef.
	Example: my ($curator, $file) = &get_relevant_curator($dbh, $pub_id, $flag_audit_timestamp);

	
	For each matching curated_by pubprop it captures the 'Curator:' portion ($curator) and Proforma:' portion ($record_number) of the pubprop value and stores it as follows

	It captures the following information:

	o Count of the number of matching curated_by pubprops:

		$data->{count}++;

	o Count of number of matching curated_by pubprops where the $curator is a FlyBase curator (and not community/UniProt curation)

		$data->{FB_curator_count}++;

	o A $data->{curator} hash structure that captures $curator and $record_number info for all matching pubprops (used when there is more than one matching pubprop)

		$data->{curator}->{$curator}->{$record_number}++;


	o Two 'relevant' shortcut key-value pairs that capture the $curator and $record_number info for the last matching pubprop - **NB: these are only safe to use to if $data->{count} == 1, otherwise need to use the $data->{curator} hash structure**

		$data->{relevant_curator} = $curator;
		$data->{relevant_record} = $record_number;




=cut

	unless (@_ == 3) {

		die "Wrong number of parameters passed to the get_relevant_curator subroutine\n";
	}



	my ($dbh, $pub_id, $audit_timestamp_to_match) = @_;

	my ($relevant_curator , $relevant_record) = '', 

	my $sql_query=sprintf("select distinct pp.value, ac.transaction_timestamp, pp.pubprop_id from  pubprop pp, cvterm c, audit_chado ac  where ac.audited_table='pubprop' and ac.audit_transaction='I' and pp.pubprop_id=ac.record_pkey and pp.pub_id=%s and c.cvterm_id=pp.type_id and c.name in ('curated_by')", $pub_id);

	my $db_query = $dbh->prepare ($sql_query);
	$db_query->execute or die "CAN'T GET curator info FROM CHADO:\n$sql_query\n";

	my $data = undef;

	while (my ($curated_by_value, $curated_by_audit_timestamp, $curated_by_pubprop_id) = $db_query->fetchrow_array()) {

		if ($curated_by_value =~ m/^Curator: (.+?);Proforma: (.+?);timelastmodified: (.*)$/) {

			my $curator = $1;
			my $record_number = $2;
			my $timelastmodified = $3;



			if ($curated_by_audit_timestamp eq $audit_timestamp_to_match){

				### commented out original code that was checking and converting format of 'timelastmodified' part of pubprop as not using this timestamp when submitting data:
				### - using audit_chado timestamp information instead to be consistent with what has been done in alliance-linkml-flybase work
				#my $time_from_curator;
				# well behaved time format: Thu Mar 17 08:24:07 2011
				#if ($timelastmodified =~ m/([A-Za-z]+)\s+([A-Za-z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d+)/) {
					#$time_from_curator= Time::Piece->strptime($timelastmodified, '%a %b %d %H:%M:%S %Y')->ymd("-");
					#$time_from_curator.=" ".$4;
				# incorrect time format that cannot be converted by Time::Piece: Thu 29 Oct 2020 09:13:21 AM EDT
				# have to convert to correct order first, before run through Time::Piece
				#} elsif ($timelastmodified =~ m/([a-zA-Z]+)\s+(\d+)\s+([a-zA-Z]+)\s+(\d+)\s+(\d+:\d+:\d+)\s+([A-Z]+)\s+([A-Z]+)/) {
					#my @temp=split(/\s+/, $timelastmodified);
					#my $time_before=$temp[0]." ".$temp[2]." ".$temp[1]." ".$temp[4]." ".$temp[3];
					#$time_from_curator= Time::Piece->strptime($time_before, '%a %b %d %H:%M:%S %Y')->ymd("-");
					#$time_from_curator.=" ".$temp[4];
				#} else {
					#print "ERROR: weird curated_by time format:$pub_id $curated_by_value\n";
					#next;
				#}
				###

				$relevant_curator = $curator;
				$relevant_record = $record_number;
				$data->{curator}->{$curator}->{$record_number}++;
				$data->{count}++;
				$data->{relevant_curator} = $curator;
				$data->{relevant_record} = $record_number;

				unless ($curator eq 'Author Submission' || $curator eq 'User Submission' || $curator eq 'UniProtKB') {

					$data->{FB_curator_count}++;
				}

				if ($curator eq 'Author Submission' || $curator eq 'User Submission') {

					$data->{community_curation_count}++;

				}

			}
		} else {
			# not expecting to trip this error
			print "ERROR: wrong curated_by pubprop format for pub_id: $pub_id, pubprop: $curated_by_value\n";
		}


	}

	return ($data);
}


sub get_flag_info_with_audit_data {

=head1 SUBROUTINE:
=cut

=head1

	Title:    get_flag_info_with_audit_data
	Usage:    get_flag_info_with_audit_data(database_handle,triage_flag_type, triage_flag);
	Function: Gets all references that are associated with a particular triage flag, returning a hash reference that includes audit_table information.
	Example:  my $phys_int_flags = &get_flag_info_with_audit_data($dbh,'harv_flag','phys_int');

Arguments:

o triage_flag_type must be either 'cam', 'dis', 'harv' or 'onto' (i.e. one of the allowed triage flag types).

The returned hash reference has the following structure:

   $data->{$pub_id}->{$matching_triage_flag}->{$audit_type}->{$audit_timestamp}++;

(The same pubprop can be updated multple times (via chiacur) so need to store timestamp as hash key).

o $pub_id is the pub_id of the reference.

o $matching_triage_flag can be either an exact match to the triage_flag argument (i.e. the 'plain' flag without any :: suffix) or also the triage_flag argument  *with* a :: suffix (which can be relevant for curation status information).

o $audit_type is either 'I' (for insert) or 'U' (for update)

o $audit_timestamp is the timestamp from the audit_chado table.


Note

=cut


	unless (@_ == 3) {

		die "Wrong number of parameters passed to the get_flag_info_with_audit_data subroutine\n";
	}


	my ($dbh, $triage_flag_type, $triage_flag) = @_;


	unless ($triage_flag_type eq 'cam_flag' || $triage_flag_type eq 'harv_flag' || $triage_flag_type eq 'dis_flag' || $triage_flag_type eq 'onto_flag') {

		die "unexpected triage flag type $triage_flag_type (must be one of 'cam_flag', 'harv_flag', 'dis_flag' or 'onto_flag'\n";

	}

	my $data = {};


	my $sql_query = sprintf("select distinct pp.pub_id, pp.value, ac.audit_transaction, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.value ~'^%s(::.*)?$' and c.cvterm_id=pp.type_id  and c.name ='%s' and ac.audited_table='pubprop' and ac.audit_transaction in ('I', 'U')  and pp.pubprop_id=ac.record_pkey order by ac.transaction_timestamp",$triage_flag, $triage_flag_type);
	my $db_query = $dbh->prepare($sql_query);
	$db_query->execute or die "WARNING: ERROR: Unable to execute get_flag_info_with_audit_data query ($!)\n";


	while (my ($pub_id, $matching_triage_flag, $audit_type, $audit_timestamp) = $db_query->fetchrow_array) {

		$data->{$pub_id}->{$matching_triage_flag}->{$audit_type}->{$audit_timestamp}++;

	}


	return $data;

}



sub get_timestamps_for_flag_with_suffix {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_timestamps_for_flag_with_suffix
	Usage:    get_timestamps_for_flag_with_suffix(database_handle,$flag_mapping);
	Function: Gets timestamp information for flags with suffixes (the suffix is appended to the plain flag name after :: in chado), for the flag(s) specified in the $flag_mapping reference in the second argument.
	Example:  my $flag_with_suffix_data = &get_timestamps_for_flag_with_suffix($dbh,$flag_mapping);

Arguments:

o $flag_mapping is a hash reference containing the flag(s) to return data for.

Must be in the form:

$flag_mapping->{flag_type}->{flag}

where:  

o flag_type is any of cam_flag, harv_flag, dis_flag, onto_flag - this defines the type of the pubprop in chado that the corresponding child 'flag' keys are stored under.

o flag is the 'plain' flag name (ie. without suffix) e.g. pheno, phys_int, dm_gen, novel_anat


To make a hash reference to use as the $flag_mapping argument that contains *all* the available flags of *all* flag_types, first use the get_flag_mapping subroutine from the Mappings module.


Returns:

The returned hash reference has the following structure:

   @{$data->{$pub_id}->{$flag_type}->{$plain_flag}->{$suffix}}, $audit_timestamp;


o $pub_id is the pub_id of the reference.

o flag_type is as provided by the $flag_mapping hash, ie. any of cam_flag, harv_flag, dis_flag, onto_flag - the type of the pubprop in chado that the corresponding child 'flag' keys are stored under.

o flag is the plain flag name (without suffix) e.g. pheno, phys_int, dm_gen, novel_anat

o suffix is the string that was after the :: for the particular pub_id+flag pubprop (this is often relevant for curation status information).

o $audit_timestamp is a timestamp from the audit_chado table. The $audit_timestamp values are sorted earliest to latest within the array. It includes timestamps for both 'I' (for insert) or 'U' (for update) audit_transaction, so that timestamps are returned regardless of whether the flag suffix was added directly in a proforma (with or without plingc) - 'I' - or updated direct in chado (e.g. via CHIA) - 'U'.


=cut


	unless (@_ == 2) {

		die "Wrong number of parameters passed to the get_timestamps_for_flag_with_suffix subroutine\n";
	}


	my ($dbh, $flag_mapping) = @_;

	my $data = {};

	foreach my $flag_type (keys %{$flag_mapping}) {

		foreach my $flag (keys %{$flag_mapping->{$flag_type}}) {

			my $sql_query = sprintf("select distinct pp.pub_id, pp.value, ac.audit_transaction, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.value ~'^%s::' and c.cvterm_id=pp.type_id  and c.name ='%s' and ac.audited_table='pubprop' and ac.audit_transaction in ('I', 'U') and pp.pubprop_id=ac.record_pkey order by ac.transaction_timestamp",$flag, $flag_type);
			my $db_query = $dbh->prepare($sql_query);
			$db_query->execute or die "WARNING: ERROR: Unable to execute get_timestamps_for_flag_with_suffix query ($!)\n";


			while (my ($pub_id, $flag_with_suffix, $audit_type, $audit_timestamp) = $db_query->fetchrow_array) {


				my ($plain_flag, $suffix) = ($flag_with_suffix =~ m/^(.+)::(.+)$/);



				push @{$data->{$pub_id}->{$flag_type}->{$plain_flag}->{$suffix}}, $audit_timestamp;

			}
		}

	}

	return $data;

}

sub get_timestamps_for_flaglist_with_suffix {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_timestamps_for_flaglist_with_suffix
	Usage:    get_timestamps_for_flaglist_with_suffix(database_handle,$flag_type, \@flag_list);
	Function: Gets timestamp information for flags with suffixes (the suffix is appended to the plain flag name after :: in chado), for the list of flag(s) specified in the \@flag_list reference in the third argument.
	Example:  my $cell_line_flags_with_suffix = &get_timestamps_for_flaglist_with_suffix($dbh,'harv_flag',\@cell_line_flags);

Arguments:

o $flag_type is the type of pubprop in chado that the list of flags in \@flag_list are stored under (ie. one of cam_flag, harv_flag, dis_flag, onto_flag)

o \@flag_list is an array reference containing the flag(s) to return data for. Each flag in the list must be a 'plain' flag name (ie. without suffix) e.g. pheno, phys_int, dm_gen, novel_anat.



Returns:

The returned hash reference has the following structure:


o $data->{$pub_id}->{$suffix}->{timestamp}

o $data->{$pub_id}->{$suffix}->{flags}


Details:

o $pub_id is the pub_id of the reference.

o $suffix is the string that was after the :: for the particular $pub_id+$flag pubprop (this is often relevant for curation status information). 


o data->{$pub_id}->{$suffix}->{timestamp}

  o This reference holds an array containing all the timestamp(s) from the audit_chado table for the corresponding suffix.

  o The timestamp values are sorted earliest to latest within the array.

  o It includes timestamps for both 'I' (for insert) or 'U' (for update) audit_transaction, so that timestamps are returned regardless of whether the flag suffix was added directly in a proforma (with or without plingc) - 'I' - or updated direct in chado (e.g. via CHIA) - 'U'.

o $data->{$pub_id}->{$suffix}->{flags}

    o this reference holds a hash containing the flag(s) that have the corresponding $suffix.



=cut


	unless (@_ == 3) {

		die "Wrong number of parameters passed to the get_timestamps_for_flaglist_with_suffix subroutine\n";
	}


	my ($dbh, $flag_type, $flag_list) = @_;

	unless ($flag_type eq 'cam_flag' || $flag_type eq 'harv_flag' || $flag_type eq 'dis_flag' || $flag_type eq 'onto_flag') {

		die "unexpected triage flag type $flag_type (must be one of 'cam_flag', 'harv_flag', 'dis_flag' or 'onto_flag'\n";

	}


	my $data = {};

	foreach my $flag (@{$flag_list}) {


		my $sql_query = sprintf("select distinct pp.pub_id, pp.value, ac.audit_transaction, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.value ~'^%s::' and c.cvterm_id=pp.type_id  and c.name ='%s' and ac.audited_table='pubprop' and ac.audit_transaction in ('I', 'U') and pp.pubprop_id=ac.record_pkey order by ac.transaction_timestamp",$flag, $flag_type);
		my $db_query = $dbh->prepare($sql_query);
		$db_query->execute or die "WARNING: ERROR: Unable to execute get_timestamps_for_flaglist_with_suffix query ($!)\n";



		while (my ($pub_id, $flag_with_suffix, $audit_type, $audit_timestamp) = $db_query->fetchrow_array) {

			my ($plain_flag, $suffix) = ($flag_with_suffix =~ m/^(.+)::(.+)$/);
			push @{$data->{$pub_id}->{$suffix}->{timestamp}}, $audit_timestamp;
			$data->{$pub_id}->{$suffix}->{flags}->{$flag}++;
		}

	}

	return $data;

}

sub get_timestamps_for_pubprop_value {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_timestamps_for_pubprop_value
	Usage:    get_timestamps_for_pubprop_value(database_handle,$pubprop_type,$string);
	Function: Gets timestamp information for a pubprop of the type given in the second argument with a value that contains the string given in the third argument.
	Example:  my $phys_int_not_curated = &get_timestamps_for_pubprop_value($dbh,'internalnotes','phys_int not curated');

Arguments:

o $pubprop_type - the pubprop type you are interested in.

o $string - the string that you want the pubprops to contain. The search will find this string anywhere in the pubprop value and it may be all or part of the value.



Returns:

The returned hash reference has the following structure:

@{$data->{$pub_id}}, $audit_timestamp;


o $pub_id is the pub_id of the reference.

o $audit_timestamp is the 'I' timestamp(s) from the audit_chado table for matching pubprops (contain $string) of the specified $pubprop_type. The $audit_timestamp values are sorted earliest to latest within the array.


=cut


	unless (@_ == 3) {

		die "Wrong number of parameters passed to the get_timestamps_for_pubprop_value subroutine\n";
	}


	my ($dbh, $pubprop_type, $string) = @_;


	my $data = {};



	my $sql_query = sprintf("select distinct pp.pub_id, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.value ~'%s' and c.cvterm_id=pp.type_id  and c.name ='%s' and ac.audited_table='pubprop' and ac.audit_transaction = 'I' and pp.pubprop_id=ac.record_pkey order by ac.transaction_timestamp",$string, $pubprop_type);
	my $db_query = $dbh->prepare($sql_query);
	$db_query->execute or die "WARNING: ERROR: Unable to execute get_timestamps_for_pubprop_value query ($!)\n";


	while (my ($pub_id, $audit_timestamp) = $db_query->fetchrow_array) {

		push @{$data->{$pub_id}}, $audit_timestamp;

	}

	return $data;

}



sub get_relevant_currec_for_datatype {



=head1 SUBROUTINE:
=cut

=head1

	Title:    get_relevant_currec_for_datatype
	Usage:    get_relevant_currec_for_datatype(database_handle,datatype);
	Function: Gets timestamp information for curation records that are expected to contain data of a particular type based on the their filename, for the datatype specified in the second argument.
	Example:  my $currec_for_cell_line = &get_relevant_currec_for_datatype($dbh,'cell_line');

Arguments:

=cut


	unless (@_ == 2) {

		die "Wrong number of parameters passed to the get_relevant_currec_for_datatype subroutine\n";
	}

	my ($dbh, $datatype) = @_;

	# only use standard filenames for matching so that can be sure that curation of the datatype is complete
	my $datatype_mapping = {

		'cell_line' => '.+?\.(cell|cell_multiple|cell_multi)\..+?',
		'phys_int' => '.+?\.(int|int_miRNA)\..+?',
		'DO' => '.+?\.DO\..+?',
		'neur_exp' => '.+?\.vfb\.exp.+?',
		'wt_exp' => '.+?\.(exp|fex)\..+?',
		'chemical' => '.+?\.chem\..+?',
		'args' => '.+?\.args\..+?',
		'phen' => '[a-z][a-z][0-9]{1,}\.phen',
		'cam_full' => '(ma|sb|rd|sf|tj|al|sm|cm|pm|gm|ao|cp|lp|sp|sr|rs|ra|ds|ew|cy)[0-9]{1,}(\.(h|hf))?',



	};

	unless (exists $datatype_mapping->{$datatype}) {

		die "get_relevant_currec_for_datatype: The datatype given as the second argument ($datatype) is not in the subroutine \$datatype_mapping hash: cannot process this datatype until the correct regex is added\n";

	}
	my $data_by_timestamp = {};
	my $data_by_curator = {};

	my $sql_query=sprintf("select distinct pp.pub_id, pp.value, ac.transaction_timestamp, pp.pubprop_id from  pubprop pp, cvterm c, audit_chado ac where ac.audited_table='pubprop' and ac.audit_transaction='I' and pp.pubprop_id=ac.record_pkey and c.cvterm_id=pp.type_id and c.name = 'curated_by' and pp.value ~'Proforma: %s;timelastmodified' order by ac.transaction_timestamp", $datatype_mapping->{$datatype});

	my $db_query = $dbh->prepare($sql_query);
	$db_query->execute or die "WARNING: ERROR: Unable to execute get_relevant_currec_for_datatype query ($!)\n";


	while (my ($pub_id, $curated_by_value, $curated_by_audit_timestamp, $curated_by_pubprop_id) = $db_query->fetchrow_array) {


		if ($curated_by_value =~ m/^Curator: (.+?);Proforma: (.+?);timelastmodified: (.*)$/) {

			my $curator = $1;
			my $record_number = $2;
			my $timelastmodified = $3;
			my $exclude_switch = 0;

			# exclude edit records as this is by definition partial curation
			if ($record_number =~ m/edit/) {
				$exclude_switch++;
			}

			# for records corresponding to wt_exp datatype, exclude vfb records as those correspond to the more specific neur_exp datatype
			if ($datatype eq 'wt_exp') {
				if ($record_number =~ m/vfb/) {
					$exclude_switch++;
				}
			}


			unless ($exclude_switch) {

				push @{$data_by_timestamp->{$pub_id}}, $curated_by_audit_timestamp;
				$data_by_curator->{$pub_id}->{$curator}->{$curated_by_audit_timestamp}->{$record_number}++;
			}

		} else {
			# not expecting to trip this error
			print "ERROR: wrong curated_by pubprop format for pub_id: $pub_id, pubprop: $curated_by_value\n";
		}
	}

	return ($data_by_timestamp, $data_by_curator);
}


sub get_matching_pubprop_value_with_timestamps {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_matching_pubprop_value_with_timestamps
	Usage:    get_matching_pubprop_value_with_timestamps(database_handle,$pubprop_type,$string);
	Function: Gets pubprop information of the type given in the second argument with a value that contains the string given in the third argument; returns the pubprop value(s) and timestamps.
	Example:  my $phys_int_internal_notes = &get_matching_pubprop_value_with_timestamps($dbh,'internalnotes','phys_int not curated');

Arguments:

o $pubprop_type - the pubprop type you are interested in.

o $string - the string that you want the pubprops to contain. The search will find this string anywhere in the pubprop value and it may be all or part of the value.



Returns:

The returned hash reference has the following structure:

@{$data->{$pub_id}->{$line}}, $audit_timestamp;


o $pub_id is the pub_id of the reference.

o $line is the value of any single line from the pubprop of the type you are interested in that contains the string you are interested in. If the pubprop contains multiple lines that is separated by returns (e.g. this is common for internalnotes), the pubprop is first split into separate lines, and only those lines that contain the string are stored.

o $audit_timestamp is the 'I' timestamp(s) from the audit_chado table for the matching $line. The $audit_timestamp values are sorted earliest to latest within the array.


=cut


	unless (@_ == 3) {

		die "Wrong number of parameters passed to the get_matching_pubprop_value_with_timestamps subroutine\n";
	}


	my ($dbh, $pubprop_type, $string) = @_;

	my $data = {};



	my $sql_query = sprintf("select distinct pp.pub_id, pp.value, ac.transaction_timestamp from pubprop pp, cvterm c, audit_chado ac where pp.value ~'%s' and c.cvterm_id=pp.type_id  and c.name ='%s' and ac.audited_table='pubprop' and ac.audit_transaction = 'I' and pp.pubprop_id=ac.record_pkey order by ac.transaction_timestamp",$string, $pubprop_type);
	my $db_query = $dbh->prepare($sql_query);
	$db_query->execute or die "WARNING: ERROR: Unable to execute get_timestamps_for_pubprop_value query ($!)\n";


	while (my ($pub_id, $value, $audit_timestamp) = $db_query->fetchrow_array) {

		my @lines = split /\n/m, $value;

		foreach my $line (@lines) {
			if ($line =~ m/$string/) {
				push @{$data->{$pub_id}->{$line}}, $audit_timestamp;

			}

		}

	}

	return $data;

}



sub get_all_flag_info_with_timestamps {


=head1 SUBROUTINE:
=cut

=head1

	Title:    get_all_flag_info_with_timestamps
	Usage:    get_all_flag_info_with_timestamps(database_handle);
	Function: Gets triage flag and timestamp information for all triage flags.
	Example:  my $flag_info = &get_all_flag_info_with_timestamps($dbh);



Returns:

The returned hash reference has the following structure:

   @{$data->{$pub_id}->{$flag_type}->{$plain_flag}->{$suffix}->{$audit_transaction_type}, $audit_timestamp;


o $pub_id is the pub_id of the reference.

o $flag_type is one of cam_flag, harv_flag, dis_flag, onto_flag - the type of the pubprop in chado that the corresponding child 'flag' keys are stored under.

o $plain_flag is the plain flag name (without suffix) e.g. pheno, phys_int, dm_gen, novel_anat

o $suffix is either the string that was after :: in the original flag in chado, or 'NO_SUFFIX' if the flag in chado had no suffix.


o $audit_transaction_type is either 'I' (for insert) of 'U' (for update) - from the audit_transaction entry in chado.

o $audit_timestamp is a timestamp from the audit_chado table. The $audit_timestamp values are sorted earliest to latest within the array.


=cut


	unless (@_ == 1) {

		die "Wrong number of parameters passed to the get_all_flag_info_with_timestamps subroutine\n";
	}


	my ($dbh) = @_;

	my @flag_types = ('cam_flag', 'harv_flag', 'dis_flag', 'onto_flag');



	my $data = {};


	foreach my $flag_type (@flag_types) {

		my $sql_query = sprintf("select distinct pp.pub_id, pp.value, ac.audit_transaction, ac.transaction_timestamp, ac.audit_transaction from pubprop pp, cvterm c, audit_chado ac where c.name ='%s' and c.cvterm_id=pp.type_id and ac.audited_table='pubprop' and ac.audit_transaction in ('I', 'U') and pp.pubprop_id=ac.record_pkey order by ac.transaction_timestamp",$flag_type);
		my $db_query = $dbh->prepare($sql_query);
		$db_query->execute or die "WARNING: ERROR: Unable to execute get_all_flag_info_with_timestamps query ($!)\n";


		while (my ($pub_id, $raw_flag, $audit_type, $audit_timestamp, $audit_transaction) = $db_query->fetchrow_array) {


			my $plain_flag = '';
			my $suffix = '';

			if ($raw_flag =~ m/^(.+)::(.+)$/) {

				$plain_flag = $1;
				$suffix = $2;	

			} else {

				$plain_flag = $raw_flag;
				$suffix = 'NO_SUFFIX';

			}

		
			push @{$data->{$pub_id}->{$flag_type}->{$plain_flag}->{$suffix}->{$audit_transaction}}, $audit_timestamp;

		}

	}
	return $data;

}
