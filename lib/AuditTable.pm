package AuditTable;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(get_relevant_curator);


=head1 MODULE: AuditTable

Module containing subroutines that get information from audit_chado table.

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

			}
		} else {
			# not expecting to trip this error
			print "ERROR: wrong curated_by pubprop format for pub_id: $pub_id, pubprop: $curated_by_value\n";
		}


	}

	return ($data);
}
