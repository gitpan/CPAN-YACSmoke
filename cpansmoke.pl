#!/usr/bin/perl -w
use strict;

use lib qw(lib);

use CPAN::YACSmoke;

my %conf  = (
#	list_from	=> 'Recent',		# use Recent plugin
#	audit_log	=> 'audit.log',
#	config_file	=> 'cpansmoke.ini',
	cpantest    => 1,
);

test(\%conf);
