use Module::Build;

my $build = Module::Build->new
    (
     module_name => 'CPAN::YACSmoke',
     license => 'perl',
     requires => {
       'perl'                       => '5.6.1',
       'CPANPLUS'                   => 0.051,
       'CPANPLUS::Backend'          => 0,
       'CPANPLUS::Configure'        => 0,
       'CPANPLUS::Error'            => 0,
       'Carp'			    => 0,
       'Config::IniFiles'	    => 0,
       'File::HomeDir'              => 0.06,
       'File::Spec'                 => 0.88,
       'File::Spec::Functions'      => 0,
       'IO::File'                   => 0,    # Recent
       'LWP::Simple'                => 0,
       'Module::Pluggable'	    => 2.5,
       'POSIX'                      => 0,
       'Regexp::Assemble'           => 0.06,
       'SDBM_File'                  => 0,
       'Sort::Versions'             => 1.5,
       'Test::Reporter'             => 1.25,
       'URI'                        => 0,
     },
     recommends => {
       'CPANPLUS'                   => 0.052,
       'Test::Reporter'             => 1.27,
     },
     build_requires => {
       'Test::More'                 => 0,
     },
     create_makefile_pl => 'traditional',
     create_readme      => 0,
     dist_author        => 'Robert Rothenberg <rrwo at cpan.org>',
     sign               => 1,
);

$build->create_build_script;
