use Test::More tests => 5;

use CPAN::YACSmoke;
use CPAN::YACSmoke::Plugin::Recent;
use CPANPLUS::Configure;

my $conf = CPANPLUS::Configure->new();
my $smoke = {
    conf    => $conf,
};
bless $smoke, 'CPAN::YACSmoke';

my $self  = {
    smoke   => $smoke,
    recent_list_path => '.'
};

my $plugin = CPAN::YACSmoke::Plugin::Recent->new($self);
isa_ok($plugin,'CPAN::YACSmoke::Plugin::Recent');

my @list = $plugin->download_list();
ok(@list > 0);

$self  = {
    smoke   => $smoke,
    recent_list_path => '.',
    recent_list_age => 1
};

$plugin = CPAN::YACSmoke::Plugin::Recent->new($self);
isa_ok($plugin,'CPAN::YACSmoke::Plugin::Recent');

my @list2 = $plugin->download_list();
ok(@list2 > 0);

{
  local $TODO = 'Sometimes the downloaded list differs';
  is_deeply(\@list,\@list2);
}


