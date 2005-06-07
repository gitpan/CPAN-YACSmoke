use Test::More tests => 2;

use CPAN::YACSmoke::Plugin::PlainTextList;

my $self  = {
	data => 't/12datalist.txt',
};

my $class = 'CPAN::YACSmoke::Plugin::PlainTextList';
my $plugin = $class->new($self);
isa_ok($plugin,$class);

my @list = $plugin->download_list();
is(@list, 22);

