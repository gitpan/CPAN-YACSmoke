package CPAN::YACSmoke::Plugin::PlainTextList;

use 5.006001;
use strict;
use warnings;

our $VERSION = '0.01';

# -------------------------------------

=head1 NAME

CPAN::YACSmoke::Plugin::PlainTextList - Plain text file plugin for CPAN::YACSmoke

=head1 SYNOPSIS

  use CPAN::YACSmoke;
  my $config = {
      list_from => 'PlainTextList', 
      data => 'datafile.txt'
  };
  my $foo = CPAN::YACSmoke->new(config => $config);
  my @list = $foo->download_list();

=head1 DESCRIPTION

This module provides the backend ability to access a list of current
distributions available for testing, in a plain text data file. Each
distribution should appear on a separate line, with the complete CPAN
author name path, eg:

  B/BA/BARBIE/CPAN-YACSmoke-Plugin-PlainTextList-0.01

This module should be use together with CPAN::YACSmoke.

=cut

# -------------------------------------
# Library Modules

use CPAN::YACSmoke;
use IO::File;

# -------------------------------------
# The Subs

=head1 CONSTRUCTOR

=over 4

=item new()

Creates the plugin object.

=back

=cut
    
sub new {
    my $class = shift || __PACKAGE__;
    my $hash  = shift;

    my $self = {};
    foreach my $field (qw( smoke data )) {
        $self->{$field} = $hash->{$field}   if(exists $hash->{$field});
    }

	unless($self->{data}) {
		$self->{smoke}->error("No data file specified");
		return undef;
	}

	unless(-f $self->{data}) {
		$self->{smoke}->error("Cannot access data file [$self->{data}]");
		return undef;
	}

    bless $self, $class;
}

=head1 METHODS

=over 4

=item download_list()

Return the list of distributions within the data file.

=cut
    
sub download_list {
    my $self = shift;
    my @distros;

	my $fh = IO::File->new($self->{data});
	unless($fh) {
		$self->{smoke}->error("Cannot open data file [$self->{data}]");
		return undef;
	}

	while(<$fh>) { chomp; push @distros, $_; }
	$fh->close();

	return @distros;
}

1;
__END__

=back

=head1 CAVEATS

This is a proto-type release. Use with caution and supervision.

The current version has a very primitive interface and limited
functionality.  Future versions may have a lot of options.

There is always a risk associated with automatically downloading and
testing code from CPAN, which could turn out to be malicious or
severely buggy.  Do not run this on a critical machine.

This module uses the backend of CPANPLUS to do most of the work, so is
subject to any bugs of CPANPLUS.

=head1 BUGS, PATCHES & FIXES

There are no known bugs at the time of this release. However, if you spot a
bug or are experiencing difficulties, that is not explained within the POD
documentation, please send an email to barbie@cpan.org or submit a bug to the
RT system (http://rt.cpan.org/). However, it would help greatly if you are 
able to pinpoint problems or even supply a patch. 

Fixes are dependant upon their severity and my availablity. Should a fix not
be forthcoming, please feel free to (politely) remind me.

=head1 SEE ALSO

The CPAN Testers Website at L<http://testers.cpan.org> has information
about the CPAN Testing Service.

For additional information, see the documentation for these modules:

  CPANPLUS
  Test::Reporter
  CPAN::YACSmoke

=head1 DSLIP

  b - Beta testing
  d - Developer
  p - Perl-only
  O - Object oriented
  p - Standard-Perl: user may choose between GPL and Artistic

=head1 AUTHOR

  Barbie, <barbie@cpan.org>
  for Miss Barbell Productions <http://www.missbarbell.co.uk>.

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2005 Barbie for Miss Barbell Productions.
  All Rights Reserved.

  This module is free software; you can redistribute it and/or 
  modify it under the same terms as Perl itself.

=cut
