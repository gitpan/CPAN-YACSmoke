use Module::Build;

my $build = Module::Build->new
    (
     module_name => 'CPAN::YACSmoke',
     license => 'perl',
     requires => {
       'perl'                       => '5.6.1',
       'CPANPLUS'                   => 0.051,
       'Carp'			    => 0,
       'Config::IniFiles'	    => 0,
       'File::HomeDir'              => 0.06,
       'File::Spec'                 => 0,
       'IO::File'                   => 0,    # *::Driver::Recent
       'LWP::Simple'                => 0,
       'Module::Pluggable'	    => 2.5,
       'Path::Class'                => 0,
       'POSIX'                      => 0,
       'Regexp::Assemble'           => 0.06,
       'SDBM_File'                  => 0,
       'Sort::Versions'             => 1.5,
       'Test::Reporter'             => 1.25,
       'URI'                        => 0,
       'YAML'                       => 0,
       'if'                         => 0.0401,
     },
     recommends => {
       'CPANPLUS'                   => 0.055,
       'File::HomeDir::Win32'       => 0.02, # for Win32 only
       'Pod::Readme'                => 0.04,
       'Test::Pod'                  => 1.00,
       'Test::Pod::Coverage'        => 0,
       'Test::Portability::Files'   => 0,
       'Test::Prereq'               => 0,
       'Test::Reporter'             => 1.27,
       'YAML'                       => 0.35, #
     },
     build_requires => {
       'File::Temp'                 => 0,
       'Test::More'                 => 0,
     },
     create_makefile_pl => 'traditional',
     create_readme      => 0,
     dist_author        => 'Robert Rothenberg <rrwo at cpan.org>, Barbie <barbie at cpan.org>',
     sign               => 1,
);

$build->create_build_script;
