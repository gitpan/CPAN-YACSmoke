=head1 NAME

CPAN::YACSmoke::Plugin::SmokeDB - SmokeDB list for Yet Another CPAN Smoke Tester

=head1 SYNOPSIS

  use CPAN::YACSmoke;
  my $config = {
	  list_from => 'SmokeDB', 
  };
  my $foo = CPAN::YACSmoke->new(config => $config);
  my @list = $foo->download_list();

=head1 DESCRIPTION

This module provides the backend ability to access the list of current
modules recorded in the local cpansmoke database.

This module should be use together with CPAN::YACSmoke.

=cut

package CPAN::YACSmoke::Plugin::SmokeDB;

use 5.006001;
use strict;
use warnings;

our $VERSION = '0.01';

# -------------------------------------
# Library Modules

use CPAN::YACSmoke;

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
    };
    foreach my $field (qw( smoke )) {
        $self->{$field} = $hash->{$field}   if(exists $hash->{$field});
    }

    bless $self, $class;
}

=head1 METHODS

=over 4

=item download_list()

Returns the current distributions stored in the local cpansmoke database.

=cut
    
sub download_list {
    my $self  = shift;
    return keys %{ $self->{smoke}->{checked} };
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

=head2 Suggestions and Bug Reporting

Please submit suggestions and report bugs to the CPAN Bug Tracker at
L<http://rt.cpan.org>.

=head1 SEE ALSO

The CPAN Testers Website at L<http://testers.cpan.org> has information
about the CPAN Testing Service.

For additional information, see the documentation for these modules:

  CPANPLUS
  Test::Reporter
  CPAN::YACSmoke

=head1 AUTHOR

Barbie, C< <<barbie@cpan.org>> >
for Miss Barbell Productions, L<http://www.missbarbell.co.uk>

Birmingham Perl Mongers, L<http://birmingham.pm.org/>

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2005 Barbie for Miss Barbell Productions
  All Rights Reserved.

  This module is free software; you can redistribute it and/or 
  modify it under the same terms as Perl itself.

=cut
