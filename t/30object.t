use Test::More tests => 1;

use CPAN::YACSmoke;

my %config = ();

SKIP: {
	skip "Cannot test due to CPANPLUS hooks", 1;
}

## NOTES:
## Can't test the following inside CPANPLUS, as there is a copy of
## CPANPLUS::Backend already instanstiated, which will override any
## settings, including the registering callbacks, which are used to
## collect the reports

#my $smoker = CPAN::YACSmoke->new(%config);
#isa_ok($smoker,'CPAN::YACSmoke');
#
#ok($smoker->homedir());
#ok($smoker->basedir());
