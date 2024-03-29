=head1 NAME

CPAN::YACSmoke - Yet Another CPAN Smoke Tester

=begin readme

=head1 REQUIREMENTS

This package requires the following modules (most of which are not
included with Perl):

  CPANPLUS
  Config::IniFiles
  File::Basename
  File::HomeDir
  File::Path
  File::Spec
  File::Temp
  IO::File
  LWP::Simple
  Module::Pluggable
  Path::Class
  Regexp::Assemble
  SDBM_File
  Sort::Versions
  Test::Reporter
  URI
  if

These dependencies (such as L<CPANPLUS> and L<Test::Reporter>) may require
additional modules.

Windows users should also have L<File::HomeDir::Win32> installed.

=head1 INSTALLATION

Installation can be done using the traditional Makefile.PL or the newer
Build.PL methods.

Using Makefile.PL:

  perl Makefile.PL
  make test
  make install

(On Windows platforms you should use C<nmake> instead.)

Using Build.PL (if you have Module::Build installed):

  perl Build.PL
  perl Build test
  perl Build install

=end readme

=head1 SYNOPSIS

  perl -MCPAN::YACSmoke -e test

=head1 DESCRIPTION

This module uses the backend of L<CPANPLUS> to run tests on modules
recently uploaded to CPAN and post results to the CPAN Testers list.

=begin readme

See the module documentation for more information.

=head1 REVISION HISTORY

=for readme include file=Changes type=text start=0.03 stop=0.03_05

=end readme

=for readme stop

It will create a database file in the F<.cpanplus> directory, which it
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

use File::Path;
use File::Basename;
use File::HomeDir qw( home );
use File::Spec::Functions qw( splitpath );
use LWP::Simple;
use Path::Class;
use POSIX qw( O_CREAT O_RDWR );         # for SDBM_File
use Regexp::Assemble;
use SDBM_File;
use Sort::Versions;
use URI;
use Module::Pluggable search_path => ["CPAN::YACSmoke::Plugin"];
use Carp;
use Config::IniFiles;

use if ($^O eq "MSWin32"), "File::HomeDir::Win32";

# use YAML 'Dump';

require Test::Reporter;
require YAML;

our $VERSION = '0.03_07';
$VERSION = eval $VERSION;

require Exporter;

our @ISA = qw( Exporter );
our %EXPORT_TAGS = (
  'all'      => [ qw( mark test excluded purge flush ) ],
  'default'  => [ qw( mark test excluded ) ],
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT    = ( @{ $EXPORT_TAGS{'default'} } );

use constant DATABASE_FILE => 'cpansmoke.dat';
use constant CONFIG_FILE   => 'cpansmoke.ini';

my $extn = qr/(?:\.(?:tar\.gz|tgz|zip))/;	# supported archive extensions

=head1 OBJECT INTERFACE

=over 4

=cut

{
  my %Checked;
  my $TiedObj;

  # We use the TiedObj flag instead of tied(%Checked) because the
  # function creates an additional reference in the scope of an
  # if (tied %Checked) { ... } which causes a warning etc.

  sub _connect_db {
    my $self = shift;
    my $filename = $self->{database_file};
    if ($TiedObj) {
#     error("Already connected to the database!");
    } else {
      $TiedObj = tie %Checked, 'SDBM_File', $filename, O_CREAT|O_RDWR, 0644;
      $self->{checked} = \%Checked;
      $self->_debug("Connected to database ($filename).");
    }
  }

  sub _disconnect_db {
    my $self = shift;

    if ($TiedObj) {
      $TiedObj         = undef;
      $self->{checked} = undef;
      untie %Checked;
      $self->_debug("Disconnected from database.");
#	} else {
#	  error("Not connected to the database!");
    }
  }

  my $CONF = CPANPLUS::Configure->new();
  sub _connect_configure {
    return $CONF;
  }

  my $CpanPlus;

  sub _connect_cpanplus {
    my $self = shift;
    return $self->{cpan} = $CpanPlus if ($CpanPlus);

    my $conf = shift;

    $CpanPlus = CPANPLUS::Backend->new($conf);

    if ($CPANPLUS::Backend::VERSION >= 0.052) {

      # TODO: if PASS included skipped tests, add a comment

      $CpanPlus->_register_callback(
        name => 'munge_test_report',
        code => sub {
		  my $mod    = shift;
		  my $report = shift || "";
		  $report =~ s/\[MSG\] \[[\w: ]+\] Extracted .*?\n//sg	if($self->{suppress_extracted});
		  $report .=
			"\nThis report was machine-generated by CPAN::YACSmoke $VERSION.\n";
		  return $report;
        },
      );
    }

    # BUG: this callback does not seem to get called consistently, if at all.

    $CpanPlus->_register_callback(
      name => 'install_prerequisite',
      code => sub {
		my $mod   = shift;
		my $root;
		if ($mod->package =~ /^(.+)$extn$/) {
		  $root = $1;
		}
		else {
		  error("Cannot handle ".$mod->package);
		  return;
		}

		unless ($TiedObj) {
		  croak "Not connected to database!";
		}
		while (my $arg = shift) {
		  $arg->package =~ m/^(.+)$extn$/;
		  my $package = $1;

		  # BUG: Exclusion does not seem to work for prereqs.
		  # Sometimes it seems that the install_prerequisite
		  # callback is not even called! Need to investigate.

		  if ($self->_is_excluded_dist($package)) { # prereq on excluded list
			msg("Prereq $package is excluded");
			return;
		  }

		  my $checked = $Checked{$package};
		  if (defined $checked &&
			  $checked =~ /aborted|fail|na/ ) {

			if ($self->{ignore_bad_prereqs}) {
			  msg("Known uninstallable prereqs $package - may have problems\n");
			} else {
			  msg("Known uninstallable prereqs $package - aborting install\n");
			  $Checked{$root} = "aborted";
			  return;
			}
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
		my $mod   = shift;
		my $grade = lc shift;
		if ($mod->{package} =~ /^(.+)$extn$/) {
		  my $package = $1;
		  my $checked = $Checked{$package};

		  # TODO: option to report only passing tests

		  return unless ($self->{cpantest});

          # Simplified algorithm for reporting: 
          # * don't send a report if
          #   - we get the same results as the last report sent
          #   - it passed the last test but not now
          #   - it didn't pass the last test or now

		  return if (defined $checked && (
                    ($checked eq $grade)                     ||
		    ($checked ne 'pass' && $grade ne 'pass')));

		  $Checked{$package} = $grade;

		  return ((!$self->{report_pass_only}) || ($grade eq 'pass'));

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

my @CPANPLUS_FIELDS = qw(
	verbose debug force cpantest 
	prereqs skiptest
        prefer_bin prefer_makefile
        makeflags makemakerflags
        md5 signature
        extractdir fetchdir
);

my @CONFIG_FIELDS = (@CPANPLUS_FIELDS, qw(
	recent_list_age ignore_cpanplus_bugs fail_max
	exclude_dists test_max audit_log
	ignore_bad_prereqs report_pass_only
	allow_retries flush_flag suppress_extracted
));


=item new( [ %config ] )

The object interface is created normally through the test() or mark()
functions of the procedural interface. However, it can be accessed
with a set of configuration settings to extend the capabilities of
the package.

CPANPLUS configuration settings (inherited from CPANPLUS unless
otherwise noted) are:

  verbose
  debug 
  force 
  cpantest
  report_pass_only
  prereqs
  prefer_bin
  prefer_makefile    - enabled by default
  makeflags
  makemakerflags
  md5
  signature
  extractdir
  fetchdir

CPAN::YACSmoke configuration settings are:

  ignore_cpanplus_bugs
  ignore_bad_prereqs
  fail_max
  exclude_dists
  test_max
  allow_retries
  suppress_extracted
  flush_flag         - used by purge()

  list_from          - List plugin required, default Recent

  recent_list_age    - used with the Recent plugin 
  recent_list_path   - used with the Recent plugin 
  mailbox            - used with the Outlook plugin 
  nntp_id            - used with the NNTP plugins 
  webpath            - used with the WebList plugin 

  audit_log          - log file to write progress to

  config_file        - an INI file with the above settings
  database_file      - the local cpansmoke database

All settings can use defaults. With regards to the last setting,
the INI file should contain one setting per line, except the values
for the exclude_dists setting, which are laid out as:

  [CONFIG]
  exclude_dists=<<HERE
  mod_perl
  HERE

The above would then ignore any distribution that include the string
'mod_perl' in its name. This is useful for distributions which use
external C libraries, which are not installed, or for which testing
is problematic.

The setting 'test_max' is used to restrict the number of distributions
tested in a single run. As some distributions can take some time to be
tested, it may be more suitable to run in small batches at a time. The
default setting is 100 distributions.

The setting 'allow_retries' defaults to include grades of UNGRADED, IGNORED
and ABORTED. If you wish to change this, for example to only allow grades
of UNGRADED to be retried, you can specify as:

  [CONFIG]
  allow_retries=ungraded

Often module authors prefer to see the details of failed tests. You can
make this the default setting using:

  [CONFIG]
  makeflags=TEST_VERBOSE=1

Note that sending verbose failure reports for packages with thousands
of tests will be quite large (!), and may be blocked by mail and news
servers.

See L<Config::IniFiles> for more information on the INI file format.

=back

=cut 

sub new {
	my $class = shift || __PACKAGE__;

	## Ensure CPANPLUS knows we automated. 
	## (Q: Should we use Env::C to set this instead?)

	$ENV{AUTOMATED_TESTING} = 1;
	$ENV{PERL_MM_USE_DEFAULT} = 1; # despite verbose setting

	my $conf = _connect_configure();

	## set internal defaults
	my $self  = {
        conf                 => $conf,
		checked              => undef,
		ignore_cpanplus_bugs => ($CPANPLUS::Backend::VERSION >= 0.052),
		fail_max             => 3,     # max failed versions to try
		exclude_dists        => [ ],   # Regexps to exclude
		test_max             => 100,   # max distributions per run
		allow_retries        => 'aborted|ungraded',
	};

	bless $self, $class;

	## set from CPANPLUS defaults
	foreach my $field (@CPANPLUS_FIELDS) {
	  $self->{$field} = $conf->get_conf($field);
	}


	## force overide of default settings

	$self->{skiptest} = 0;
	$self->{prereqs}  = 2; # force to ask callback

    # Makefile.PL shows which tests failed, whereas Build.PL does
    # not when reports are sent through CPANPLUS 0.053, hence the
    # prefer_makefile=1 default.

    $self->{prefer_makefile} = 1;

    # If we have TEST_VERBOSE=1 by default, then many FAIL reports
    # will be huge. A lot of module authors will want that, but
    # it's not the best idea to send those out immediately.

    ## $self->{makeflags} = 'TEST_VERBOSE=1';
	
	my %config = @_;

	## config_file is an .ini file

	$config{config_file} ||=
          file($self->basedir(), CONFIG_FILE)->stringify;

	if($config{config_file} && -r $config{config_file}) {
		my $cfg = Config::IniFiles->new(-file => $config{config_file});
		foreach my $field (@CONFIG_FIELDS) {
		   my $val = $cfg->val( 'CONFIG', $field );
		   $self->{$field} = $val	if(defined $val);
                   # msg("Setting $field = $val") if (defined $val);

		}
		my @list = $cfg->val( 'CONFIG', 'exclude_dists' );
		$self->{exclude_dists} = [ @list ]	if(@list);
	}

	if ($self->{audit_log}) {
	  my ($vol, $path, $file) = splitpath($self->{audit_log});
	  unless ($vol || $path) {
	    $self->{audit_log} = file($self->basedir(), $file)->stringify;
	  }
	}


	## command line switches override
	foreach my $field (@CONFIG_FIELDS, 'audit_cb') {
		if (exists $config{$field}) {
			$self->{$field} = $config{$field};
		}
	}

	## reset CPANPLUS defaults
	foreach my $field (@CPANPLUS_FIELDS) {
		$conf->set_conf($field => $self->{$field});
	}

	$self->{test_max} = 0	if($self->{test_max} < 0);	# sanity check


	## determine the data source plugin

	$config{list_from} ||= 'Recent';
	my $plugin;
	my @plugins = $self->plugins();
	for(@plugins) {
		$plugin = $_	if($_ =~ /$config{list_from}/);
	}

	croak("no plugin available of that name\n")	unless($plugin);
	eval "CORE::require $plugin";
	croak "Couldn't require $plugin : $@" if $@;
	$config{smoke} = $self;
	$self->{plugin} = $plugin->new(\%config);


	## determine the database file

	$self->{database_file} ||=
          file($self->basedir(), DATABASE_FILE)->stringify;

	$self->_connect_db();
	$self->_connect_cpanplus($conf);

	return $self;
}


sub DESTROY {
  my $self = shift;
  $self->_audit("Disconnecting from database");
  $self->_disconnect_db();
}

=head2 METHODS

=over 4

=item homedir

Obtains the users home directory

=cut 

# TODO: use CPANPLUS function

sub homedir {
  my $self = shift;
  return $self->{homedir} = dir(shift)	if (@_);

  my $home = dir(home());

  $self->{homedir} = $home;

  $self->_audit("homedir = " . $self->{homedir});
  return $self->{homedir}->stringify;
}

=item basedir

Obtains the base directory for downloading and testing distributions.

=cut 

sub basedir {
  my $self = shift;
  return $self->{basedir} = shift if (@_);

  unless (defined $self->{basedir}) {
    $self->{basedir} = $self->{conf}->get_conf("base") || $self->homedir();
  }
  return $self->{basedir};
}

=item builddir

Obtains the build directory for unpacking and testing distributions.

=back

=cut 

sub builddir {
  my $self = shift;

  require Config;

  return dir(
    $self->{conf}->get_conf('base'),
	$Config::Config{version},
	$self->{conf}->_get_build('moddir'),
  )->stringify;
}


sub _is_excluded_dist {
	my $self = shift;
	my $dist = shift;
	unless($self->{re}) {
		$self->{re} = new Regexp::Assemble;
		$self->{re}->add( @{ $self->{exclude_dists} } );
	}

	return 1	if($dist =~ $self->{re}->re);
	return 0;
}

sub _remove_excluded_dists {
	my $self = shift;
	my @dists = ( );
	my $removed = 0;

	while (my $dist = shift) {
		my $file = basename($dist);
		if ($self->_is_excluded_dist($file)) {
			chomp($file);
			$self->_track("Excluding $dist");
			$removed = 1;
		} else {
			push @dists, $dist;
		}
	}
	$self->_audit('')	if($removed);
	return @dists;
}

sub _build_path_list {
  my $self = shift;
  my $ignored = 0;

  my %paths = ( );
  while (my $line = shift) {
    if ($line =~ /^(.*)\-(.+)$extn$/) {
      my $dist = $1;
      my @dirs = split /\/+/, $dist;
      my $ver  = $2;

      # due to rt.cpan.org bugs #11093, #11125 in CPANPLUS

      if ($self->{ignore_cpanplus_bugs} || (
	   (@dirs == 4) && ($ver =~ /^[\d\.\_]+$/)) ) {

		if (exists $paths{$dist}) {
		  unshift @{ $paths{$dist} }, $ver;
		} else {	
		  $paths{$dist} = [ $ver ];
		}

      } else {
		$self->_track("Ignoring $dist-$ver (due to CPAN+ bugs)");
		$ignored = 1;
      }

      # check for previously parsed package string
    } elsif ($line =~ /^(.*)\-(.+)$/) {
      my $dist = $1;
      my @dirs = split /\/+/, $dist;
      my $ver  = $2;

      if (@dirs == 1) {		# previously parsed
		if (exists $paths{$dist}) {
		  unshift @{ $paths{$dist} }, $ver;
		} else {	
		  $paths{$dist} = [ $ver ];
		}
      }
    }
  }
  $self->_audit('')	if($ignored);
  return %paths;
}

=head1 PROCEDURAL INTERFACE

=head2 EXPORTS

The following routines are exported by default.  They are intended to
be called from the command-line, though they could be used from a
script.

=over

=cut

=item test( [ %config, ] [ $dist [, $dist .... ] ] )

  perl -MCPAN::YACSmoke -e test

  perl -MCPAN::YACSmoke -e test('R/RR/RRWO/Some-Dist-0.01.tar.gz')

Runs tests on CPAN distributions. Arguments should be paths of
individual distributions in the author directories.  If no arguments
are given, it will download the F<RECENT> file from CPAN and use that.

By default it uses CPANPLUS configuration settings. If CPANPLUS is set
not to send test reports, then it will not send test reports.

For further use of configuration settings see the new() constructor.

=cut

sub test {
  my $smoker;
  eval {
    if ((ref $_[0]) && $_[0]->isa(__PACKAGE__)) {
      $smoker = shift;
    }
  };
  my %config = ref($_[0]) eq 'HASH' ? %{ shift() } : ();
  $smoker ||= __PACKAGE__->new(%config);

  $smoker->_audit("\n".('-'x40)."\n");

  my @distros = @_;
  unless (@distros) {
    @distros = $smoker->{plugin}->download_list();
    unless (@distros) {
      exit error("No new distributions uploaded to be tested");
    }
  }

  my %paths = $smoker->_build_path_list(
    $smoker->_remove_excluded_dists( @distros )
  );

  # only test as many distributions as specified
  my @testlist;
  push @testlist, keys %paths;

  foreach my $distpath (sort @testlist) {
    last	unless($smoker->{test_max} > 0);

    my @versions = @{ $paths{$distpath} };
    my @dirs     = split /\/+/, $distpath;
    my $dist     = $dirs[-1];

	# When there are multiple recent versions of a distribution, we
	# only want to test the latest one. If it fails, then we'll
	# check previous distributions.

    my $passed     = 0;
    my $fail_count = 0;
	my $report     = 1;

    # TODO - if test fails due to bad prereqs, set $fail_count to
    # fail_max and abort testing versions (based on an option)

    while ( (!$passed) && ($fail_count < $smoker->{fail_max}) &&
	    (my $ver = shift @versions) ) {
      my $distpathver = join("-", $distpath, $ver);
      my $distver     = join("-", $dist,     $ver);

      my $grade = $smoker->{checked}->{$distver} || 'ungraded';

      if (($grade eq 'ungraded') ||
	  ($smoker->{allow_retries} && $grade =~ /$smoker->{allow_retries}/)) {

	    my $mod = $smoker->{cpan}->parse_module( module => $distpathver)
	      or error("Invalid distribution $distver\n");

	    if ($mod && (!$mod->is_bundle)) {
	      $smoker->_audit(('-'x40)."\n");
	      $smoker->_track("Testing $distpathver");
	      $smoker->{test_max}--;
		  $report = 1;

		  eval {
					  
			CPANPLUS::Error->flush();

			# TODO: option to not re-test prereqs that are known to
			# pass (maybe if we use DBD::SQLite for the database and
			# mark the date of the result?)

			my $stat = $smoker->{cpan}->install( 
				modules  => [ $mod ],
				target   => 'create',
				allow_build_interactively => 0,
				# other settings now set via set_config() method
			);

			# TODO: check the $stat and react appropriately

            my $stack = CPANPLUS::Error->stack_as_string();
            $stack =~ s/\[MSG\] \[[\w: ]+\] Extracted .*?\n//sg	if($smoker->{suppress_extracted});
            $smoker->_audit($stack);

			# TODO: option to mark uncompleted tests as aborted vs ungraded
			#       aborted should indicate a fault in testing the distribution
			#       ungraded should indicate a fault in testing a prerequisite
			# 'Out of memory' faults, known failing prereqs, CPANPLUS faults,
			# etc should all be covered by these. Otherwise it would be a FAIL.

			$grade  = ($smoker->{checked}->{$distver} ||= 'aborted');
			$passed = ($grade eq 'pass');

			$smoker->_audit("\nReport Grade for $distver is ".uc($smoker->{checked}->{$distver})."\n");

		  }; # end eval block
		}
      } else {
		if($report == 1) {
		  $smoker->_audit(('-'x40)."\n");
		  $report = 0;
		}
		$passed = ($grade eq 'pass');
		$smoker->_audit("$distpathver already tested and graded ".uc($grade)."\n");
      }
      $fail_count++, unless ($passed);

      # Mark older versions so that they are not tested
      if ($passed) {
		while (my $ver = shift @versions) {
		  my $distver = join("-", $dist, $ver);
		  $smoker->{checked}->{$distver} = "ignored";
		}
	  }
    }
  }
  $smoker = undef;

  # TODO: repository fills up. An option to flush it is needed.

}

=item mark( [ %config, ] $dist [, $grade ] ] )

  perl -MCPAN::YACSmoke -e mark('Some-Dist-0.01')

  perl -MCPAN::YACSmoke -e mark('Some-Dist-0.01', 'fail')

Retrieves the test result in the database, or changes the test result.

It can be useful to update the status of a distribution that once
failed or was untestable but now works, so as to test modules which
make use of it.

Grades can be one of (case insensitive):

  aborted  = tests aborted (uninstallable prereqs or other failure in test)
  pass     = passed tests
  fail     = failed tests
  unknown  = no tests available
  na       = not applicable to platform or installed libraries
  ungraded = no grade (test possibly aborted by user)
  none     = undefines a grade
  ignored  = package was ignored (a newer version was tested)


For further use of configuration settings see the new() constructor.

=cut

sub mark {
  my $smoker;
  eval {
    if ((ref $_[0]) && $_[0]->isa(__PACKAGE__)) {
      $smoker = shift;
    }
  };	

  my %config = ref($_[0]) eq 'HASH' ? %{ shift() } : ( verbose => 1, );
  $smoker ||= __PACKAGE__->new(%config);

  $smoker->_audit("\n".('-'x40)."\n");

  my $distver = shift || "";
  my $grade   = lc shift || "";

  # See POD above for a description of the grades

  if ($grade) {
    unless ($grade =~ /(pass|fail|unknown|na|none|ungraded|aborted|ignored)/) {
      return error("Invalid grade: '$grade'");
    }
    if ($grade eq "none") {
      $grade = undef;
    }
    $smoker->{checked}->{$distver} = $grade;
    $smoker->_track("result for '$distver' marked as '" . ($grade||"none")."'");
  } else {
    my @distros = ($distver ? ($distver) : $smoker->{plugin}->download_list());
    my %paths = $smoker->_build_path_list(
      $smoker->_remove_excluded_dists( @distros )
    );
    foreach my $distpath (sort { versioncmp($a, $b) } keys %paths) {
	  my $dist = $distpath;
	  $dist =~ s!.*/!!;
      foreach my $ver (@{ $paths{$distpath} }) {
		$grade = $smoker->{checked}->{"$dist-$ver"};
		if ($grade) {
		  $smoker->_track("result for '$distpath-$ver' is '$grade'");
		} else {
		  $smoker->_track("no result for '$distpath-$ver'");
		}
      }
    }
  }
  $smoker = undef;
  return $grade	if($distver);
}

=item excluded( [ %config, ] [ $dist [, $dist ... ] ] )

  perl -MCPAN::YACSmoke -e excluded('Some-Dist-0.01')

  perl -MCPAN::YACSmoke -e excluded()

Given a list of distributions, indicates which ones would be excluded from
testing, based on the exclude_dist list that is created.

For further use of configuration settings see the new() constructor.

=cut

sub excluded {
  my $smoker;
  eval {
    if ((ref $_[0]) && $_[0]->isa(__PACKAGE__)) {
      $smoker = shift;
    }
  };
  my %config = ref($_[0]) eq 'HASH' ? %{ shift() } : ();
  $smoker ||= __PACKAGE__->new(%config);

  $smoker->_audit("\n".('-'x40)."\n");

  my @distros = @_;
  unless (@distros) {
    @distros = $smoker->{plugin}->download_list();
    unless (@distros) {
      exit err("No new distributions uploaded to be tested");
    }
  }

  my @dists = $smoker->_remove_excluded_dists( @distros );
  $smoker->_audit('EXCLUDED: '.(scalar(@distros) - scalar(@dists))." distributions\n\n");
  $smoker = undef;
  return @dists;
}

# TODO: a method to purge older versions of test results from Checked
# database. (That is, if the latest version tested is 1.23, we don't
# need to keep earlier results around.)  There should be an option to
# disable this behaviour.

=item purge( [ %config, ] [ $dist [, $dist ... ] ] )

  perl -MCPAN::YACSmoke -e purge()

  perl -MCPAN::YACSmoke -e purge('Some-Dist-0.01')

Purges the entries from the local cpansmoke database. The criteria for purging
is that a distribution must have a more recent version, which has previously
been marked as a PASS. However, if one or more distributions are passed as a
parameter list, those specific distributions will be purged.

If the flush_flag is set, via the config hash, to a true value, the directory 
path created for each older copy of a distribution is deleted.

For further use of configuration settings see the new() constructor.

=cut

sub purge {
  my $smoker;
  eval {
    if ((ref $_[0]) && $_[0]->isa(__PACKAGE__)) {
      $smoker = shift;
    }
  };
  my %config = ref($_[0]) eq 'HASH' ? %{ shift() } : ();
  $smoker ||= __PACKAGE__->new(%config);

  my $flush = $smoker->{flush_flag} || 0;
  my %distvars;
  my $override = 0;

  if(@_) {
	  $override = 1;
	  for(@_) {
		next	unless(/^(.*)\-(.+)$/);
		push @{$distvars{$1}}, $2;
	  }
  } else {
	  for(keys %{$smoker->{checked}}) {
		next	unless(/^(.*)\-(.+)$/);
		push @{$distvars{$1}}, $2;
	  }
  }

  for my $dist (sort keys %distvars) {
	  my $passed = $override;
	  my @vers = sort { versioncmp($a, $b) } @{$distvars{$dist}};
	  while(@vers) {
		my $vers = pop @vers;		# the latest
		if($passed) {
			$smoker->_track("'$dist-$vers' ['".
							uc($smoker->{checked}->{"$dist-$vers"}).
							"'] has been purged");
			delete $smoker->{checked}->{"$dist-$vers"};
			if($flush) {
		          my $builddir =
                            file($smoker->basedir(), "$dist-$vers")->stringify;
			  rmtree($builddir)	if(-d $builddir);
			}
		}
		elsif($smoker->{checked}->{"$dist-$vers"} eq 'pass') {
			$passed = 1;
		}
	  }
  }

}

=item flush( [ %config, ] [ 'all' | 'old' ]  )

  perl -MCPAN::YACSmoke -e flush()
  
  perl -MCPAN::YACSmoke -e flush('all')

  perl -MCPAN::YACSmoke -e flush('old')

Removes unrequired build directories from the designated CPANPLUS build
directory. Note that this deletes directories regardless of whether the 
associated distribution was tested.

Default flush is 'all'. The 'old' option will only delete the older 
distributions, of multiple instances of a distribution.

Note that this cannot be done reliably using last access or modify time, as
the intention is for this distribution to be used on any OS that CPANPLUS
is installed on. In this case not all OSs support the full range of return
values from the stat function.

For further use of configuration settings see the new() constructor.

=cut

sub flush {
  my $smoker;
  eval {
    if ((ref $_[0]) && $_[0]->isa(__PACKAGE__)) {
      $smoker = shift;
    }
  };
  my %config = ref($_[0]) eq 'HASH' ? %{ shift() } : ();
  $smoker ||= __PACKAGE__->new(%config);

  my $param = shift || 'all';
  my %dists;

  opendir(DIR, $smoker->builddir());
  while(my $dir = readdir(DIR)) {
	next	if($dir =~ /^\.+$/);

	if($param eq 'old') {
		$dir =~ /(.*)-(.+)$extn/;
		$dists{$1}->{$2} = "$dir";
	} else {
		rmtree($dir);
		$smoker->_track("'$dir' flushed");
	}
  }
  closedir(DIR);

  if($param eq 'old') {
	for my $dist (keys %dists) {
	  for(sort { versioncmp($a, $b) } keys %{$dists{$dist}}) {
	    rmtree($dists{$dist}->{$_});
		$smoker->_track("'$dists{$dist}->{$_}' flushed");
	  }
	}
  }

}

## Private Methods

sub _track {
	my ($self,$message) = @_;
	msg($message, $self->{verbose});
	$self->_audit($message);
}

sub _debug {
  my ($self,$message) = @_;
  return unless($self->{debug});
  $self->_audit($message);
}

sub _audit {
  my $self = shift;
  $self->{audit_cb}->(@_)	if($self->{audit_cb});
  return	unless($self->{audit_log});

  my $FH = IO::File->new(">>".$self->{audit_log})
    or exit error("Failed to write to file [$self->{audit_log}]: $!\n");
  print $FH join("\n",@_) . "\n";
  $FH->close;
}

1;
__END__

=pod

=back

=head1 PLUGINS

To know which distributions to test, the packages needs to access a list
of distributions that have been recently uploaded to CPAN. There are
currently four plugins which can enable this:

=head2 Recent

The Recent plugin downloads the F<RECENT> file from CPAN, and returns
the list of recently added modules, by diff-ing from the previously
downloaded version.

Pass through configuration settings:

  %config = {
	  list_from => 'Recent',
 	  recent_list_age => '',
	  recent_list_path => '.'
  };

=head2 SmokeDB

The SmokeDB plugin uses the contents of the locally stored cpansmoke database.
This can then be used to retest distributions that haven't been fully tested
previously.

There are no pass through configuration settings.

=head2 PlainTextList

The PlainTextList plugin allows for a locally created plain text file,
listing all the distributions to be tested in a single run. Note that the
excluded list and text_max settings will still apply.

Pass through configuration settings:

  %config = {
	  list_from => 'PlainTextList',
 	  data => $my_data_file,
  };

=head2 Writing A Plugin

For an example, see one of the above plugins, or one of the known plugin
packages available on CPAN (see list below). 

The constructor, new(), is passed a hash of the configuration settings. The
setting 'smoke' is an object reference to YACSmoke. Be sure to save the 
configuration settings your plugin requires in the constructor. 

The single instance method used by YACSmoke is download_list(). This should
return a simple list of the distributions available for testing. Note
that if a parameter value of 1 is passed to download_list(), this indicates
that a test run is in progress, otherwise only a query on the outstanding 
list is being made.

=head2 Known Plugin Packages on CPAN

=over

=item CPAN::YACSmoke::Plugin::NNTP

Uses the NNTP feed direct via 'nntp.perl.org' of 'perl.cpan.testers'.

=item CPAN::YACSmoke::Plugin::NNTPWeb

Uses the web interface to the newsgroup 'perl.cpan.testers'.

=item CPAN::YACSmoke::Plugin::Outlook

Uses a list of emails held in an Outlook mail folder

=item CPAN::YACSmoke::Plugin::Phlanax100

Uses the distributions within the Phlanax 100 list

=item CPAN::YACSmoke::Plugin::WebList

Uses a web page containing the list of recently uploaded distributions to
CPAN. Uses KobeSearch by default, but another similar page can be requested.

=back

=for readme continue

=head1 CAVEATS

This is a proto-type release. Use with caution and supervision.

The current version has a very primitive interface and limited
functionality.  Future versions may have a lot of options.

There is always a risk associated with automatically downloading and
testing code from CPAN, which could turn out to be malicious or
severely buggy.  Do not run this on a critical machine.

This module uses the backend of CPANPLUS to do most of the work, so is
subject to any bugs of CPANPLUS.

=head1 SUGGESTIONS AND BUG REPORTING

Please submit suggestions and report bugs to the CPAN Bug Tracker at
L<http://rt.cpan.org>.

There is a SourceForge project site for CPAN::YACSmoke at
L<http://sourceforge.net/projects/yacsmoke>.

=head1 SEE ALSO

The CPAN Testers Website at L<http://testers.cpan.org> has information
about the CPAN Testing Service.

For additional information, see the documentation for these modules:

  CPANPLUS
  Test::Reporter

=head1 AUTHORS

Robert Rothenberg <rrwo at cpan.org>

Barbie <barbie at cpan.org>, for Miss Barbell Productions,
L<http://www.missbarbell.co.uk>

=head2 Acknowledgements

Jos Boumans <kane at cpan.org> for writing L<CPANPLUS>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Robert Rothenberg.  All Rights Reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
