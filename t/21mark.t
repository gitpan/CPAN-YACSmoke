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

#is(mark('Games-Trackword-1.02','unknown'),'unknown');
#is(mark('Games-Trackword-1.02'),'unknown');
#is(mark('Games-Trackword-1.02','pass'),'pass');
#is(mark('Games-Trackword-1.02'),'pass');

