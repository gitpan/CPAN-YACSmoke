=head1 NAME

CPAN::YACSmoke - Yet Another CPAN Smoke Tester

=head1 SYNOPSIS

  perl -MCPAN::YACSmoke -e test

=head1 DESCRIPTION

This module uses the backend of L<CPANPLUS> to run tests on modules
recently uploaded to CPAN and post results to the CPAN Testers list.

It will create a database file in the F<.cpanplus> directory which it
uses to track tested distributions.  This information will be used to
keep from posting multiple reports for the same module, and to keep
from testing modules that use non-passing modules as prerequisites.

If it is given multiple versions of the same distribution to test, it
will test the most recent version only.  If that version fails, then
it will test a previous version.

By default it uses CPANPLUS configuration settings.

=cut

package CPAN::YACSmoke;

use 5.006001;
use strict;
use warnings;

use CPANPLUS::Backend 0.051;
use CPANPLUS::Configure;
use CPANPLUS::Error;

use File::HomeDir qw( home );
use File::Spec::Functions qw( catfile );
use IO::All;
use LWP::Simple;
use POSIX qw( O_CREAT O_RDWR );         # for SDBM_File
use SDBM_File;
use URI;

require Test::Reporter;

our $VERSION = '0.01';
$VERSION = eval $VERSION;

require Exporter;

our @ISA = qw( Exporter );

our %EXPORT_TAGS = (
  'all'      => [ qw( 
    mark test
  ) ],
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
  mark test
);

use constant RECENT_FILE   => 'RECENT';
use constant DATABASE_FILE => 'YACSmoke';

sub homedir {
  my $self = shift;
  if (@_) {
    return $self->{homedir} = shift;
  }
  else {
    unless (defined $self->{homedir}) {
      if ($^O eq "MSWin32") { # bug in File::HomeDir <= 0.06
	$self->{homedir} = $ENV{HOME}        ||
	  ($ENV{HOMEDRIVE}.$ENV{HOMEPATH})   ||
	    $ENV{USERPROFILE}                ||
	    home();
      } else {
	$self->{homedir} = home();
      }
    }
    return $self->{homedir};
  }
}

sub basedir {
  my $self = shift;
  if (@_) {
    return $self->{basedir} = shift;
  }
  else {
    unless (defined $self->{basedir}) {
      $self->{basedir} = $self->{conf}->get_conf("base") || $self->homedir();
    }
    return $self->{basedir};
  }
}

{
  my %Checked;
  my $TiedObj;

 # We use the TiedObj flag instead of tied(%Checked) because the
 # function creates an additional reference in the scope of an
 # if (tied %Checked) { ... } which causes a warning etc.

  sub connect_db {
    my $self = shift;
    my $filename = shift || catfile($self->basedir(), DATABASE_FILE);
    if ($TiedObj) {
      error("Already connected to the database!");
    }
    else {
      $TiedObj = tie %Checked, 'SDBM_File', $filename, O_CREAT|O_RDWR, 0644;
      $self->{checked} = \%Checked;
      msg("Connected to database ($filename).", $self->{debug});
    }
  }

  sub disconnect_db {
    my $self = shift;

    if ($TiedObj) {
      $TiedObj         = undef;
      $self->{checked} = undef;
      untie %Checked;
      msg("Disconnected from database.", $self->{debug});
    }
    else {
      error("Not connected to the database!");
    }
  }

  my $CpanPlus;

  sub connect_cpanplus {
    my $self = shift;
    if ($CpanPlus) {
      return $self->{cpan} = $CpanPlus;
    }
    else {

      my $CpanPlus = CPANPLUS::Backend->new();

      $CpanPlus->_register_callback(
	name => 'install_prerequisite',
	code => sub {
	  unless ($TiedObj) {
	    exit error("Not connected to database!");
	  }
	  while (my $arg = shift) {
	    $arg->package =~ m/^(.+)\.tar\.gz$/;
	    my $package = $1;
	    if ( (defined $Checked{$package}) &&
		 ($Checked{$package} =~ /fail|unknown/i) ) {
	      msg("Known uninstallable prereqs $package - aborting install\n");
	      return;
	    }
	  }
	  return 1;
	},
       );

      $CpanPlus->_register_callback(
	name => 'send_test_report',
	code => sub {
	  unless ($TiedObj) {
	    exit error("Not connected to database!");
	  }
	  my $arg   = shift;
	  my $grade = shift;
	  if ($arg->{package} =~ /^(.+)\.tar\.gz$/) {
	    my $package = $1;
	    if ($Checked{$package}) {
	      return;
	    } else {
	      return ($Checked{$package} = lc($grade));
	    }
	  } else {
	    error("Unable to parse package information\n");
	    return;
	  }
	},
       );

      $CpanPlus->_register_callback(
	name => 'edit_test_report',
	code => sub { return; },
       );

      return $self->{cpan} = $CpanPlus;
    }
  }

}

sub new {
  my $class = shift || __PACKAGE__;

  my $conf = CPANPLUS::Configure->new();

  my $self  = {
    conf                 => $conf,
    checked              => undef,
    verbose              => $conf->get_conf("verbose")  || 0,
    debug                => $conf->get_conf("debug")    || 0,
    force                => $conf->get_conf("force")    || 0,
    cpantest             => $conf->get_conf("cpantest") || 0,
    recent_list_age      => 1,
    recent_list_path     => undef,
    ignore_cpanplus_bugs => 0,
    fail_max             => 3, # max failed versions to try
  };
  bless $self, $class;

  $self->connect_db();
  $self->connect_cpanplus();

  return $self;
}


sub DESTROY {
  my $self = shift;
  $self->disconnect_db();
}

sub download_recent_list {
  my $self   = shift;
  my $local  = $self->{recent_list_path} ||
    catfile( $self->basedir(), RECENT_FILE );
  if ( (!$self->{force}) &&
       (-e $local) && ((-M $local) < $self->{recent_list_age}) ) {
    return $local;
  }

  my $conf   = $self->{conf};
  my $hosts  = $conf->get_conf('hosts');
  my $h_ind  = 0;

  while ($h_ind < @$hosts) {
    my $remote = URI->new( $hosts->[$h_ind]->{scheme} . '://' .
      $hosts->[$h_ind]->{host} . $hosts->[$h_ind]->{path} . RECENT_FILE );

    msg("Downloading $remote to $local", $self->{verbose});

    my $status = mirror( $remote, $local );
    if ($status == RC_OK) {
      return $local;
    }
    $h_ind++;
  }
  return;
}

sub _build_path_list {
  my $self = shift;

  my %paths = ( );
  while (my $line = shift) {
    if ($line =~ /^authors\/id\/(.+)\-(.+)\.tar\.gz$/) {
      my $dist = $1;
      my @dirs = split /\/+/, $dist;
      my $ver  = $2;

      # due to rt.cpan.org bugs #11093, #11125 in CPANPLUS

      if ($self->{ignore_cpanplus_bugs} || (
	  (@dirs == 4) && ($ver =~ /^[\d\.\_]+$/)) ) {
	if (exists $paths{$dist}) {
	  unshift @{ $paths{$dist} }, $ver;
	}
	else {	
	  $paths{$dist} = [ $ver ];
	}
      }
      else {
	msg("Ignoring $dist-$ver (due to CPAN++ bugs)");
      }
    }
  }
  return %paths;
}

=head2 EXPORTS

The following routines are exported by default.  They are intended to
be called from the command-line, though they could be used from a
script.

=over

=cut

=item test

  perl -MCPAN::YACSmoke -e test

  perl -MCPAN::YACSmoke -e test('authors/id/R/RR/RRWO/Some-Dist-0.01.tar.gz')

Runs tests on CPAN distributions. Arguments should be paths of
individual distributions in the author directories.  If no arguments
are given, it will download the F<RECENT> file from CPAN and use that.

By default it uses CPANPLUS configuration settings. If CPANPLUS is set
not to send test reports, then it will not send test reports.

=cut

sub test {
  my $smoker = (ref $_[0]) ? shift :  __PACKAGE__->new();
  unless ($smoker->isa(__PACKAGE__)) {
    exit err("Invalid object");
  }

  my @distros = @_;
  unless (@distros) {
    my $recent_list_path = $smoker->download_recent_list();
    unless (-e $recent_list_path) {
      exit err("Unable to download list of recent modules");
    }
    @distros =
      grep /^authors\/id\/(.+)\-(.+)\.tar\.gz$/,
	io($recent_list_path)->slurp();
  }

  my %paths = $smoker->_build_path_list( @distros );

    foreach my $distpath (sort keys %paths) {
      my @versions = @{ $paths{$distpath} };
      my @dirs     = split /\/+/, $distpath;
      my $dist     = $dirs[-1];

      # When there are multiple recent versions of a distribution, we
      # only want to test the latest one. If it fails, then we'll
      # check previous distributions.

      my $passed     = 0;
      my $fail_count = 0;

      while ( (!$passed) && ($fail_count < $smoker->{fail_max}) &&
	      (my $ver = shift @versions) ) {
	my $distpathver = join("-", $distpath, $ver);
	my $distver     = join("-", $dist,     $ver);

	if (!$smoker->mark($distver)) {

	  my $mod  = $smoker->{cpan}->parse_module( module => $distpathver)
	    or error("Invalid distribution $distver\n");

	  if ($mod && (!$mod->is_bundle)) {

	    msg("Testing $distpathver");

	    eval {
	      CPANPLUS::Error->flush();

	      # BUG(?): The settings from within CPANPLUS Config seem
	      # to override these settings (cpantest). This needs to
	      # be investigated a bit.

	      my $stat = $smoker->{cpan}->install( 
  	        modules  => [ $mod ],
                target   => 'create',
                skiptest => 0,
                cpantest => $smoker->{cpantest},
                prereqs  => 1, # always install prereqs
                debug    => $smoker->{debug},
                verbose  => $smoker->{verbose},
                allow_build_interactively => 0,
              );

	      $smoker->mark($distver, 'unknown'),
		unless ($smoker->mark($distver));

	      $passed = ($smoker->mark($distver) eq 'pass');
	    };
	  }
	}
	else {
	  $passed = ($smoker->mark($distver) eq 'pass');
	}
	$fail_count++, unless ($passed);
      }
    }
}

=item mark

  perl -MCPAN::YACSmoke -e mark('Some-Dist-0.01')

  perl -MCPAN::YACSmoke -e mark('Some-Dist-0.01', 'fail')

Retrieves the test result in the database, or changes the test result.

It can be useful to update the status of a distribution that once
failed or was untestable but now works, so as to test modules which
make use of it.

=cut

sub mark {
  my $smoker = (ref $_[0]) ? shift :  __PACKAGE__->new();
  unless ($smoker->isa(__PACKAGE__)) {
    exit err("Invalid object");
  }
  my $distver = shift || "";
  my $grade   = shift || "";
  if ($grade) {
    unless ($grade =~ /(pass|fail|unknown|na|none)/) {
      return error("Invalid grade: '$grade'");
    }
    if ($grade eq "none") { $grade = undef; }
    $smoker->{checked}->{$distver} = $grade;
    msg("result for '$distver' marked as '$grade'", $smoker->{verbose});
  }
  else {
    $grade = $smoker->{checked}->{$distver};
    if ($grade) {
      msg("result for '$distver' is '$grade'", $smoker->{verbose});
    }
    else {
      msg("no result for '$distver'", $smoker->{verbose});
    }
  }
  return $grade;
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

=head1 AUTHOR

Robert Rothenberg <rrwo at cpan.org>

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
