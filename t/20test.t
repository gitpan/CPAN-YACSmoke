use Test::More tests => 1;

use CPAN::YACSmoke;

my $trail;

my %config = (
    audit_log => 'audit.log',
	audit_cb  => \&myaudit,
    verbose => 0
);

SKIP: {
	skip "Cannot test due to CPANPLUS hooks", 1;
}

## NOTES:
## Can't test the following inside CPANPLUS, as there is a copy of
## CPANPLUS::Backend already instanstiated, which will override any
## settings, including the registering callbacks, which are used to
## collect the reports

#eval{test(\%config, 'Games-Trackword-1.02.tar.gz')};
#like($trail,qr/Ignoring Games-Trackword-1.02/);

#my @lines = eval {test('B/BA/BARBIE/Games-Trackword-1.02.tar.gz')};
#$text = join('',@lines);
#like($text,qr!All tests successful!s);
#is(mark('Games-Trackword-1.02'),'pass');

sub myaudit {
	$trail .= join("\n",@_) . "\n";
}