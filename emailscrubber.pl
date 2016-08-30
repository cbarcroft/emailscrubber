#!/usr/bin/perl

# Strict and warnings are recommended.
use strict;
use warnings;

my $start_run = time();

# Imports
use Text::CSV;
use Scalar::Util qw(looks_like_number);
use Email::Valid;
use Time::Piece;

our %counters = (
	"duplicates" => 0,
    "rejected"  => 0,
    "accepted" => 0
);

# Set up input file
my $csv = Text::CSV->new({ sep_char => ',', eol => $/, binary => 1 });
my $file = $ARGV[0] or die "Provide CSV file as second argument. \n";
our $file_unique = remove_duplicates($file);
open(our $data, '<', $file_unique) or die "Could not open '$file_unique' $!\n";

# Set up output files
our $accepted_output_filename = build_output_filename("accepted_emails");
our $rejected_output_filename = build_output_filename("rejected_emails");
open(our $accepted_outfile, '>:encoding(utf8)', $accepted_output_filename) or die "Could not open accepted output file $!\n";
open(our $rejected_outfile, '>:encoding(utf8)', $rejected_output_filename) or die "Could not open rejected output file $!\n";

our @blacklist = read_blacklist();

while (my $line = <$data>) {
  if ($csv->parse($line)) {
 
      my @fields = $csv->fields();
      my $customer_code = $fields[0];
      my $full_email = $fields[1];
      my $year = $fields[2];
      my ($email_userinitial, $email_domaininitial) = (split /@/, $full_email)[0,1];
      my $email_user = lc $email_userinitial;
      my $email_domain = lc $email_domaininitial;

      # *** BEGIN RULE CHECKS **

      # Reject if email is not a valid email address
      if ( is_invalid_email_address($full_email) ){
      	reject_email($full_email, $customer_code, $year, "Invalid email address");
      	next;
      }

      # Reject if email user is only numbers
      if ( is_numeric_only($email_user) ){
      	reject_email($full_email, $customer_code, $year, "Only numeric");
      	next;
      }

      # Reject if email user is too short (second argument is the minimum character length)
      if ( is_too_short($email_user, 3) ){
      	reject_email($full_email, $customer_code, $year, "Too short");
      	next;
      }

      # Reject if email user is present in the blacklist at config/blacklist.csv
      if ( is_blacklisted($email_user) ){
      	reject_email($full_email, $customer_code, $year, "Email User Blacklisted");
      	next;
      }

      # Reject if email domain is present in the blacklist at config/blacklist.csv
      if ( is_blacklisted($email_domain) ){
      	reject_email($full_email, $customer_code, $year, "Email Domain Blacklisted");
      	next;
      }
      
      # If we get this far, then nothing is wrong - output email to accepted file.
      accept_email($full_email, $customer_code, $year)

 
  } else {
      warn "Line could not be parsed: $line\n";
  }
}

cleanup();

my $end_run = time();
my $run_time = $end_run - $start_run;

printf("\nScrubbing completed in %i seconds. \n  %i duplicates removed. \n  %i rejected into %s \n  %i accepted into %s \n\n", $run_time, $counters{duplicates}, $counters{rejected}, $rejected_output_filename, $counters{accepted}, $accepted_output_filename); 

#
sub is_invalid_email_address {
	my $email = shift;
	return !Email::Valid->address($email);
}

sub is_numeric_only {
	my $email_user = shift;
	return looks_like_number($email_user);
}

sub is_too_short {
	my $email_user = shift;
	my $minimum_character_count = shift;
	return ( length($email_user) < $minimum_character_count );
}

sub is_blacklisted {
	my $email_user = shift;

	return ( $email_user ~~ @blacklist );
}


sub remove_duplicates(\@){
	my $origfile = shift; 
	my $outfile  = "tmp/uniq_" . $origfile;
	my %hTmp;
	 
	open (IN, "<$origfile")  or die "Couldn't open input file: $!"; 
	open (OUT, ">$outfile") or die "Couldn't open output file: $!"; 
	 
	while (my $sLine = <IN>) {
		if ($hTmp{$sLine}++) {
			$counters{duplicates}++;
		} else {
			print OUT $sLine;
		}
	}
	close OUT;
	close IN;

	return $outfile
 }

sub reject_email {
	my $email = shift;
	my $customer_code = shift;
	my $year = shift;
	my $reason = shift;

	print "REJECTED " . $email . " $reason \n";
	$csv->print($rejected_outfile, [$email, $customer_code, $year, $reason]);
	$counters{rejected}++; 
}

sub accept_email {
	my $email = shift;
	my $customer_code = shift;
	my $year = shift;

	print "ACCEPTED " . $email . "\n";
	$csv->print($accepted_outfile, [$email, $customer_code, $year]);
	$counters{accepted}++;  
}

sub read_blacklist {
	my $blacklist_file = 'config/blacklist.csv';
	open my $info, $blacklist_file or die "Could not open blacklist config file $file: $!";

	my @blacklist = ();
	while( my $line = <$info>)  {
		$line =~ s/\s+//g;  
	    push @blacklist, $line;    
	}

	close $info;

	return @blacklist;
}

sub build_output_filename {
	my $file_designator = shift;
	my $timestamp = localtime->strftime('%Y-%m-%d-%H%M%S');

	return sprintf("output/%s_%s.csv", $timestamp, $file_designator);
}

sub cleanup {
	close $rejected_outfile;
	close $accepted_outfile;
	close $data;

	unlink $file_unique;
}