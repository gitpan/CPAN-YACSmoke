=head1 NAME

CPAN::YACSmoke::Plugin::Recent - Recent list for Yet Another CPAN Smoke Tester

=head1 SYNOPSIS

  use CPAN::YACSmoke;
  my $config = {
      list_from        => 'Recent', 
      recent_list_path => '.',       # defaults to CPANPLUS base directory
      recent_list_age  => 1          # max age of file (*)
  };
  my $foo = CPAN::YACSmoke->new(config => $config);
  my @list = $foo->download_list();

  # (*) defaults to always getting a fresh file

=head1 DESCRIPTION

This module provides the backend ability to access the list of current
modules in the F<RECENT> file from a CPAN Mirror.

This module should be used together with L<CPAN::YACSmoke>.

=cut

package CPAN::YACSmoke::Plugin::Recent;

use 5.006001;
use strict;
use warnings;

our $VERSION = '0.02';

# -------------------------------------
# Library Modules

use CPAN::YACSmoke;
use LWP::Simple;
use URI;
use File::Spec::Functions qw( catfile );
use IO::File;

# -------------------------------------
# Constants

use constant RECENT_FILE   => 'RECENT';

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

  my $self = {
    recent_list_age => 1
  };
  foreach my $field (qw( smoke force recent_list_path recent_list_age )) {
    $self->{$field} = $hash->{$field}   if(exists $hash->{$field});
  }

  bless $self, $class;
}

=head1 METHODS

=over 4

=item download_list()

Return the list of distributions recorded in the latest RECENT file.

=cut
    
sub download_list {
  my $self  = shift;

  my $path  = $self->{recent_list_path} || $self->{smoke}->basedir();
  my $local = catfile( $path, RECENT_FILE );

  if ((!$self->{force}) && $self->{recent_list_age} &&
      (-e $local) && ((-M $local) < $self->{recent_list_age}) ) {
    # no need to download

  } else {
    my $hosts = $self->{smoke}->{conf}->get_conf('hosts');
    my $h_ind = 0;

    while ($h_ind < @$hosts) {
      my $remote = URI->new( $hosts->[$h_ind]->{scheme} . '://' .
			     $hosts->[$h_ind]->{host} . $hosts->[$h_ind]->{path} . RECENT_FILE );

      #	 $self->{smoke}->msg("Downloading $remote to $local", $self->{smoke}->{verbose});

      my $status = mirror( $remote, $local );
      last    if ($status == RC_OK);
      $h_ind++;
    }

    return ()   if(@$hosts == $h_ind); # no host accessible
  }

  my @testlist;
  my $fh = IO::File->new($local)  
    or croak("Cannot access local RECENT file [$local]: $!\n");
  while (<$fh>) {
    next    unless(/^authors/);
    next    if(/CHECKSUMS|\.meta|\.readme/);
    s!authors/id/!!;
    chomp;
    #	$self->{smoke}->msg("RECENT $_", $self->{smoke}->{debug});
    #	print STDERR $_, "\n";
    push @testlist, $_;
  }

  return @testlist;
}

1;
__END__

=pod

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

=head1 AUTHORS

Robert Rothenberg <rrwo at cpan.org>

Barbie <barbie at cpan.org>, for Miss Barbell Productions,
L<http://www.missbarbell.co.uk>

=head2 Suggestions and Bug Reporting

Please submit suggestions and report bugs to the CPAN Bug Tracker at
L<http://rt.cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Robert Rothenberg.  All Rights Reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=head1 SEE ALSO

The CPAN Testers Website at L<http://testers.cpan.org> has information
about the CPAN Testing Service.

For additional information, see the documentation for these modules:

  CPANPLUS
  Test::Reporter

=cut
