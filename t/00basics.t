use Test::More tests => 3;
BEGIN { 
    use_ok CPAN::YACSmoke;
    use_ok CPAN::YACSmoke::Plugin::Recent;
    use_ok CPAN::YACSmoke::Plugin::SmokeDB;
}
