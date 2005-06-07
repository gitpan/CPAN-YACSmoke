#!/usr/bin/perl -w
use strict;

=head1 NAME

yacsmoke - a Yet Another CPAN Smoke script.

=head1 SYNOPSIS

  perl yacsmoke.pl [-t|--test <distribution>] 
				   [-l|--list <list_from>:<param_name>=<param_value>]
				   [-a|--audit <audit file>]
				   [-c|--config <configuration file>]
                   [-d|--database <database file>]
				   [-h|--help]

  Further CPANPLUS or CPAN::YACSmoke configuration settings should be 
  implemented using a configuration file.

=head1 DESCRIPTION

Runs CPAN Smoke tests on the given set of distributions.

=head1 OPTIONS

There are several options available to the user, all of which are optional.
The script will use defaults if no options are given. The default set of
options are:

  perl yacsmoke.pl -l=Recent

=head2 Single Test (-t|--test)

If a specific distribution is required to be tested, passing the distribution
name and version can be done using the -t option:

  perl yacsmoke.pl -t=My-Distro-0.01

This will override any -l settings passed on the command line.

=head2 Multiple Tests (-l|--list)

To test a list of distributions, using one of the plugins, the -l option is 
used:

  perl yacsmoke.pl -l=Recent

If any arguments for the plugin are required, then these are passed as:

  perl yacsmoke.pl -l=Recent:recent_list_age=1

=head2 Audit File (-a|--audit)

Path to the audit file.

=head2 Configuration File (-c|--config)

Path to the configuration file.

=head2 Database File (-d|--database)

Path to the database file.

=head2 Help (-h|--help)

Prints the help screen.

=cut

our $VERSION = '0.03_06';

use lib qw(lib);

use CPAN::YACSmoke;
use Getopt::Long;

my %conf  = (
	list_from	=> 'Recent',		# use Recent plugin
#	audit_log	=> 'audit.log',
#	config_file	=> 'cpansmoke.ini',
	cpantest    => 1,
);

our ($opt_t, $opt_l, $opt_a, $opt_c, $opt_d, $opt_h);
GetOptions(	
	'test|t=s'		=> \$opt_t, 
	'list|l=s'		=> \$opt_l, 
	'audit|a=s'		=> \$opt_a,
	'config|c=s'	=> \$opt_c, 
	'database|d=s'	=> \$opt_d, 
	'help|h'		=> \$opt_h,
);

# do they need help?
if ( $opt_h  ) {
	print <<HERE;

Usage: perl yacsmoke.pl [-t|--test <distribution>] 
                        [-l|--list <list_from>:<param_name>=<param_value>]
                        [-a|--audit <audit file>]
                        [-c|--config <configuration file>]
                        [-d|--database <database file>]
                        [-h|--help]
HERE
	exit 1;
}

$conf{audit_log}     = $opt_a	if($opt_a);
$conf{config_file}   = $opt_c	if($opt_c);
$conf{database_file} = $opt_d	if($opt_d);

if($opt_t) {
	test(\%conf,$opt_t);
	exit 1;
}

die "No --test or --list option specified\n"	unless($opt_l);

my @args = split(":",$opt_l);
$conf{list_from} = shift @args;
for(@args) {
	my ($name,$value) = split("=",$_);
	$conf{$name} = $value;
}

test(\%conf);
