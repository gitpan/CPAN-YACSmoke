#!/usr/bin/perl -w
use strict;

use lib qw(.\lib);

use CPAN::YACSmoke qw(purge);

my %conf  = (
	audit_log	=> 'audit.log',
	config_file	=> 'cpansmoke.ini',
);

my @list;
while(<DATA>) {
	next	if(/^[_\#]/);
	chomp;
	push @list, $_;
}

my $smoker = CPAN::YACSmoke->new(%conf);

$smoker->purge(@list)	if(@list);

__END__
__DATA__
# list the entries to purge
