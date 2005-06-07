use Test::More tests => 4;
BEGIN { 
    use_ok CPAN::YACSmoke;
    use_ok CPAN::YACSmoke::Plugin::PlainTextList;
    use_ok CPAN::YACSmoke::Plugin::Recent;
    use_ok CPAN::YACSmoke::Plugin::SmokeDB;
}
