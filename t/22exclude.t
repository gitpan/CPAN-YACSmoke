use Test::More tests => 1;

use CPAN::YACSmoke;

SKIP: {
	skip "Cannot test due to CPANPLUS hooks", 1;
}

## NOTES:
## Can't test the following inside CPANPLUS, as there is a copy of
## CPANPLUS::Backend already instanstiated, which will override any
## settings, including the registering callbacks, which are used to
## collect the reports

#my @list = excluded();
#ok(@list > 0);

#my @distros = (
#    'R/RR/RRWO/CPAN-YACSmoke-0.01.tar.gz',
#    'P/PE/PETDANCE/WWW-Mechanize-1.00.tar.gz'
#);
#my @expected = (
#    'P/PE/PETDANCE/WWW-Mechanize'
#);
#my @list = excluded(@distros);
#is_deeply(\@list,\@expected);

